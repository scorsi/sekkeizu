# Forgejo: Git forge, SQLite, behind Caddy. Closed registrations; the owner's account is created
# by a oneshot (password in sops, SSH keys = owner.sshKeys), and Actions runners are pre-registered
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
  inherit (config.sekkeizu) owner services forgejoRunners;
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
      waitForForgejo = ''
        for _ in $(seq 120); do
          curl -fsS ${api}/healthz >/dev/null 2>&1 && break
          sleep 1
        done
        curl -fsS ${api}/healthz >/dev/null
      '';
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

        # Daily archive of the database, repositories and config; tmpfiles removes the ones older than `age`.
        dump = {
          enable = true;
          backupDir = "/persist/backups/forgejo";
          age = "7d";
        };

        settings = {
          server = {
            DOMAIN = web.host;
            ROOT_URL = "${web.url}/";
            HTTP_ADDR = "127.0.0.1";
            HTTP_PORT = internalPort;
            START_SSH_SERVER = true;
            BUILTIN_SSH_SERVER_USER = "git";
            SSH_DOMAIN = ssh.host;
            SSH_PORT = ssh.port;
            SSH_LISTEN_PORT = ssh.port;
          };
          service.DISABLE_REGISTRATION = true;
          session.COOKIE_SECURE = true;
          actions.ENABLED = true;
          # `git push` to a repository that does not exist yet creates it (private).
          repository.ENABLE_PUSH_CREATE_USER = true;
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

      services.caddy.virtualHosts.${web.url}.extraConfig = ''
        reverse_proxy 127.0.0.1:${toString internalPort}
      '';

      # Read as root by the units below (LoadCredential); the runner's own file also gets an owner in forgejo-runner.nix.
      sops.secrets = lib.genAttrs secretNames (_: { });

      systemd.services.forgejo-admin = {
        description = "Forgejo: owner account and SSH keys";
        wantedBy = [ "multi-user.target" ];
        after = [ "forgejo.service" ];
        # Runs again whenever Forgejo restarts (new password in sops, new key in owner.nix).
        partOf = [ "forgejo.service" ];
        environment = env;
        path = [
          pkgs.curl
          pkgs.gawk
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = cfg.user;
          Group = cfg.group;
          LoadCredential = "admin-password:${config.sops.secrets.forgejo-admin-password.path}";
        };
        script = ''
          ${waitForForgejo}
          password=$(< "$CREDENTIALS_DIRECTORY/admin-password")

          if ${exe} admin user list | awk 'NR > 1 { print $2 }' | grep -qx ${lib.escapeShellArg adminUser}; then
            ${exe} admin user change-password --username ${lib.escapeShellArg adminUser} \
              --password "$password" --must-change-password=false
          else
            ${exe} admin user create --admin --username ${lib.escapeShellArg adminUser} \
              --email ${lib.escapeShellArg owner.email} --password "$password" --must-change-password=false
          fi

          # Basic auth over loopback; the credentials go through a curl config, not the command line.
          add_key() {
            code=$(curl -sS -o /dev/null -w '%{http_code}' \
              --config <(printf 'user = "%s:%s"\n' ${lib.escapeShellArg adminUser} "$password") \
              -H 'Content-Type: application/json' \
              -d "$(printf '{"title":"%s","key":"%s"}' "$1" "$2")" \
              ${api}/v1/admin/users/${adminUser}/keys)
            # 422: the key is already there.
            case $code in 201 | 422) ;; *) echo "adding key '$1': HTTP $code" >&2; exit 1 ;; esac
          }
          ${lib.concatMapStringsSep "\n" (
            k:
            let
              parts = lib.splitString " " k.key;
            in
            "add_key ${lib.escapeShellArg (lib.last parts)} ${lib.escapeShellArg "${builtins.elemAt parts 0} ${builtins.elemAt parts 1}"}"
          ) owner.sshKeys}
        '';
      };

      systemd.services.forgejo-runners = {
        description = "Forgejo: pre-register the Actions runners";
        wantedBy = [ "multi-user.target" ];
        after = [ "forgejo.service" ];
        partOf = [ "forgejo.service" ];
        environment = env;
        path = [ pkgs.curl ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = cfg.user;
          Group = cfg.group;
          LoadCredential = map (n: "${n}:${config.sops.secrets."forgejo-runner-${n}".path}") (
            builtins.attrNames forgejoRunners
          );
        };
        script = ''
          ${waitForForgejo}
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: runner: ''
              # Global scope (empty): usable by every repository. Already registered → nothing to do.
              ${exe} forgejo-cli actions register --scope "" --name ${lib.escapeShellArg name} \
                --labels ${lib.escapeShellArg (lib.concatStringsSep "," runner.labels)} \
                --secret "$(< "$CREDENTIALS_DIRECTORY/${name}")" \
                || echo "runner ${name}: registration refused (already registered?)" >&2
            '') forgejoRunners
          )}
        '';
      };
    };
}
