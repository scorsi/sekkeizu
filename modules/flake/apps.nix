# Apps du flake, via `nix run .#<nom>` :
#   switch → rebuild + diff des générations (sudo demandé par darwin-rebuild)
#   check  → nix flake check
#   fmt    → nix fmt
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
