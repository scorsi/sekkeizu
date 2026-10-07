# flake-parts connaît `nixosConfigurations` mais pas `darwinConfigurations` :
# on déclare l'option pour que plusieurs fichiers de modules/hosts/ puissent y contribuer.
{ lib, flake-parts-lib, ... }:
{
  options.flake = flake-parts-lib.mkSubmoduleOptions {
    darwinConfigurations = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = "Configurations nix-darwin, une par machine macOS.";
    };
  };
}
