# Where each service of the lab can be reached. Everything that needs a service's address (Caddy,
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
        address = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            IP to pin the name to where DNS cannot be trusted: Go programs on macOS (the runner) ignore
            Tailscale's MagicDNS, which is not the system resolver there.
          '';
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
