{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.backup-pull =
        pkgs.runCommand "backup-pull-test"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.python3
              pkgs.rsync
            ];
          }
          ''
            python3 ${../backup/pull-rsync-test.py} ${../backup/pull-rsync.sh}
            touch "$out"
          '';
      checks.observability-backups =
        pkgs.runCommand "observability-backups-test" { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            python3 -B ${../backup/observability-archives-test.py} ${../backup/observability-archives.py} ${../backup/observability-retention-days.json}
            touch "$out"
          '';
    };
}
