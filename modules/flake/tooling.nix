# Repo tooling, available on every system:
#   nix fmt              → format the whole repo
#   nix develop          → shell with the Nix linters
#   nix flake check      → evaluate everything + build the hosts for the current system
{
  config,
  lib,
  inputs,
  ...
}:
let
  # nix-darwin / NixOS configurations declared by files under modules/hosts/.
  darwinHosts = config.flake.darwinConfigurations or { };
  nixosHosts = config.flake.nixosConfigurations or { };
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      formatter = pkgs.nixfmt-tree;

      devShells.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          nixfmt
          statix # Nix anti-patterns
          deadnix # dead code
          shellcheck # scripts/bootstrap.sh
          just
          nix-output-monitor # `nom`, for more readable builds
          nvd # diff between two generations (used by `nix run .#switch`)
          sops # secrets/ editing (see .sops.yaml)
          age
          ssh-to-age # host SSH key -> age recipient
        ];
        # sops on macOS looks in ~/Library/Application Support by default.
        shellHook = ''
          export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
        '';
      };

      # On macOS, `nix flake check` builds every darwin host. NixOS hosts are checks of their own
      # system: evaluated from the Mac, built only where that system is native.
      checks =
        lib.optionalAttrs (system == "aarch64-darwin") (
          lib.mapAttrs' (name: host: lib.nameValuePair "darwin-${name}" host.system) darwinHosts
        )
        // lib.mapAttrs' (name: host: lib.nameValuePair "nixos-${name}" host.config.system.build.toplevel) (
          lib.filterAttrs (_: host: host.pkgs.stdenv.hostPlatform.system == system) nixosHosts
        );

      # darwin-rebuild pinned to the flake's nix-darwin version:
      # the bootstrap script uses it for the very first switch.
      packages = lib.optionalAttrs (lib.hasSuffix "darwin" system) {
        inherit (inputs.nix-darwin.packages.${system}) darwin-rebuild;
      };
    };
}
