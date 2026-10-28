# NixOS on a Lenovo ThinkCentre M75q (Ryzen 5 5600GE, NVMe, UEFI), wired to the home LAN. Pairs
# with the impermanence feature, which mounts the disk by label. The host sets
# `disko.devices.disk.main.device` to its NVMe by id: hashira-02 carries the DAS's disks too, and
# their /dev/sd* names are not stable.
# Install over an existing NixOS reachable by SSH (kexec: 15 GB of RAM is plenty):
#   1. A throwaway key in root's authorized_keys (`sudo` from the installer's user).
#   2. A host key generated beforehand, its age recipient already in .sops.yaml, under
#      <dir>/etc/ssh/ssh_host_ed25519_key: the disk's root is /persist once booted.
#   3. `SSH_AUTH_SOCK= nixos-anywhere -i <key> --build-on remote --extra-files <dir>
#      --flake .#<host> root@<ip>`, then delete the throwaway key and the local host key.
#      Over a previous install, disko can find a leftover FAT signature on the new ESP, skip mkfs,
#      and fail to mount /mnt/boot ("can't read superblock"). Then, still in the installer:
#      `mkfs.vfat -F 32 -n ESP /dev/disk/by-partlabel/disk-main-ESP`, mount it on /mnt/boot
#      (umask=0077), and rerun with `--phases install,reboot`.
{ inputs, ... }:
{
  flake.modules.nixos.m75q =
    { modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
        inputs.disko.nixosModules.disko
      ];

      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];
      boot.kernelModules = [ "kvm-amd" ];
      hardware.cpu.amd.updateMicrocode = true;
      hardware.enableRedistributableFirmware = true;

      # disko only formats at install time; the mounts are impermanence's (by label) plus /boot below.
      disko.enableConfig = false;
      disko.devices.disk.main = {
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                extraArgs = [
                  "-n"
                  "ESP"
                ];
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            # Mounted on / during the install, so the store lands at its root: /persist/nix once booted.
            nixos = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                extraArgs = [
                  "-L"
                  "nixos"
                ];
                mountpoint = "/";
              };
            };
          };
        };
      };

      fileSystems."/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };
      # No swap partition: 15 GB of RAM, and zram covers a build's peak.
      zramSwap.enable = true;

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.initrd.systemd.enable = true;

      # The box's DHCP, no reservation: kekkai finds the node through the lighthouse.
      networking.useNetworkd = true;
      systemd.network.networks."10-uplink" = {
        matchConfig.Type = "ether";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
      };
    };
}
