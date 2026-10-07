# git: identity from sekkeizu.owner, SSH-signed commits, delta diffs.
#
# Signing: git signs with the FIDO2 key of the device actually plugged in (YubiKey or
# Thetis), detected via fido2-token (aaguid) rather than SSH agent order.
# On the server, the laptop's agent arrives via `ssh -A`.
# Both public keys must be added on GitHub as "Signing keys".
{ config, ... }:
let
  inherit (config.sekkeizu) owner;
in
{
  flake.modules.homeManager.git =
    { pkgs, lib, ... }:
    let
      # nixpkgs' OpenSSH: macOS's own doesn't support FIDO2 keys (ed25519-sk).
      ssh = pkgs.openssh;
      # fido2-token: identifies the model (aaguid) of plugged-in FIDO2 devices.
      fido2 = pkgs.libfido2;

      # Keys whose signature is recognized (`git log --show-signature`).
      allowedSigners = pkgs.writeText "allowed_signers" (
        builtins.concatStringsSep "\n" (map (k: "${owner.email} ${k.key}") owner.sshKeys) + "\n"
      );

      # Key of the FIDO2 device actually plugged in (matched by aaguid), in the format git expects.
      # The device id (DevSrvsID:<n> on macOS) changes on every plug-in: always re-list it,
      # never cache it.
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

      # delta: colored diffs with line numbers (theme via catppuccin).
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
