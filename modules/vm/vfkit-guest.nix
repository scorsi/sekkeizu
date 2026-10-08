# NixOS guest booted in EFI mode by vfkit (Virtualization.framework) on a Mac: a classic NixOS
# machine with its own disk and /nix/store, deployed with nixos-rebuild like any other. The Mac side
# (LaunchAgent, install and deploy apps) is modules/macos/vfkit-host.nix.
{
  flake.modules.nixos.vfkit-guest =
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      boot.loader.systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
      # systemd-boot is also installed at the removable-media path (EFI/BOOT/BOOTAA64.EFI): the VM
      # boots even without its EFI variable store, it only loses the boot order and one-shot entries.
      boot.loader.efi.canTouchEfiVariables = false;

      boot.initrd.systemd.enable = true;
      boot.initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_blk"
        "virtio_net"
        "virtio_console"
      ];
      # vfkit's virtio-serial console, logged to a file on the Mac.
      boot.kernelParams = [ "console=hvc0" ];

      # The image is built minimal, then enlarged on the Mac (sparse file) by install-<vm>.
      boot.growPartition = true;
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
        autoResize = true;
      };
      fileSystems."/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };
      # Discards reach the Mac's sparse disk image: freed blocks stop taking space there.
      services.fstrim.enable = true;

      # Virtualization.framework NAT: DHCP from macOS's bootpd (192.168.64.0/24), reachable from
      # the Mac only. Everything else goes through Tailscale.
      networking.useNetworkd = true;
      systemd.network.networks."10-uplink" = {
        matchConfig.Type = "ether";
        networkConfig.DHCP = "ipv4";
        # bootpd keys its lease on the client id: the MAC is fixed per VM, so is the address.
        dhcpV4Config.ClientIdentifier = "mac";
      };
      # <host>.local for the Mac itself: deploys stay on the NAT bridge, as tailscaled on macOS
      # binds to the default interface and would hairpin through the router.
      services.avahi = {
        enable = true;
        publish = {
          enable = true;
          addresses = true;
        };
        openFirewall = true;
      };

      # Raw EFI disk image (ESP + ext4 root), built on a Linux builder; see install-<vm>.
      system.build.vfkitImage = import "${modulesPath}/../lib/make-disk-image.nix" {
        inherit lib config pkgs;
        format = "raw";
        partitionTableType = "efi";
        diskSize = "auto";
        additionalSpace = "1024M";
        copyChannel = false;
      };
    };
}
