{
  perSystem =
    { pkgs, ... }:
    {
      checks.forgejo-dump =
        pkgs.runCommand "forgejo-dump-test"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.python3
              pkgs.rsync
            ];
          }
          ''
            python3 -B ${../backup/forgejo-dump-test.py} ${../backup/forgejo-dump-publish.sh} ${../backup/pull-rsync.sh}
            touch "$out"
          '';
    };
}
