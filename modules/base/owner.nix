# Primary user account on each machine.
{ config, ... }:
let
  inherit (config.sekkeizu) owner;
in
{
  flake.modules.darwin.owner = {
    # Target user for nix-darwin's per-user settings (system.defaults, homebrew, launchd.user.agents…).
    system.primaryUser = owner.name;

    # The macOS account already exists (created by the setup assistant):
    # described here without being managed (no `users.knownUsers`), so nix-darwin never recreates it.
    users.users.${owner.name} = {
      inherit (owner) name;
      home = "/Users/${owner.name}";
      description = owner.fullName;
      openssh.authorizedKeys.keys = map (k: k.key) owner.sshKeys;
    };
  };

  flake.modules.nixos.owner = {
    users.users.${owner.name} = {
      isNormalUser = true;
      description = owner.fullName;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = map (k: k.key) owner.sshKeys;
    };
  };
}
