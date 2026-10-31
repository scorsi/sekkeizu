{
  config,
  inputs,
  lib,
  ...
}:
{
  perSystem = { pkgs, ... }: {
    checks =
      lib.optionalAttrs pkgs.stdenv.isDarwin {
        secret-restarts =
          let
            cfg = config.flake.darwinConfigurations.jiban.config;
            scripts = cfg.system.activationScripts;
            afterSops = lib.last (lib.splitString "/bin/sops-install-secrets " scripts.postActivation.text);
            cases = [
              {
                name = "hikyaku";
                fragment = "hikyaku-secrets";
                secret = "hikyaku-token";
              }
              {
                name = "kekkai-node";
                fragment = "kekkai-secrets";
                secret = "kekkai-key";
              }
            ];
            fakeLaunchctl = pkgs.writeShellScript "launchctl-test" ''
              set -eu
              test "$#" -eq 3
              test "$1" = kickstart
              test "$2" = -k
              test "$3" = "$expectedService"
              echo restart >> "$restartLog"
              test "''${FAIL_RESTART:-0}" = 0
            '';
            check =
              {
                name,
                fragment,
                secret,
              }:
              let
                body = scripts.${fragment}.text;
                script = pkgs.writeText "${name}-restart-test.sh" (
                  "set -eu\n"
                  + lib.replaceStrings [ "/bin/launchctl" "/var/db/" ] [ "\"$fakeLaunchctl\"" "\"$state\"/" ] body
                );
                fingerprint = cfg.sops.secrets.${secret}.sopsFileHash;
              in
              assert lib.hasInfix body afterSops;
              assert fingerprint != "";
              ''
                export state="$TMPDIR/${name}" restartLog="$TMPDIR/${name}.log"
                export expectedService=system/${cfg.launchd.daemons.${name}.serviceConfig.Label}
                mkdir -p "$state"
                bash ${script}
                test "$(cat "$state/${name}.secrets")" = '${fingerprint}'
                bash ${script}
                test "$(wc -l < "$restartLog")" -eq 1

                echo previous-fingerprint > "$state/${name}.secrets"
                if FAIL_RESTART=1 bash ${script}; then exit 1; fi
                test "$(cat "$state/${name}.secrets")" = previous-fingerprint
                bash ${script}
                test "$(cat "$state/${name}.secrets")" = '${fingerprint}'
                bash ${script}
                test "$(wc -l < "$restartLog")" -eq 3
              '';
          in
          pkgs.runCommand "darwin-secret-restarts-test" { nativeBuildInputs = [ pkgs.bash ]; } ''
            export fakeLaunchctl=${fakeLaunchctl}
            ${lib.concatMapStringsSep "\n" check cases}
            touch "$out"
          '';
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        secret-restarts =
          let
            cfg = config.flake.nixosConfigurations.ishizue.config;
            fixtures =
              pkgs.runCommand "rotation-fixtures"
                {
                  nativeBuildInputs = [
                    pkgs.age
                    pkgs.sops
                  ];
                }
                ''
                  mkdir -p "$out"
                  age-keygen -o "$out/key"
                  recipient=$(age-keygen -y "$out/key")
                  for version in before after; do
                    printf 'hikyaku-token: %s-token\nforgejo-admin-password: %s-password\n' "$version" "$version" |
                      sops encrypt --age "$recipient" --input-type yaml --output-type yaml /dev/stdin > "$out/$version.yaml"
                  done
                '';
          in
          pkgs.testers.runNixOSTest {
            name = "secret-restarts";
            nodes.machine = { lib, pkgs, ... }: {
              imports = [ inputs.sops-nix.nixosModules.sops ];
              # Disposable test identity, never a host key.
              environment.etc.rotation-key.source = "${fixtures}/key";
              system.activationScripts.setupSecrets.deps = [ "etc" ];
              sops = {
                validateSopsFiles = false;
                age.keyFile = "/etc/rotation-key";
                defaultSopsFile = "${fixtures}/before.yaml";
                secrets = lib.genAttrs [ "hikyaku-token" "forgejo-admin-password" ] (name: {
                  inherit (cfg.sops.secrets.${name}) restartUnits;
                });
              };
              specialisation.rotated.configuration.sops.defaultSopsFile = lib.mkForce "${fixtures}/after.yaml";
              systemd.services = {
                hikyaku = {
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    LoadCredential = "token:/run/secrets/hikyaku-token";
                  };
                  script = ''
                    cp "$CREDENTIALS_DIRECTORY/token" /run/loaded-token
                    echo start >> /run/reader-starts
                  '';
                };
                forgejo = {
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "${pkgs.coreutils}/bin/true";
                  };
                };
                forgejo-admin = {
                  inherit (cfg.systemd.services.forgejo-admin) after wantedBy partOf;
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    LoadCredential = "password:/run/secrets/forgejo-admin-password";
                  };
                  script = ''
                    test ! -e /run/fail-admin
                    sleep 1
                    cp "$CREDENTIALS_DIRECTORY/password" /run/admin-password
                  '';
                };
              };
            };
            # The NixOS test driver only runs Python: it boots the VM and hands over to Nushell.
            testScript =
              let
                check = pkgs.writeText "secret-restarts.nu" ''
                  def wait-active [unit: string] {
                    for _ in 1..60 {
                      if (do { ^systemctl is-active --quiet $unit } | complete).exit_code == 0 { return }
                      sleep 1sec
                    }
                    error make {msg: $"($unit) is not active"}
                  }
                  def expect [file: string, want: string] {
                    let got = open --raw $file | str trim
                    if $got != $want { error make {msg: $"($file): ($got), expected ($want)"} }
                  }
                  def starts [] { open --raw /run/reader-starts | lines | length }

                  expect /run/loaded-token before-token
                  expect /run/admin-password before-password
                  let switch = $"(^readlink -f /run/current-system/specialisation/rotated | str trim)/bin/switch-to-configuration"
                  ^$switch test
                  wait-active forgejo-admin.service
                  expect /run/loaded-token after-token
                  expect /run/admin-password after-password
                  if (starts) != 2 { error make {msg: "hikyaku did not restart exactly once"} }
                  ^$switch test
                  if (starts) != 2 { error make {msg: "an unchanged secret restarted hikyaku"} }
                  touch /run/fail-admin
                  if (do { ^systemctl restart forgejo-admin.service } | complete).exit_code == 0 {
                    error make {msg: "a failing forgejo-admin did not fail the restart"}
                  }
                '';
              in
              ''
                machine.start()
                machine.wait_for_unit("hikyaku.service")
                machine.wait_for_unit("forgejo-admin.service")
                machine.succeed("${pkgs.nushell}/bin/nu --no-config-file ${check}")
              '';
          };
      };
  };
}
