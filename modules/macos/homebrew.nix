# Homebrew, fully declarative.
#  - nix-homebrew installs and pins Homebrew itself.
#  - nix-darwin (`homebrew.*`) manages what it installs.
#  - `cleanup = "zap"`: any cask/formula absent from the list is uninstalled on switch,
#    including its config files. Removing an app = removing its line.
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
      # Adopts an existing Homebrew install instead of failing.
      autoMigrate = true;
      # Only declared taps (`brew tap` by hand is rejected).
      # homebrew/core and homebrew/cask go through Homebrew's JSON API: no need to clone them.
      mutableTaps = false;
      taps = { };
    };

    homebrew = {
      enable = true;
      onActivation = {
        cleanup = "zap";
        # No implicit updates: versions move when decided explicitly.
        autoUpdate = false;
        upgrade = false;
      };

      # ─── Applications ────────────────────────────────────────────────
      # Add GUI apps (casks) here, e.g.: "tailscale-app" "utm"
      casks = [ ];

      # Formulas with no nixpkgs equivalent (avoid: prefer nixpkgs).
      brews = [ ];

      # Mac App Store apps: { "Xcode" = 497799835; } (requires being signed into the App Store).
      masApps = { };
    };
  };
}
