# Homebrew 100 % déclaratif.
#  - nix-homebrew installe et épingle Homebrew lui-même.
#  - nix-darwin (`homebrew.*`) gère ce qu'il installe.
#  - `cleanup = "zap"` : tout cask/formule absent de la liste est désinstallé au switch,
#    avec ses fichiers de config. Supprimer une app = retirer sa ligne.
{ config, inputs, ... }:
let
  owner = config.sekkeizu.owner.name;
in
{
  flake.modules.darwin.homebrew = {
    imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];

    nix-homebrew = {
      enable = true;
      user = owner;
      # Reprend une installation Homebrew existante au lieu d'échouer.
      autoMigrate = true;
      # Taps déclarés uniquement (`brew tap` à la main est refusé).
      # homebrew/core et homebrew/cask passent par l'API JSON de Homebrew : pas besoin de les cloner.
      mutableTaps = false;
      taps = { };
    };

    homebrew = {
      enable = true;
      onActivation = {
        cleanup = "zap";
        # Pas de mise à jour implicite : les versions bougent quand on le décide.
        autoUpdate = false;
        upgrade = false;
      };

      # ─── Applications ────────────────────────────────────────────────
      # Ajouter ici les apps graphiques (casks), ex. : "tailscale-app" "utm"
      casks = [ ];

      # Formules sans équivalent dans nixpkgs (à éviter : préférer nixpkgs).
      brews = [ ];

      # Apps du Mac App Store : { "Xcode" = 497799835; } (nécessite d'être connecté à l'App Store).
      masApps = { };
    };
  };
}
