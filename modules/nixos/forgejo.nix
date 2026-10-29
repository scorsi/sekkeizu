# Forgejo: Git forge, SQLite, behind genkan. Closed registrations; the owner's account is created
# by a oneshot (password in sops, set through a temporary API token so it never reaches a
# command line; SSH keys = owner.sshKeys), and Actions runners are pre-registered
# with secrets from sops, so a rebuilt machine needs no click in the web UI.
#
# Git over SSH uses Forgejo's built-in server on its own port, not the system sshd: that one stays
# key-only for the owner (AllowUsers) and never learns about a shared `git` account or about
# Forgejo's authorized_keys; Forgejo's server only speaks git, with the keys stored in Forgejo.
#
# Secrets (secrets/<host>/secrets.yaml): forgejo-admin-password, forgejo-runner-<name> per runner
# (40 hex chars: `openssl rand -hex 20`).
{ config, ... }:
let
  inherit (config.kiso) owner;
  inherit (config.sekkeizu) services forgejoRunners forgejoCi;
  web = services.forgejo;
  ssh = services.forgejo-ssh;
  internalPort = 3000;
  adminUser = owner.name;
in
{
  flake.modules.nixos.forgejo =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.forgejo;
      exe = lib.getExe cfg.package;
      api = "http://127.0.0.1:${toString internalPort}/api";
      env = {
        HOME = cfg.stateDir;
        FORGEJO_WORK_DIR = cfg.stateDir;
        FORGEJO_CUSTOM = cfg.customDir;
      };
      # Shared by the units below: nu commands to put before their `main`.
      helpers = ''
        def wait-for-forgejo [] {
          for _ in 1..120 {
            if (try { http get ${api}/healthz | ignore; true } catch { false }) { return }
            sleep 1sec
          }
          http get ${api}/healthz | ignore
        }

        def credential [name: string] {
          open --raw $"($env.CREDENTIALS_DIRECTORY)/($name)" | str trim --right --char (char nl)
        }

        source ${./forgejo-keys.nu}
        source ${./forgejo-token.nu}

        # Runs `action` with a token of the admin user, prefixed per unit so each one only ever
        # revokes its own.
        def provision-token [unit: string, scopes: string, action: closure] {
          let prefix = $"sekkeizu-provision-($unit)-"
          with-token {
            ^${exe} admin user generate-access-token --username ${builtins.toJSON adminUser} --token-name $"($prefix)(random uuid)" --scopes $scopes --raw | str trim
          } { revoke-tokens ${cfg.database.path} ${builtins.toJSON adminUser} $prefix } $action
        }

        # nu's http client runs in-process: the token stays out of every argv.
        def api-request [token: string, method: string, path: string, body: record] {
          let url = $"${api}/v1/($path)"
          let headers = [Authorization $"token ($token)"]
          match $method {
            GET => { http get --full --allow-errors --headers $headers $url }
            POST => { http post --full --allow-errors --headers $headers --content-type application/json $url $body }
            PATCH => { http patch --full --allow-errors --headers $headers --content-type application/json $url $body }
            DELETE => { http delete --full --allow-errors --headers $headers $url }
          }
        }
      '';
      # owner.sshKeys entries are "<type> <key> <comment>": the comment becomes the title.
      keysFile = pkgs.writeText "forgejo-admin-keys.json" (
        builtins.toJSON (
          map (
            k:
            let
              parts = lib.splitString " " k.key;
            in
            {
              title = lib.last parts;
              key = "${builtins.elemAt parts 0} ${builtins.elemAt parts 1}";
            }
          ) owner.sshKeys
        )
      );
      afterStateDir = {
        requires = [ "forgejo-state-dir.service" ];
        after = [ "forgejo-state-dir.service" ];
      };
      secretNames = [
        "forgejo-admin-password"
      ]
      ++ map (n: "forgejo-runner-${n}") (builtins.attrNames forgejoRunners);
    in
    {
      services.forgejo = {
        enable = true;
        database.type = "sqlite3";
        lfs.enable = false;

        settings = {
          server = {
            DOMAIN = web.host;
            ROOT_URL = "${web.url}/";
            # genkan runs on another node and reaches it over kekkai (kekkai.nix opens the port to it
            # only); the firewall keeps it closed everywhere else.
            HTTP_ADDR = "0.0.0.0";
            HTTP_PORT = internalPort;
            START_SSH_SERVER = true;
            BUILTIN_SSH_SERVER_USER = "git";
            SSH_DOMAIN = ssh.host;
            SSH_PORT = ssh.port;
            SSH_LISTEN_PORT = ssh.port;
            # Only reached through genkan's passthrough (genkan.nix), which sends the client's address
            # in a PROXY header; a connection without one is refused.
            SSH_SERVER_USE_PROXY_PROTOCOL = true;
            # Signed out, the generic landing page is all there is to see: go straight to the form.
            LANDING_PAGE = "login";
          };
          # Single-user forge: nothing is visible without logging in, and none of the multi-user
          # surface (organisations, user directory) exists. Names checked against Forgejo 15's
          # modules/setting/: the org creation switch lives in [admin], not [service].
          service = {
            DISABLE_REGISTRATION = true;
            REQUIRE_SIGNIN_VIEW = true;
            DEFAULT_ALLOW_CREATE_ORGANIZATION = false;
          };
          "service.explore" = {
            DISABLE_USERS_PAGE = true;
            DISABLE_ORGANIZATIONS_PAGE = true;
          };
          admin.DISABLE_REGULAR_ORG_CREATION = true;
          session.COOKIE_SECURE = true;
          actions.ENABLED = true;
          # Also drops the registry itself, not just the repository tab.
          packages.ENABLED = false;
          repository = {
            # `git push` to a repository that does not exist yet creates it (private).
            ENABLE_PUSH_CREATE_USER = true;
            # Kept: code, issues, pull requests, releases, Actions.
            DISABLED_REPO_UNITS = lib.concatStringsSep "," [
              "repo.wiki"
              "repo.ext_wiki"
              "repo.ext_issues"
              "repo.projects"
              "repo.packages"
            ];
          };
        };
      };

      sekkeizu.persist.directories = [
        {
          directory = cfg.stateDir;
          user = cfg.user;
          group = cfg.group;
          mode = "0750";
        }
      ];

      # The state directory is a bind mount from /persist. At a switch the mount unit is new, and
      # tmpfiles may have created custom/ underneath it, so the sandbox (ReadWritePaths) would not
      # find it (and the sandbox of the unit itself cannot run the fix): a separate unit waits for the mount and
      # creates the tree on top of it.
      systemd.services.forgejo-secrets = afterStateDir;
      systemd.services.forgejo = afterStateDir;
      systemd.services.forgejo-state-dir = {
        description = "Forgejo: state directory tree, on top of its mount";
        unitConfig.RequiresMountsFor = [ cfg.stateDir ];
        before = [
          "forgejo-secrets.service"
          "forgejo.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.systemd}/bin/systemd-tmpfiles --create --prefix=${cfg.stateDir}";
        };
      };

      # Read as root by the units below (LoadCredential); the runner's own file also gets an owner in forgejo-runner.nix.
      sops.secrets = lib.genAttrs secretNames (name: {
        restartUnits = [
          "forgejo-runners.service"
        ]
        ++ lib.optional (name == "forgejo-admin-password") "forgejo-admin.service";
      });

      systemd.services.forgejo-admin = {
        description = "Forgejo: owner account and SSH keys";
        wantedBy = [
          "multi-user.target"
          "forgejo.service"
        ];
        after = [ "forgejo.service" ];
        # Also provision again whenever Forgejo itself restarts.
        partOf = [ "forgejo.service" ];
        environment = env;
        path = [
          pkgs.coreutils
          pkgs.sqlite
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = cfg.user;
          Group = cfg.group;
          UMask = "0077";
          LoadCredential = "admin-password:${config.sops.secrets.forgejo-admin-password.path}";
          ExecStart = pkgs.writers.writeNu "forgejo-admin" ''
            ${helpers}
            def main [] {
              wait-for-forgejo
              let users = ^${exe} admin user list | lines | skip 1 | each { str trim | split row --regex '\s+' | get 1? }
              if ${builtins.toJSON adminUser} not-in $users {
                # The random password is replaced right below; it is printed, so keep it out of the journal.
                ^${exe} admin user create --admin --username ${builtins.toJSON adminUser} --email ${builtins.toJSON owner.email} --random-password --must-change-password=false | ignore
              }

              # A token, not basic auth: on rotation Forgejo still holds the previous password.
              provision-token forgejo-admin write:admin,write:user {|token|
                let user = ${builtins.toJSON adminUser} | url encode --all
                let body = {password: (credential admin-password), must_change_password: false}
                let response = api-request $token PATCH $"admin/users/($user)" $body
                if $response.status != 200 {
                  error make {msg: $"Forgejo PATCH admin/users/($user): HTTP ($response.status)"}
                }
                reconcile-owner-keys { |method, path, body| api-request $token $method $path $body } (open ${keysFile}) ${cfg.stateDir}/sekkeizu-owner-keys.json
              }
            }
          '';
        };
      };

      systemd.services.forgejo-runners = {
        description = "Forgejo: pre-register the Actions runners, give them read access to the private flakes";
        wantedBy = [
          "multi-user.target"
          "forgejo.service"
        ];
        requires = [ "forgejo-admin.service" ];
        after = [
          "forgejo.service"
          "forgejo-admin.service"
        ];
        partOf = [ "forgejo.service" ];
        environment = env;
        path = [
          pkgs.coreutils
          pkgs.sqlite
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = cfg.user;
          Group = cfg.group;
          UMask = "0077";
          LoadCredential = map (n: "${n}:${config.sops.secrets."forgejo-runner-${n}".path}") (
            builtins.attrNames forgejoRunners
          );
          ExecStart = pkgs.writers.writeNu "forgejo-runners" ''
            ${helpers}
            def main [] {
              wait-for-forgejo
              # Global scope (empty): usable by every repository. Already registered → nothing to do.
              # Label names only, the way the runner declares them when it connects: this unit runs
              # again at every Forgejo restart and overwrites the stored labels, and a stored
              # `linux:host` matches no `runs-on: linux`, so jobs would wait until the runner restarts.
              for r in (open ${
                pkgs.writeText "forgejo-runners.json" (
                  builtins.toJSON (
                    lib.mapAttrsToList (name: runner: {
                      inherit name;
                      labels = lib.concatMapStringsSep "," (l: builtins.head (lib.splitString ":" l)) runner.labels;
                    }) forgejoRunners
                  )
                )
              }) {
                # Forgejo 15 LTS declares secret-stdin as a string flag; its value is ignored.
                credential $r.name | ^${exe} forgejo-cli actions register --scope "" --name $r.name --labels $r.labels --secret-stdin=true
              }

              # CI fetches the private flakes this repo depends on over SSH: one read-only deploy key on
              # each (forgejo-ci-key in sops, written for the runners in forgejo-runner.nix).
              # users/<u>/repos sits under the user scope as well as the repository one.
              provision-token forgejo-runners read:user,write:repository {|token|
                reconcile-deploy-keys { |method, path, body| api-request $token $method $path $body } ${builtins.toJSON adminUser} ${builtins.toJSON forgejoCi.readRepos} ${builtins.toJSON forgejoCi.readKey} ${cfg.stateDir}/sekkeizu-deploy-keys.json
              }
            }
          '';
        };
      };
    };
}
