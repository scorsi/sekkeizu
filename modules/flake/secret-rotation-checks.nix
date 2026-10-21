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
              {
                name = "forgejo-runner";
                fragment = "forgejo-runner-secrets";
                secret = "forgejo-runner-jiban";
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
                forgejo-runners = {
                  inherit (cfg.systemd.services.forgejo-runners)
                    after
                    requires
                    wantedBy
                    partOf
                    ;
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    LoadCredential = "password:/run/secrets/forgejo-admin-password";
                  };
                  script = ''
                    ${pkgs.diffutils}/bin/cmp "$CREDENTIALS_DIRECTORY/password" /run/admin-password
                    cp /run/admin-password /run/runner-password
                  '';
                };
              };
            };
            testScript = ''
              machine.start()
              machine.wait_for_unit("hikyaku.service")
              machine.wait_for_unit("forgejo-runners.service")
              assert machine.succeed("cat /run/loaded-token") == "before-token"
              assert machine.succeed("cat /run/runner-password") == "before-password"
              switch = machine.succeed("readlink -f /run/current-system/specialisation/rotated").strip() + "/bin/switch-to-configuration test"
              machine.succeed(switch)
              machine.wait_for_unit("forgejo-runners.service")
              assert machine.succeed("cat /run/loaded-token") == "after-token"
              assert machine.succeed("cat /run/runner-password") == "after-password"
              assert machine.succeed("wc -l < /run/reader-starts").strip() == "2"
              machine.succeed(switch)
              assert machine.succeed("wc -l < /run/reader-starts").strip() == "2"
              machine.succeed("touch /run/fail-admin")
              machine.fail("systemctl restart forgejo-admin.service forgejo-runners.service")
              machine.fail("systemctl is-active --quiet forgejo-runners.service")
            '';
          };
      };
  };
}
