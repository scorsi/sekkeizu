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
              pkgs.sqlite
            ];
          }
          ''
            cp ${../nixos/forgejo-keys.nu} forgejo-keys.nu
            cp ${../nixos/forgejo-keys-test.nu} forgejo-keys-test.nu
            nu --no-config-file forgejo-keys-test.nu
            cp ${../nixos/forgejo-token.nu} forgejo-token.nu
            cp ${../nixos/forgejo-token-test.nu} forgejo-token-test.nu
            nu --no-config-file forgejo-token-test.nu
            touch "$out"
          '';
    };
}
