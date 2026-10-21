{
  perSystem =
    { pkgs, ... }:
    {
      checks.forgejo-keys =
        pkgs.runCommand "forgejo-keys-test"
          {
            nativeBuildInputs = [
              pkgs.nushell
              pkgs.coreutils
            ];
          }
          ''
            cp ${../nixos/forgejo-keys.nu} forgejo-keys.nu
            cp ${../nixos/forgejo-keys-test.nu} forgejo-keys-test.nu
            nu --no-config-file forgejo-keys-test.nu
            touch "$out"
          '';
    };
}
