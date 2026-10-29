# hashira-02 (柱, the pillar) — Lenovo ThinkCentre M75q on the home LAN, a compute node.
# A host = its identity + the list of features it imports. Nothing else.
# Deployed from jiban with `nix run .#deploy-hashira-02` (built on the node), reached over kekkai.
{ config, inputs, ... }:
let
  inherit (config.flake.modules) nixos;
  inherit (config.kiso) stateVersions;
  hostName = "hashira-02";
in
{
  flake.nixosConfigurations.${hostName} = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      # ─── System features ──────────────────────────────────────────────
      nixos.m75q
      nixos.impermanence
      nixos.nix
      nixos.owner
      nixos.fish
      nixos.secrets
      nixos.kekkai
      nixos.server
      nixos.observability-agent
      nixos.hanko
      nixos.genkan
      nixos.forgejo-runner
      nixos.rirekisho

      # ─── Machine identity ─────────────────────────────────────────────
      {
        nixpkgs.hostPlatform = "x86_64-linux";
        networking = { inherit hostName; };
        time.timeZone = "Europe/Paris";
        system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
        system.stateVersion = stateVersions.nixos;

        sops.defaultSopsFile = ../../secrets/${hostName}/secrets.yaml;

        # Deploy fallback when kekkai is down: root from the home LAN too (FIDO2 keys only).
        services.openssh.settings.AllowUsers = [ "root@192.168.1.0/24" ];

        disko.devices.disk.main.device = "/dev/disk/by-id/nvme-WD_PC_SN740_SDDQNQD-256G-1201_23340U801827";
      }
    ];
  };
}
