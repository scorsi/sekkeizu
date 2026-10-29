{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.backup-exports =
        pkgs.runCommand "backup-exports-test"
          {
            nativeBuildInputs = [
              pkgs.nushell
              pkgs.coreutils
              pkgs.openssl
            ];
          }
          ''
            cp ${../backup/observability-export.nu} observability-export.nu
            nu --no-config-file ${../backup/observability-export-test.nu}
            HANKO_ACCOUNT_SCRIPT=${../backup/hanko-account.nu} nu --no-config-file ${../backup/hanko-account-test.nu}
            touch "$out"
          '';
    };
}
