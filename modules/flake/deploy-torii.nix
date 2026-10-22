# `nix run .#deploy-torii-cdg [nixos-rebuild build args | --rollback]`: evaluated on the Mac, built
# on torii itself (no x86_64 builder here; its 2 GB swap covers the build), reached over kekkai and
# activated in a detached unit (nixos-deploy.nu). DEPLOY_HOST=root@torii-cdg.scorsi.dev (public SSH)
# is the fallback when kekkai itself is broken.
{ config, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (lib.hasSuffix "darwin" system) {
      apps.deploy-torii-cdg = {
        type = "app";
        program = toString (
          pkgs.writers.writeNu "deploy-torii-cdg" ''
            ${builtins.readFile ./nixos-deploy.nu}
            def --wrapped main [...args] {
              $env.PATH = $env.PATH | prepend ${pkgs.nixos-rebuild}/bin
              let repo = ^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim
              # Same root@ for build and target: one ControlMaster connection (ssh-hosts.nix), one touch.
              let host = $env.DEPLOY_HOST? | default "root@torii-cdg.kekkai.uchi.${config.sekkeizu.domain}"
              deploy $host $"($repo)#torii-cdg" ...$args
            }
          ''
        );
      };
    };
}
