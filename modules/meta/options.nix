# Flake-level options, shared by every feature and every host.
# Each file under modules/ reads `config.sekkeizu.*` in its closure, then injects
# it into its darwin / nixos / homeManager pieces.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.sekkeizu = {
    owner = mkOption {
      description = "Primary user, identical on every machine.";
      type = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Short account name (the one from `whoami` on the Mac).";
          };
          fullName = mkOption {
            type = types.str;
            description = "Display name (git, macOS account).";
          };
          email = mkOption {
            type = types.str;
            description = "Git commit email.";
          };
          sshKeys = mkOption {
            type = types.listOf (
              types.submodule {
                options = {
                  aaguid = mkOption {
                    type = types.str;
                    description = "FIDO2 model identifier (`fido2-token -I`), to find the plugged-in device at signing time.";
                  };
                  key = mkOption {
                    type = types.str;
                    description = "SSH public key (sk-ssh-ed25519@openssh.com ...).";
                  };
                };
              }
            );
            default = [ ];
            description = "FIDO2 keys allowed to connect to each machine.";
          };
        };
      };
    };

    repoDir = mkOption {
      type = types.str;
      default = "sekkeizu";
      description = ''
        Repo location, relative to the user's home (where the bootstrap script clones it).
        Used by configs linked "live" to the repo, like Neovim's.
      '';
    };

    stateVersions = mkOption {
      description = ''
        State version of each tool. These lock in compatibility choices
        and only change by reading release notes, never just to "update".
      '';
      type = types.attrsOf types.anything;
    };
  };
}
