# Outillage du repo, disponible sur chaque système :
#   nix fmt              → formate tout le repo
#   nix develop          → shell avec les linters Nix
#   nix flake check      → évalue tout + construit les hosts du système courant
{
  config,
  lib,
  inputs,
  ...
}:
let
  # Configurations nix-darwin déclarées par les fichiers de modules/hosts/.
  darwinHosts = config.flake.darwinConfigurations or { };
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      formatter = pkgs.nixfmt-tree;

      devShells.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          nixfmt
          statix # anti-patterns Nix
          deadnix # code mort
          shellcheck # scripts/bootstrap.sh
          just
        ];
      };

      # Sur macOS, `nix flake check` construit chaque host darwin.
      checks = lib.optionalAttrs (system == "aarch64-darwin") (
        lib.mapAttrs' (name: host: lib.nameValuePair "darwin-${name}" host.system) darwinHosts
      );

      # darwin-rebuild épinglé sur la version de nix-darwin du flake.lock :
      # le bootstrap l'utilise pour le tout premier switch.
      packages = lib.optionalAttrs (lib.hasSuffix "darwin" system) {
        inherit (inputs.nix-darwin.packages.${system}) darwin-rebuild;
      };
    };
}
