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
            pkgs.writers.writeNu "set-autologin-password" ''
              def main [host?: string] {
                let host = $host | default (^/bin/hostname -s | str trim)
                cd (^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim)
                mkdir $"secrets/($host)"
                ^${setAutologinPassword}/bin/set-autologin-password ${pkgs.sops}/bin/sops $"secrets/($host)/kcpassword"
              }
            ''
          );
        };

        rekey-host = {
          type = "app";
          program = toString (
            pkgs.writers.writeNu "rekey-host" ''
              def main [host: string] {
                cd (^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim)

                # Decrypts before re-encrypting: the FIDO2 identities, a touch per file.
                $env.SOPS_AGE_KEY_FILE = $env.SOPS_AGE_KEY_FILE? | default $"($env.HOME)/.config/sops/age/keys.txt"
                if not ($env.SOPS_AGE_KEY_FILE | path exists) {
                  error make { msg: $"age identities not found: ($env.SOPS_AGE_KEY_FILE)" }
                }

                let pub = if $host == (^/bin/hostname -s | str trim) {
                  open --raw /etc/ssh/ssh_host_ed25519_key.pub | split row " " | first 2 | str join " "
                } else {
                  # Recent ssh-keyscan also prints a "# host:22 SSH-2.0-…" comment line on stdout.
                  ^${pkgs.openssh}/bin/ssh-keyscan -t ed25519 $host | complete | get stdout | lines
                  | where { |l| $l != "" and not ($l | str starts-with "#") }
                  | each { split row " " | skip 1 | first 2 | str join " " }
                  | get 0?
                }
                if ($pub | is-empty) { error make { msg: $"no ed25519 host key found for ($host)" } }

                let age = $pub | ^${pkgs.ssh-to-age}/bin/ssh-to-age | str trim
                print $"recipient of ($host): ($age)"

                let anchor = "(?m)^  - &" + $host + " age1[0-9a-z]+"
                let sops = open --raw .sops.yaml
                if not ($sops =~ $anchor) {
                  error make { msg: $"no &($host) anchor in .sops.yaml: add the host by hand first" }
                }
                $sops | str replace --regex $anchor $"  - &($host) ($age)" | save --force .sops.yaml

                let files = glob $"secrets/($host)/*"
                if ($files | is-empty) {
                  print --stderr $"no secrets in secrets/($host)/"
                  return
                }
                for f in $files { ^${pkgs.sops}/bin/sops updatekeys --yes $f }
              }
            ''
          );
        };
      };
    };
}
