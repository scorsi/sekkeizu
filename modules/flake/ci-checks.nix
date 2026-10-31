{ config, ... }:
let
  runner = config.flake.nixosConfigurations.ishizue.config;
  torii = config.flake.nixosConfigurations.torii-cdg.config;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.ci-resources =
        assert runner.systemd.services.kajiba-runner.serviceConfig.Slice == "ci.slice";
        assert runner.systemd.services.nix-daemon.serviceConfig.Slice == "ci.slice";
        assert (runner.systemd.services.forgejo.serviceConfig.Slice or "system.slice") != "ci.slice";
        assert !(torii.systemd.slices ? ci);
        assert (torii.systemd.services.nix-daemon.serviceConfig.Slice or "system.slice") != "ci.slice";
        pkgs.runCommand "ci-resources-test" { } ''
          touch "$out"
        '';
    };
}
