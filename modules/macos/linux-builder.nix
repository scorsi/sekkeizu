# Linux builder VM (QEMU + HVF, run as a LaunchDaemon by nix-darwin): lets the Mac build
# aarch64-linux derivations. Only needed to build a VM's disk image (`nix run .#install-<vm>`):
# afterwards the VM builds its own systems. Import it in the host only for that, then drop it again
# (nix-darwin then deletes the builder's disk).
{
  flake.modules.darwin.linux-builder =
    { lib, ... }:
    {
      nix.linux-builder = {
        enable = true;
        # Fresh disk at each start: its 20 GB filled up with past builds, and a VM image build needs
        # room for the closure plus the image itself. Nothing in there is worth keeping.
        ephemeral = true;
        # 40 GB (sparse) for the next image builds. Any other change to `config` would need a working
        # builder to rebuild the builder itself; the disk size only changes the Mac-side launcher
        # (checked: the guest system's derivation is the same as the stock one, from cache.nixos.org).
        # 1 core and 3 GB stay at the defaults until builds turn out too slow.
        config.virtualisation.diskSize = lib.mkForce (40 * 1024);
      };
    };
}
