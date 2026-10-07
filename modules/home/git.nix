# git : identité depuis sekkeizu.owner, commits signés en SSH, diffs avec delta.
#
# Signature : git signe avec la clé FIDO2 du device réellement branché (YubiKey ou Thetis),
# détecté via fido2-token (aaguid) et non l'ordre de l'agent SSH.
# Sur le serveur, l'agent du laptop arrive par `ssh -A`.
# Les deux clés publiques sont à ajouter sur GitHub comme « Signing keys ».
{ config, ... }:
let
  inherit (config.sekkeizu) owner;
in
{
  flake.modules.homeManager.git =
    { pkgs, lib, ... }:
    let
      # OpenSSH de nixpkgs : celui de macOS ne gère pas les clés FIDO2 (ed25519-sk).
      ssh = pkgs.openssh;
      # fido2-token : identifie le modèle (aaguid) des devices FIDO2 branchés.
      fido2 = pkgs.libfido2;

      # Clés dont la signature est reconnue (`git log --show-signature`).
      allowedSigners = pkgs.writeText "allowed_signers" (
        builtins.concatStringsSep "\n" (map (k: "${owner.email} ${k.key}") owner.sshKeys) + "\n"
      );

      # Clé du device FIDO2 réellement branché (matché par aaguid), au format attendu par git.
      # L'id de device (DevSrvsID:<n> sur macOS) change à chaque branchement : toujours relister,
      # jamais le mettre en cache.
      signingKeyCommand = pkgs.writeShellScript "git-ssh-signing-key" ''
        while IFS= read -r line; do
          [ -n "$line" ] || continue
          dev=''${line%%: *}
          aaguid=""
          while IFS= read -r info; do
            case "$info" in
              aaguid:*) aaguid=''${info#aaguid: } ;;
            esac
          done <<< "$(${fido2}/bin/fido2-token -I "$dev" 2>/dev/null)"
          case "$aaguid" in
            ${lib.concatMapStringsSep "\n            " (
              k: ''"${k.aaguid}") echo "key::${k.key}"; exit 0 ;;''
            ) owner.sshKeys}
          esac
        done <<< "$(${fido2}/bin/fido2-token -L 2>/dev/null)"
        echo "aucun device FIDO2 reconnu branché" >&2
        exit 1
      '';
    in
    {
      programs.git = {
        enable = true;
        settings = {
          user = {
            name = owner.fullName;
            inherit (owner) email;
          };

          commit.gpgSign = true;
          tag.gpgSign = true;
          gpg = {
            format = "ssh";
            ssh = {
              program = "${ssh}/bin/ssh-keygen";
              defaultKeyCommand = "${signingKeyCommand}";
              allowedSignersFile = "${allowedSigners}";
            };
          };

          init.defaultBranch = "main";
          pull.rebase = true;
          push.autoSetupRemote = true;
          rebase.autoStash = true;
          merge.conflictStyle = "zdiff3";
          diff.colorMoved = "default";
        };
        ignores = [
          ".DS_Store"
          ".direnv/"
          "result"
          "result-*"
          "*~"
        ];
      };

      # delta : diffs colorés avec numéros de ligne (thème via catppuccin).
      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          line-numbers = true;
          navigate = true;
        };
      };
    };
}
