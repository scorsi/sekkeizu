# git : identité depuis sekkeizu.owner, commits signés en SSH, diffs avec delta.
#
# Signature : git signe avec la clé FIDO2 présente dans l'agent SSH (YubiKey ou Thetis,
# celle qui est branchée ; agent et OpenSSH compatible : feature `ssh`).
# Sur le serveur, l'agent du laptop arrive par `ssh -A`.
# Les deux clés publiques sont à ajouter sur GitHub comme « Signing keys ».
{ config, ... }:
let
  inherit (config.sekkeizu) owner;
in
{
  flake.modules.homeManager.git =
    { pkgs, ... }:
    let
      # OpenSSH de nixpkgs : celui de macOS ne gère pas les clés FIDO2 (ed25519-sk).
      ssh = pkgs.openssh;

      # Clés dont la signature est reconnue (`git log --show-signature`).
      allowedSigners = pkgs.writeText "allowed_signers" (
        builtins.concatStringsSep "\n" (map (key: "${owner.email} ${key}") owner.sshKeys) + "\n"
      );

      # Première clé matérielle (sk-) chargée dans l'agent, au format attendu par git.
      signingKeyCommand = pkgs.writeShellScript "git-ssh-signing-key" ''
        key=$(${ssh}/bin/ssh-add -L 2>/dev/null | grep -m1 '^sk-')
        [ -n "$key" ] || { echo "aucune clé FIDO2 dans l'agent SSH" >&2; exit 1; }
        echo "key::$key"
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

      programs.lazygit.enable = true;
    };
}
