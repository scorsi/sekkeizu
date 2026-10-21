# Flake apps, via `nix run .#<name>` (switch, check and fmt come from kiso):
#   set-autologin-password [host] → encrypt the login password as a kcpassword secret (see modules/macos/autologin.nix)
#   rekey-host <host> [--public-key file] → rotate the host's recipient, including shared secrets
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
      rekeyTools = [
        pkgs.git
        pkgs.sops
        pkgs.ssh-to-age
        pkgs.hostname
      ];
      rekeyHost = pkgs.writers.writeNu "rekey-host" ''
        $env.PATH = ${builtins.toJSON (map (p: "${p}/bin") rekeyTools)} | append $env.PATH
        ${builtins.readFile ./rekey-host.nu}
      '';
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
          program = toString rekeyHost;
        };
      };
      checks.rekey-host =
        pkgs.runCommand "rekey-host-test"
          {
            nativeBuildInputs = rekeyTools ++ [
              pkgs.age
              pkgs.openssh
              pkgs.nushell
            ];
          }
          ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            nu --no-config-file ${./rekey-host-test.nu} ${rekeyHost}
            touch "$out"
          '';
    };
}
