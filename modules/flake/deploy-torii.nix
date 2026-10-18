# `nix run .#deploy-torii-cdg [nixos-rebuild args]`: evaluated on the Mac, built on torii itself
# (no x86_64 builder here; its 2 GB swap covers the build), switched over its public name.
{ lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (lib.hasSuffix "darwin" system) {
      apps.deploy-torii-cdg = {
        type = "app";
        program = toString (
          pkgs.writers.writeNu "deploy-torii-cdg" ''
            def --wrapped main [...args] {
              let repo = ^${pkgs.git}/bin/git rev-parse --show-toplevel | str trim
              # Same root@ for build and target: one ControlMaster connection (ssh-hosts.nix), one touch.
              let host = "root@torii-cdg.scorsi.dev"
              exec ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake $"($repo)#torii-cdg" --build-host $host --target-host $host ...$args
            }
          ''
        );
      };
    };
}
