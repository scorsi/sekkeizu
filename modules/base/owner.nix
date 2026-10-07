# Compte de l'utilisateur principal sur chaque machine.
{ config, ... }:
let
  inherit (config.sekkeizu) owner;
in
{
  flake.modules.darwin.owner = {
    # Utilisateur visé par les réglages « par utilisateur » de nix-darwin
    # (system.defaults, homebrew, launchd.user.agents…).
    system.primaryUser = owner.name;

    # Le compte macOS existe déjà (créé par l'assistant de configuration) :
    # on le décrit sans le gérer (pas de `users.knownUsers`), nix-darwin ne le recrée donc pas.
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
