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
    };
}
