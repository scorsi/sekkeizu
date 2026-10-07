# Branche home-manager dans le système (nix-darwin ou NixOS).
# Le host choisit ensuite ses fonctionnalités home via `home-manager.users.<owner>.imports`.
{ config, inputs, ... }:
let
  owner = config.sekkeizu.owner.name;
  hmStateVersion = config.sekkeizu.stateVersions.homeManager;

  common = {
    home-manager = {
      useGlobalPkgs = true; # même nixpkgs (et overlays) que le système
      useUserPackages = true; # paquets dans le profil système de l'utilisateur
      # Un fichier existant (ex. ~/.config/fish/config.fish) est renommé au lieu de bloquer le switch.
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
