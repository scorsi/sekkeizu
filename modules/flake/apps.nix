# Flake apps, via `nix run .#<name>`:
#   switch → rebuild + diff generations (sudo asked by darwin-rebuild)
#   check  → nix flake check
#   fmt    → nix fmt
#   set-autologin-password [host] → encrypt the login password as a kcpassword secret (see modules/macos/autologin.nix)
{ lib, inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (lib.hasSuffix "darwin" system) {
      apps = {
        switch = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "switch" ''
              set -euo pipefail
              repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              host=$(/bin/hostname -s)
              before=$(readlink -f /run/current-system)

              log=$(mktemp -t darwin-switch-XXXXXX.log)
              echo "Journal : $log"

              sudo ${
                inputs.nix-darwin.packages.${system}.darwin-rebuild
              }/bin/darwin-rebuild switch --flake "$repo#$host" 2>&1 | tee "$log"

              after=$(readlink -f /run/current-system)
              if [ "$before" != "$after" ]; then
                echo "--- nvd diff ---"
                ${pkgs.nvd}/bin/nvd diff "$before" "$after"
              else
                echo "Pas de changement de génération."
              fi
            ''
          );
        };

        check = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "check" ''
              set -euo pipefail
              repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              exec nix flake check "$repo"
            ''
          );
        };

        set-autologin-password = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "set-autologin-password" ''
              set -euo pipefail
              repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              host=''${1:-$(/bin/hostname -s)}
              cd "$repo"
              mkdir -p "secrets/$host"
              exec ${pkgs.python3}/bin/python3 -I ${./set-autologin-password.py} \
                ${pkgs.sops}/bin/sops "secrets/$host/kcpassword"
            ''
          );
        };

        fmt = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "fmt" ''
              set -euo pipefail
              repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              exec nix fmt "$repo"
            ''
          );
        };
      };
    };
}
