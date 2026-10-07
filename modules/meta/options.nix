# Options de niveau flake, partagées par toutes les fonctionnalités et tous les hosts.
# Chaque fichier de modules/ lit `config.homelab.*` dans sa fermeture, puis l'injecte
# dans ses morceaux darwin / nixos / homeManager.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.homelab = {
    owner = mkOption {
      description = "Utilisateur principal, identique sur toutes les machines.";
      type = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Nom court du compte (celui de `whoami` sur le Mac).";
          };
          fullName = mkOption {
            type = types.str;
            description = "Nom affiché (git, compte macOS).";
          };
          email = mkOption {
            type = types.str;
            description = "Email des commits git.";
          };
          sshKeys = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Clés publiques SSH autorisées à se connecter sur chaque machine.";
          };
        };
      };
    };

    repoDir = mkOption {
      type = types.str;
      default = "homelab";
      description = ''
        Emplacement du repo, relatif au home de l'utilisateur (là où le bootstrap le clone).
        Sert aux configs liées « en direct » au repo, comme celle de Neovim.
      '';
    };

    stateVersions = mkOption {
      description = ''
        Versions d'état de chaque outil. Elles figent des choix de compatibilité
        et ne se changent qu'en lisant les notes de version, jamais pour « mettre à jour ».
      '';
      type = types.attrsOf types.anything;
    };
  };
}
