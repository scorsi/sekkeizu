{ config, ... }:
let
  runner = config.flake.nixosConfigurations.ishizue.config;
  torii = config.flake.nixosConfigurations.torii-cdg.config;
  budget = runner.systemd.slices.ci.sliceConfig;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.ci-resources =
        assert runner.systemd.services.forgejo-runner.serviceConfig.Slice == "ci.slice";
        assert runner.systemd.services.nix-daemon.serviceConfig.Slice == "ci.slice";
        assert (runner.systemd.services.forgejo.serviceConfig.Slice or "system.slice") != "ci.slice";
        assert budget.MemoryHigh == "3G";
        assert budget.MemoryMax == "4G";
        assert budget.MemorySwapMax == 0;
        assert budget.CPUQuota == "200%";
        assert runner.nix.settings.max-jobs == 1;
        assert runner.nix.settings.cores == 2;
        assert !(torii.systemd.slices ? ci);
        assert (torii.systemd.services.nix-daemon.serviceConfig.Slice or "system.slice") != "ci.slice";
        pkgs.runCommand "ci-resources-test" { } ''
          touch "$out"
        '';
    };
}
