{ ... }:
{
  perSystem = { pkgs, ... }: {
    checks.hanko-backup =
      pkgs.runCommand "hanko-backup-test"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.diffutils
            pkgs.openssl
            pkgs.rsync
          ];
        }
        ''
          openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out account.key
          bash ${../backup/hanko-account.sh} account.key backups
          original=$(sha256sum account.key | cut -d ' ' -f 1)
          cmp account.key "backups/account-$original.key"
          test "$(stat -c %a backups)" = 750
          test "$(stat -c %a "backups/account-$original.key")" = 640
          bash ${../backup/hanko-account.sh} account.key backups
          test "$(find backups -type f | wc -l)" -eq 1
          openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out account.key
          bash ${../backup/hanko-account.sh} account.key backups
          test "$(find backups -type f | wc -l)" -eq 2
          mkdir pulled
          bash ${../backup/pull-rsync.sh} backups/ pulled/
          test "$(stat -c %a "pulled/account-$original.key")" = 600
          mkdir restored
          install -m 0600 "pulled/account-$original.key" restored/account.key
          test "$(stat -c %a restored/account.key)" = 600
          test "$(sha256sum restored/account.key | cut -d ' ' -f 1)" = "$original"
          openssl pkey -in restored/account.key -check -noout
          echo invalid > invalid.key
          if bash ${../backup/hanko-account.sh} invalid.key backups; then exit 1; fi
          if bash ${../backup/hanko-account.sh} missing.key backups; then exit 1; fi
          ln -s account.key symlink.key
          if bash ${../backup/hanko-account.sh} symlink.key backups; then exit 1; fi
          mkfifo fifo.key
          status=0
          timeout 2 bash ${../backup/hanko-account.sh} fifo.key backups || status=$?
          test "$status" -eq 1
          test "$(find backups -type f | wc -l)" -eq 2
          test -z "$(find backups -name '.account.*')"
          touch "$out"
        '';
  };
}
