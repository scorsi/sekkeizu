# Flake apps, via `nix run .#<name>` (switch, check and fmt come from kiso):
#   set-autologin-password [host] → encrypt the login password as a kcpassword secret (see modules/macos/autologin.nix)
#   rekey-host <host> → after a reinstall (new SSH host key): update the host's age recipient in .sops.yaml and re-encrypt secrets/<host>/
{ lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      # Compiled, so no interpreter is needed at runtime.
      setAutologinPassword = pkgs.stdenv.mkDerivation {
        name = "set-autologin-password";
        src = ./set-autologin-password.nim;
        dontUnpack = true;
        nativeBuildInputs = [ pkgs.nim ];
        # The store file name isn't a valid Nim module name.
        buildPhase = "cp $src main.nim && nim c -d:release --nimcache:$TMPDIR/nimcache -o:set-autologin-password main.nim";
        installPhase = "install -D set-autologin-password $out/bin/set-autologin-password";
      };
    in
    lib.optionalAttrs (lib.hasSuffix "darwin" system) {
      apps = {
        set-autologin-password = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "set-autologin-password" ''
              set -euo pipefail
              repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              host=''${1:-$(/bin/hostname -s)}
              cd "$repo"
              mkdir -p "secrets/$host"
              exec ${setAutologinPassword}/bin/set-autologin-password \
                ${pkgs.sops}/bin/sops "secrets/$host/kcpassword"
            ''
          );
        };

        rekey-host = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "rekey-host" ''
              set -euo pipefail
              host=''${1:?usage: rekey-host <host>}
              repo=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
              cd "$repo"

              # Needs the admin key to decrypt before re-encrypting.
              export SOPS_AGE_KEY_FILE=''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}
              [ -r "$SOPS_AGE_KEY_FILE" ] || { echo "clé admin introuvable : $SOPS_AGE_KEY_FILE" >&2; exit 1; }

              if [ "$host" = "$(/bin/hostname -s)" ]; then
                pub=$(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)
              else
                # Recent ssh-keyscan also prints a "# host:22 SSH-2.0-…" comment line on stdout.
                pub=$(${pkgs.openssh}/bin/ssh-keyscan -t ed25519 "$host" 2>/dev/null | grep -v '^#' | cut -d' ' -f2,3)
              fi
              [ -n "$pub" ] || { echo "clé hôte ed25519 introuvable pour $host" >&2; exit 1; }

              age=$(echo "$pub" | ${pkgs.ssh-to-age}/bin/ssh-to-age)
              echo "recipient de $host : $age"

              grep -Eq "^  - &$host age1" .sops.yaml ||
                { echo "pas d'ancre &$host dans .sops.yaml : ajoute l'hôte à la main d'abord" >&2; exit 1; }
              ${pkgs.gnused}/bin/sed -i.bak -E "s|^(  - &$host )age1[0-9a-z]+|\1$age|" .sops.yaml
              rm -f .sops.yaml.bak

              shopt -s nullglob
              files=(secrets/"$host"/*)
              [ ''${#files[@]} -gt 0 ] || { echo "aucun secret dans secrets/$host/" >&2; exit 0; }
              for f in "''${files[@]}"; do
                ${pkgs.sops}/bin/sops updatekeys --yes "$f"
              done
            ''
          );
        };
      };
    };
}
