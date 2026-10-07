# Réglages Nix communs à toutes les machines.
# nix-darwin gère Nix lui-même (`nix.enable = true`, valeur par défaut) : c'est ce qui
# rend `nix.gc`, `nix.optimise` et plus tard `nix.linux-builder` disponibles.
{ config, ... }:
let
  owner = config.sekkeizu.owner.name;

  settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Permet à l'utilisateur de pousser des closures (nixos-rebuild --target-host, builders).
    trusted-users = [
      "root"
      owner
    ];
    # Un build qui échoue n'arrête pas les autres : plus d'erreurs remontées par switch.
    keep-going = true;
    warn-dirty = false;
  };
in
{
  flake.modules.darwin.nix = {
    nix = {
      inherit settings;
      # GC hebdomadaire (dimanche 03:15) : indispensable avec 256 Go.
      gc = {
        automatic = true;
        interval = {
          Weekday = 0;
          Hour = 3;
          Minute = 15;
        };
        options = "--delete-older-than 14d";
      };
      optimise.automatic = true;
    };
  };

  flake.modules.nixos.nix = {
    nix = {
      inherit settings;
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };
      optimise.automatic = true;
    };
  };
}
