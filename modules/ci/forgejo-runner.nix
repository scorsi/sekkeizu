# Forgejo Actions runners, on the host executor: jobs run straight on the machine, as an
# unprivileged user, with the tools of `hostPackages` in their PATH (Nix included on ishizue).
#
# Why the host executor and not podman on ishizue: a single user, private repositories and an 8 GB
# VM. Containers would mean a second layer (rootless podman, image pulls onto the persistent disk,
# 1 GB of tmpfs for layers) to isolate code that only the owner pushes; the job gets the same
# isolation from the systemd sandbox below (no write access outside its own directories) and from
# being an ordinary user of the Nix daemon. Containers are worth it the day someone else pushes.
#
# Registration: no token to fetch from the web UI. The shared secret in sops is pre-registered by
# Forgejo (modules/nixos/forgejo.nix, `forgejo-cli actions register`), and the runner connects with it
# (`server.connections`); its UUID is the first 16 bytes of the secret, like Forgejo derives it.
# The secret is `forgejo-runner-<host>` in secrets/<host>/secrets.yaml (jiban's is in ishizue's too).
#
# sekkeizu's own CI unlocks its encrypted trees (.gitattributes) with the repo's git-crypt key,
# `git-crypt-key` (secrets/<host>/git-crypt-key, binary sops), at /run/secrets/git-crypt-key.
{ config, lib, ... }:
let
  inherit (config.sekkeizu) services forgejoRunners;
  forgejo = services.forgejo;
  forgejoSsh = services.forgejo-ssh;
  user = "forgejo-runner";

  # The runner's start script, as its user (HOME = its state directory): writes its config and SSH
  # setup, then becomes the runner.
  startRunner =
    pkgs:
    {
      name,
      configDir,
      secretFile,
      ciKeyFile,
      workDir,
    }:
    let
      config = pkgs.writeText "forgejo-runner-config.json" (
        builtins.toJSON {
          log.level = "info";
          runner = {
            capacity = 1;
            inherit (forgejoRunners.${name}) labels;
          };
          host.workdir_parent = workDir;
          server.connections.forgejo = {
            url = "${forgejo.url}/";
            token_url = "file:${secretFile}";
          };
        }
      );
    in
    pkgs.writers.writeNu "forgejo-runner-start" ''
      # Its UUID is the first 16 bytes of the secret, like Forgejo derives it.
      let hex = open --raw ${secretFile} | into binary | bytes at 0..15 | encode hex --lower
      let uuid = [0..7 8..11 12..15 16..19 20..31] | each { |r| $hex | str substring $r } | str join "-"
      open ${config} | upsert server.connections.forgejo.uuid $uuid | to yaml | save --force ${configDir}/config.yaml

      # The private flakes jobs fetch over git+ssh from Forgejo (sekkeizu.forgejoCi): read-only
      # deploy key, and Forgejo's host key pinned rather than trusted on first use.
      let ssh = $"($env.HOME)/.ssh"
      mkdir $ssh
      ^chmod 700 $ssh
      "[${forgejoSsh.host}]:${toString forgejoSsh.port} ${forgejoSsh.hostKey}\n" | save --force $"($ssh)/known_hosts"
      "Host ${forgejoSsh.host}\n  IdentityFile ${ciKeyFile}\n  IdentitiesOnly yes\n  StrictHostKeyChecking yes\n" | save --force $"($ssh)/config"

      exec ${lib.getExe pkgs.forgejo-runner} daemon --config ${configDir}/config.yaml
    '';
