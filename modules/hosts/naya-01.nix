# naya-01 (納屋, the barn) — Minisforum NAB6 Lite on the home LAN: the storage node until the NAS (kura)
# arrives, then downloads, with its 1 TB NVMe as their scratch space.
# A host = its identity + the list of features it imports. Nothing else.
# Deployed from jiban with `nix run .#deploy-naya-01` (built on the node), reached over kekkai.
# Not installed yet: its SSH host key, generated ahead (recipient in .sops.yaml), waits in
# secrets/recovery/naya-01.yaml (`ssh-host-ed25519-key`) for the install's --extra-files (luks-nvme.nix).
{ config, inputs, ... }:
let
  inherit (config.flake.modules) nixos;
  inherit (config.kiso) stateVersions;
  hostName = "naya-01";
in
{
  flake.nixosConfigurations.${hostName} = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      # ─── System features ──────────────────────────────────────────────
      nixos.nab6
      nixos.luks-nvme
      nixos.impermanence
      nixos.nix
      nixos.owner
      nixos.fish
      nixos.secrets
      nixos.kekkai
      nixos.annai-resolver
      nixos.server
      nixos.hikyaku
      nixos.node-exporter

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

        disko.devices.disk.main.device = "/dev/disk/by-id/nvme-KINGSTON_OM8PGP41024Q-A0_50026B7382FA8D78";
      }
    ];
  };
}
