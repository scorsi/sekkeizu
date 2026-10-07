# Nix settings common to all machines.
# nix-darwin manages Nix itself (`nix.enable = true`, the default): that's what
# makes `nix.gc`, `nix.optimise`, and later `nix.linux-builder` available.
{ config, ... }:
let
  owner = config.sekkeizu.owner.name;

  settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Lets the user push closures (nixos-rebuild --target-host, builders).
    trusted-users = [
      "root"
      owner
    ];
    # A failing build doesn't stop the others: more errors surfaced per switch.
    keep-going = true;
    warn-dirty = false;
  };
in
{
  flake.modules.darwin.nix = {
    nix = {
      inherit settings;
      # Weekly GC (Sunday 03:15): a must with 256 GB.
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
