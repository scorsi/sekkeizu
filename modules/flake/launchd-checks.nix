{ config, lib, ... }:
let
  launchd = config.flake.darwinConfigurations.jiban.config.launchd;
  jobs = launchd.daemons // launchd.agents // launchd.user.agents;
  # launchd starts boot jobs before /nix is mounted: a job that execs from the store without
  # waiting exits 78 and is never retried (`command` in nix-darwin adds the wait).
  # shortcut: fixed upstream (kekkai bdbd9c6, hikyaku 3df9bc4) but not pinned yet; drop each
  # name when its input is bumped.
  pending = [
    "hikyaku"
    "kekkai-node"
  ];
  unguarded = lib.subtractLists pending (
    lib.attrNames (
      lib.filterAttrs (
        _: job:
        let
          args = job.serviceConfig.ProgramArguments or [ ];
        in
        lib.any (lib.hasInfix "/nix/store") args
        && !(
          lib.take 2 args == [
            "/bin/sh"
            "-c"
          ]
          && lib.hasPrefix "/bin/wait4path /nix/store && " (lib.elemAt args 2)
        )
      ) jobs
    )
  );
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.launchd-wait4path =
        assert lib.assertMsg (
          unguarded == [ ]
        ) "launchd jobs exec from /nix/store without wait4path: ${toString unguarded}";
        pkgs.runCommand "launchd-wait4path-test" { } ''
          touch "$out"
        '';
    };
}
