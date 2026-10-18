# torii-cdg (鳥居, the gate) — Vultr instance in Paris (infra/stacks/torii), the lab's public gate.
# A host = its identity + the list of features it imports. Nothing else.
# Kept minimal (1 vCPU, 1 GB): no home-manager, services land as they are migrated (docs/migration.md).
{ config, inputs, ... }:
let
  inherit (config.flake.modules) nixos;
  inherit (config.kiso) stateVersions;
  hostName = "torii-cdg";
in
{
  flake.nixosConfigurations.${hostName} = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      # ─── System features ──────────────────────────────────────────────
      nixos.vultr-guest
      nixos.impermanence
      nixos.nix
      nixos.owner
      nixos.fish
      nixos.secrets
      nixos.annai-soto
      nixos.server

      # ─── Machine identity ─────────────────────────────────────────────
      {
        nixpkgs.hostPlatform = "x86_64-linux";
        networking = { inherit hostName; };
        time.timeZone = "Europe/Paris";
        system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
        system.stateVersion = stateVersions.nixos;

        # Not on the tailnet: root deploys come from the internet, FIDO2 keys only (docs/migration.md).
        services.openssh.settings.AllowUsers = [ "root" ];
      }
    ];
  };
}
