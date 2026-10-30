# Where each service of the lab can be reached. Everything that needs a service's address (genkan,
# Forgejo's ROOT_URL, the runners, the docs) reads it from here, never from a string of its own:
# the values live in endpoints.nix, so moving to real domain names is a change in that one file.
{ lib, ... }:
let
  inherit (lib) mkOption types;

  endpoint =
    { config, ... }:
    {
      options = {
        scheme = mkOption {
          type = types.str;
          default = "https";
          description = "URL scheme.";
        };
        host = mkOption {
          type = types.str;
          description = "DNS name the service answers on.";
        };
        aliases = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Other names the service still answers on (pinned like `host` by its clients).";
        };
        public = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Public names of a web service: their DNS points at torii-cdg, whose genkan forwards them
            by SNI to ishizue's PROXY listener (genkan.nix). Empty: overlay only.
          '';
        };
        address = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            IP to pin the name to where DNS cannot be trusted: jiban's runner (a Go program) would
            otherwise depend on annai answering before the resolver's fallback.
          '';
        };
        hostKey = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "SSH host key (`<type> <base64>`), for clients that must not trust on first use.";
        };
        port = mkOption {
          type = types.port;
          default = 443;
          description = "Port the service is reached on (the public one, not what the daemon binds behind a proxy).";
        };
        url = mkOption {
          type = types.str;
          readOnly = true;
          description = "scheme://host[:port], without a trailing slash; the port is left out when it is the scheme's default.";
          default =
            let
              implicit = {
                https = 443;
                http = 80;
              };
              suffix = lib.optionalString (
                (implicit.${config.scheme} or null) != config.port
              ) ":${toString config.port}";
            in
            "${config.scheme}://${config.host}${suffix}";
        };
      };
    };
in
{
  options.sekkeizu = {
    services = mkOption {
      type = types.attrsOf (types.submodule endpoint);
      default = { };
      description = "Addresses of the lab's services, by name.";
    };

    backupPullKey = mkOption {
      type = types.str;
      description = "Public half of jiban's former backup-pull key (private half: backup-pull-key in sops): the Storage Box subaccount still trusts it, for restoring the last restic repository (README, Backups).";
    };

    azukariOffsiteKey = mkOption {
      type = types.str;
      description = "Public half of azukari-server's key to the Storage Box `backup` subaccount (private half: azukari-offsite-key in secrets/hashira-01/azukari-offsite.yaml), installed by infra/stacks/storage.";
    };

    forgejoCi = {
      readKey = mkOption {
        type = types.str;
        description = "Public half of the runners' read-only deploy key (private half: forgejo-ci-key in sops).";
      };
      readRepos = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          The owner's Forgejo repositories the runners may read with that key: the private flakes
          this repo depends on, fetched over SSH by `nix flake check` and builds in CI.
        '';
      };
    };

    forgejoRunners = mkOption {
      description = ''
        Forgejo Actions runners, named after the machine they run on. Forgejo (ishizue) pre-registers
        each of them, which is why the registry is shared between hosts.
      '';
      default = { };
      type = types.attrsOf (
        types.submodule {
          options.labels = mkOption {
            type = types.listOf types.str;
            description = "Runner labels (`name:host`: jobs run directly on the machine).";
          };
        }
      );
    };
  };
}
