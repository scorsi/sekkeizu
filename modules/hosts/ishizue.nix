# ishizue (礎, the foundation stone) — NixOS VM on jiban (vfkit, Virtualization.framework).
# A host = its identity + the list of features it imports. Nothing else.
# Resources (vCPU, RAM, disk, MAC) are the Mac's business: `sekkeizu.vms.ishizue` in jiban.nix.
# Deployed from jiban with `nix run .#deploy-ishizue` (built inside the VM), reached over Tailscale.
{ config, inputs, ... }:
let
  inherit (config.flake.modules) nixos homeManager;
  inherit (config.sekkeizu) owner stateVersions;
  hostName = "ishizue";
in
{
  flake.nixosConfigurations.${hostName} = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      # ─── System features ──────────────────────────────────────────────
      nixos.vfkit-guest
      nixos.impermanence
      nixos.nix
      nixos.owner
      nixos.home-manager
      nixos.fish
      nixos.secrets
      nixos.tailscale
      nixos.server
      nixos.caddy
      nixos.forgejo
      nixos.forgejo-mirrors
      nixos.forgejo-runner
      nixos.site
      nixos.backup-source

      # ─── User features ────────────────────────────────────────────────
      {
        home-manager.users.${owner.name}.imports = [
          homeManager.fish
          homeManager.ssh
          homeManager.git
          homeManager.cli
          homeManager.pay-respects
          homeManager.tmux
          homeManager.theme
          homeManager.kanna
        ];
      }

      # ─── Machine identity ─────────────────────────────────────────────
      {
        nixpkgs.hostPlatform = "aarch64-linux";
        networking = { inherit hostName; };
        time.timeZone = "Europe/Paris";
        system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
        system.stateVersion = stateVersions.nixos;

        sops.defaultSopsFile = ../../secrets/${hostName}/secrets.yaml;
      }
    ];
  };
}
