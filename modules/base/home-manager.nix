# Wires home-manager into the system (nix-darwin or NixOS).
# Each host then picks its home features via `home-manager.users.<owner>.imports`.
{ config, inputs, ... }:
let
  owner = config.sekkeizu.owner.name;
  hmStateVersion = config.sekkeizu.stateVersions.homeManager;

  common = {
    home-manager = {
      useGlobalPkgs = true; # same nixpkgs (and overlays) as the system
      useUserPackages = true; # packages in the user's system profile
      # An existing file (e.g. ~/.config/fish/config.fish) gets renamed instead of blocking the switch.
      backupFileExtension = "before-home-manager";
      users.${owner}.home.stateVersion = hmStateVersion;
    };
  };
in
{
  flake.modules.darwin.home-manager = {
    imports = [
      inputs.home-manager.darwinModules.home-manager
      common
    ];
  };

  flake.modules.nixos.home-manager = {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      common
    ];
  };
}