in
{
  flake.modules.nixos.forgejo-runner =
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.sekkeizu.forgejo-runner;
      name = config.networking.hostName;
      stateDir = "/var/lib/forgejo-runner";
    in
    {
      options.sekkeizu.forgejo-runner = {
        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Tools jobs need, on top of the base set.";
        };
        writablePaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "The only places outside its state directory the runner may write to.";
        };
        user = lib.mkOption {
          type = lib.types.str;
          default = user;
          readOnly = true;
          description = "Account the jobs run as.";
        };
      };

      config = {
        users.users.${user} = {
          isSystemUser = true;
          group = user;
          home = stateDir;
        };
        users.groups.${user} = { };

        # A nixosTest boots 2-3 VMs of ~400 MB each; on this small host, parallel builds starve them
        # into timeouts. One build at a time: a flake check's tests run in sequence.
        nix.settings = {
          max-jobs = 1;
          cores = 2;
        };

        # Builds run under nix-daemon, outside the runner's cgroup. Share one budget, including
        # manual daemon builds, leaving half of ishizue's 8 GiB / 4 vCPUs for its services.
        systemd.slices.ci.sliceConfig = {
          MemoryHigh = "3G";
          MemoryMax = "4G";
          MemorySwapMax = 0;
          CPUQuota = "200%";
        };
        systemd.services.nix-daemon.serviceConfig.Slice = "ci.slice";

        # Forgejo's names must resolve to this machine: ishizue asks Quad9, not annai (annai.nix), and
        # Tailscale DNS may not be up at boot.
        networking.hosts."127.0.0.1" = lib.unique [
          forgejo.host
          forgejoSsh.host
        ];

        sekkeizu.persist.directories = [
          {
            directory = stateDir;
            inherit user;
            group = user;
            mode = "0750";
          }
        ];

        sops.secrets."forgejo-runner-${name}" = {
          owner = user;
          restartUnits = [ "forgejo-runner.service" ];
        };
        sops.secrets.forgejo-ci-key.owner = user;
        sops.secrets.git-crypt-key = {
          sopsFile = ../../secrets/${name}/git-crypt-key;
          format = "binary";
          owner = user;
        };

        systemd.services.forgejo-runner = {
          description = "Forgejo Actions runner";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "forgejo.service"
            "forgejo-runners.service"
          ];
          path = [
            pkgs.bash
            pkgs.coreutils
            pkgs.curl
            pkgs.findutils
            pkgs.gawk
            pkgs.git-crypt
            pkgs.gitMinimal
            pkgs.gnugrep
            pkgs.gnused
            pkgs.gnutar
            pkgs.gzip
            pkgs.nix
            pkgs.nodejs
            pkgs.nushell # CI steps run in nu (.forgejo/workflows)
            pkgs.openssh
            pkgs.xz
          ]
          ++ cfg.extraPackages;
          environment.HOME = stateDir;
          serviceConfig = {
            User = user;
            Group = user;
            StateDirectory = "forgejo-runner";
            RuntimeDirectory = "forgejo-runner";
            WorkingDirectory = stateDir;
            # RuntimeDirectory: /run/forgejo-runner.
            ExecStart = startRunner pkgs {
              inherit name;
              configDir = "/run/forgejo-runner";
              secretFile = config.sops.secrets."forgejo-runner-${name}".path;
              ciKeyFile = config.sops.secrets.forgejo-ci-key.path;
              workDir = "${stateDir}/work";
            };
            Restart = "on-failure";
            RestartSec = 5;

            Slice = "ci.slice";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            ReadWritePaths = cfg.writablePaths;
          };
        };
      };
    };

  flake.modules.darwin.forgejo-runner =
    {
      config,
      pkgs,
      ...
    }:
    let
      name = config.networking.hostName;
      macUser = "_forgejo-runner";
      stateDir = "/var/lib/forgejo-runner";
      secretFile = config.sops.secrets."forgejo-runner-${name}".path;
    in
    {
      # A dedicated, hidden, non-admin account: jobs run with nothing but their own directory.
      users = {
        knownGroups = [ macUser ];
        knownUsers = [ macUser ];
        groups.${macUser} = {
          gid = 401;
          description = "Forgejo Actions runner";
        };
        users.${macUser} = {
          uid = 401;
          gid = 401;
          home = stateDir;
          createHome = false;
          isHidden = true;
          shell = "/usr/bin/false";
          description = "Forgejo Actions runner";
        };
      };

      sops.secrets."forgejo-runner-${name}".owner = macUser;
      sops.secrets.forgejo-ci-key.owner = macUser;
      sops.secrets.git-crypt-key = {
        sopsFile = ../../secrets/${name}/git-crypt-key;
        format = "binary";
        owner = macUser;
      };

      # The runner is a Go binary with its own resolver: pinned in /etc/hosts, it does not depend on
      # annai answering first (jiban's 9.9.9.9 fallback knows nothing of uchi, annai.nix).
      system.activationScripts.postActivation.text = lib.mkMerge [
        (lib.mkOrder 1550 "${pkgs.writers.writeNu "forgejo-runner-activate" ''
          ^/usr/bin/install -d -m 700 -o ${macUser} -g ${macUser} ${stateDir}
          ${lib.optionalString (forgejo.address != null) ''
            let hosts = open --raw /etc/hosts | lines | where { |l| not ($l | str ends-with "# sekkeizu-forgejo") }
            $hosts | append "${forgejo.address} ${forgejo.host} # sekkeizu-forgejo" | str join "\n" | $in + "\n" | save --force /etc/hosts
          ''}
        ''}")
        (lib.mkOrder 1650 config.system.activationScripts.forgejo-runner-secrets.text)
      ];

      # A file-level fingerprint also restarts the runner when another secret in the same file changes.
      system.activationScripts.forgejo-runner-secrets.text = ''
        if [ "$(cat /var/db/forgejo-runner.secrets 2>/dev/null)" != "${
          config.sops.secrets."forgejo-runner-${name}".sopsFileHash
        }" ]; then
          /bin/launchctl kickstart -k system/${config.launchd.daemons.forgejo-runner.serviceConfig.Label}
          printf '%s\n' '${
            config.sops.secrets."forgejo-runner-${name}".sopsFileHash
          }' > /var/db/forgejo-runner.secrets
        fi
      '';

      # `command`, not ProgramArguments: nix-darwin then waits for /nix/store, mounted after
      # launchd starts boot jobs (a missing program exits 78 and is never retried).
      launchd.daemons.forgejo-runner.command = "${startRunner pkgs {
        inherit name secretFile;
        configDir = stateDir;
        ciKeyFile = config.sops.secrets.forgejo-ci-key.path;
        workDir = "${stateDir}/work";
      }}";
      launchd.daemons.forgejo-runner.serviceConfig = {
        UserName = macUser;
        GroupName = macUser;
        WorkingDirectory = stateDir;
        EnvironmentVariables = {
          HOME = stateDir;
          PATH = "${
            lib.makeBinPath [
              pkgs.bash
              pkgs.coreutils
              pkgs.git-crypt
              pkgs.gitMinimal
              pkgs.nodejs
              pkgs.nushell # CI steps run in nu (.forgejo/workflows)
              # The daemon's own Nix: jobs build through it as an ordinary user (e.g. sekkeizu's CI).
              config.nix.package
            ]
          }:/usr/bin:/bin:/usr/sbin:/sbin";
        };
        RunAtLoad = true;
        KeepAlive = true;
        # Starts before the network and Tailscale are up at boot: wait a bit between attempts.
        ThrottleInterval = 15;
        StandardOutPath = "${stateDir}/runner.log";
        StandardErrorPath = "${stateDir}/runner.log";
      };
    };
}
