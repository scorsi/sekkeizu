# Linux builder VM (QEMU + HVF, run as a LaunchDaemon by nix-darwin): lets the Mac build
# aarch64-linux derivations. Only needed to build a VM's disk image (`nix run .#install-<vm>`):
# afterwards the VM builds its own systems. Import it in the host only for that, then drop it again
# (nix-darwin then deletes the builder's disk).
{
  flake.modules.darwin.linux-builder = {
    nix.linux-builder = {
      enable = true;
      # Fresh disk at each start: its 20 GB filled up with past builds, and a VM image build needs
      # room for the closure plus the image itself. Nothing in there is worth keeping.
      ephemeral = true;
      # Left at the defaults (1 core, 3 GB, 20 GB sparse disk) on purpose: the stock builder comes
      # from cache.nixos.org, while any change to `config` needs a working builder to rebuild itself.
      # Tune it in a second step if builds turn out too slow.
    };
  };
}
