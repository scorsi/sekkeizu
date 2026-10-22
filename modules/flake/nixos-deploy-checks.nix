# Client side of the detached NixOS deploy (nixos-deploy.nu), against fake ssh and nixos-rebuild.
{
  perSystem =
    { pkgs, ... }:
    {
      checks.nixos-deploy =
        pkgs.runCommand "nixos-deploy-test"
          {
            nativeBuildInputs = [
              pkgs.nushell
              pkgs.coreutils
              pkgs.gnused
            ];
          }
          ''
            cp ${./nixos-deploy.nu} nixos-deploy.nu
            cp ${./nixos-deploy-test.nu} nixos-deploy-test.nu
            nu --no-config-file nixos-deploy-test.nu
            touch "$out"
          '';
    };
}
