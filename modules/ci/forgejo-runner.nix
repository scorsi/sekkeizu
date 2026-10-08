# Forgejo Actions runners, on the host executor: jobs run straight on the machine, as an
# unprivileged user, with the tools of `hostPackages` in their PATH (Nix included on ishizue).
#
# Why the host executor and not podman on ishizue: a single user, private repositories and a 6 GB
# VM. Containers would mean a second layer (rootless podman, image pulls onto the persistent disk,
# 1 GB of tmpfs for layers) to isolate code that only the owner pushes; the job gets the same
# isolation from the systemd sandbox below (no write access outside its own directories) and from
# being an ordinary user of the Nix daemon. Containers are worth it the day someone else pushes.
#
# Registration: no token to fetch from the web UI. The shared secret in sops is pre-registered by
# Forgejo (modules/nixos/forgejo.nix, `forgejo-cli actions register`), and the runner connects with it
# (`server.connections`); its UUID is the first 16 bytes of the secret, like Forgejo derives it.
# The secret is `forgejo-runner-<host>` in secrets/<host>/secrets.yaml (jiban's is in ishizue's too).
{ config, lib, ... }:
let
  inherit (config.sekkeizu) services forgejoRunners;
  forgejo = services.forgejo;
  user = "forgejo-runner";

  # Runs as the runner's user, with CONFIG_DIR, SECRET_FILE and WORK_DIR set by the caller.
  writeConfig = labels: ''
    secret=$(< "$SECRET_FILE")
    hex=$(printf %s "''${secret:0:16}" | od -An -tx1 | tr -d ' \n')
    uuid="''${hex:0:8}-''${hex:8:4}-''${hex:12:4}-''${hex:16:4}-''${hex:20:12}"
    cat > "$CONFIG_DIR/config.yaml" <<YAML
    log:
      level: info
    runner:
      capacity: 1
      labels: [${lib.concatMapStringsSep ", " (l: ''"${l}"'') labels}]
    host:
      workdir_parent: $WORK_DIR
    server:
      connections:
        forgejo:
          url: ${forgejo.url}/
          uuid: $uuid
          token_url: file:$SECRET_FILE
    YAML
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

        # The registered host name must resolve to this machine, whatever Tailscale DNS does at boot.
        networking.hosts."127.0.0.1" = [ forgejo.host ];

        sekkeizu.persist.directories = [
          {
            directory = stateDir;
            inherit user;
            group = user;
            mode = "0750";
          }
        ];

        sops.secrets."forgejo-runner-${name}".owner = user;

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
            pkgs.gitMinimal
            pkgs.gnugrep
            pkgs.gnused
            pkgs.gnutar
            pkgs.gzip
            pkgs.nix
            pkgs.nodejs
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
            ExecStart =
              let
                start = pkgs.writeShellScript "forgejo-runner-start" ''
                  set -euo pipefail
                  CONFIG_DIR=$RUNTIME_DIRECTORY
                  SECRET_FILE=${config.sops.secrets."forgejo-runner-${name}".path}
                  WORK_DIR=${stateDir}/work
                  ${writeConfig forgejoRunners.${name}.labels}
                  exec ${lib.getExe pkgs.forgejo-runner} daemon --config "$CONFIG_DIR/config.yaml"
                '';
              in
              start;
            Restart = "on-failure";
            RestartSec = 5;

            # Jobs are the owner's own code, but a runaway one must not take Forgejo down with it.
            MemoryMax = "3G";
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

      # The runner is a Go binary with its own resolver: it reads /etc/hosts, not MagicDNS.
      system.activationScripts.postActivation.text = lib.mkOrder 1550 ''
        install -d -m 700 -o ${macUser} -g ${macUser} ${stateDir}
        ${lib.optionalString (forgejo.address != null) ''
          sed -i "" '/# sekkeizu-forgejo$/d' /etc/hosts
          echo "${forgejo.address} ${forgejo.host} # sekkeizu-forgejo" >> /etc/hosts
        ''}
      '';

      launchd.daemons.forgejo-runner.serviceConfig = {
        ProgramArguments = [
          "${pkgs.writeShellScript "forgejo-runner-start" ''
            set -euo pipefail
            CONFIG_DIR=${stateDir}
            SECRET_FILE=${secretFile}
            WORK_DIR=${stateDir}/work
            ${writeConfig forgejoRunners.${name}.labels}
            exec ${lib.getExe pkgs.forgejo-runner} daemon --config "$CONFIG_DIR/config.yaml"
          ''}"
        ];
        UserName = macUser;
        GroupName = macUser;
        WorkingDirectory = stateDir;
        EnvironmentVariables = {
          HOME = stateDir;
          PATH = "${
            lib.makeBinPath [
              pkgs.bash
              pkgs.coreutils
              pkgs.gitMinimal
              pkgs.nodejs
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
