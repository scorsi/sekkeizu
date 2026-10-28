# `nix run .#deploy-<host> [nixos-rebuild build args | --rollback]` for the x86_64 hosts: evaluated
# on the Mac, built on the host itself (no x86_64 builder here; torii's 2 GB swap covers its build),
# reached over kekkai and activated in a detached unit (nixos-deploy.nu). DEPLOY_HOST is the
# fallback when kekkai itself is broken: root@torii-cdg.scorsi.dev (public SSH), root@<LAN IP> for
# a hashira.
{ config, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (lib.hasSuffix "darwin" system) {
      apps = lib.genAttrs' [ "torii-cdg" "hashira-01" "hashira-02" ] (
        name:
        lib.nameValuePair "deploy-${name}" {
          type = "app";
          program = toString (
            pkgs.writers.writeNu "deploy-${name}" ''
              ${builtins.readFile ./nixos-deploy.nu}
              def --wrapped main [...args] {
                $env.PATH = $env.PATH | prepend ${pkgs.nixos-rebuild}/bin
                let repo = ^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim
                # Same root@ for build and target: one ControlMaster connection (ssh-hosts.nix), one touch.
                let host = $env.DEPLOY_HOST? | default "root@${name}.kekkai.uchi.${config.sekkeizu.domain}"
                deploy $host $"($repo)#${name}" ...$args
              }
            ''
          );
        }
      );
    };
}
