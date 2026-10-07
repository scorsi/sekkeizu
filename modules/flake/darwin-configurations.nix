# flake-parts knows `nixosConfigurations` but not `darwinConfigurations`:
# declare the option so multiple files under modules/hosts/ can contribute to it.
{ lib, flake-parts-lib, ... }:
{
  options.flake = flake-parts-lib.mkSubmoduleOptions {
    darwinConfigurations = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = { };
      description = "nix-darwin configurations, one per macOS machine.";
    };
  };
}
