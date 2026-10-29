# NixOS on a Lenovo ThinkCentre M75q (Ryzen 5 5600GE, NVMe, UEFI), wired to the home LAN. Pairs
# with the impermanence feature, which mounts the disk by label. The host sets
# `disko.devices.disk.main.device` to its NVMe by id: hashira-02 carries the DAS's disks too, and
# their /dev/sd* names are not stable.
# Install over an existing NixOS reachable by SSH (kexec: 15 GB of RAM is plenty):
#   1. A throwaway key in root's authorized_keys; keep the host key: copy
#      /persist/etc/ssh/ssh_host_ed25519_key to <dir>/etc/ssh/ (the disk's root is /persist once
#      booted), or generate one and add its age recipient to .sops.yaml first.
#   2. The recovery passphrase in a local file, from `sops -d secrets/recovery/<host>.yaml`.
#   3. `SSH_AUTH_SOCK= nixos-anywhere -i <key> --phases kexec,disko,install --build-on remote
#      --disk-encryption-keys /tmp/recovery.key <local file> --extra-files <dir>
#      --flake .#<host> root@<ip>`.
#   4. Still in the installer: `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=
#      --unlock-key-file=/tmp/recovery.key /dev/disk/by-partlabel/disk-main-nixos`, then reboot.
#      Delete the throwaway key and the local copies.
#   Over a previous install, disko can find a leftover FAT signature on the new ESP, skip mkfs,
#   and fail to mount /mnt/boot ("can't read superblock"). Then, still in the installer:
#   `mkfs.vfat -F 32 -n ESP /dev/disk/by-partlabel/disk-main-ESP`, mount it on /mnt/boot
#   (umask=0077), and rerun with `--phases install`.
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
            # LUKS around the ext4 that becomes /persist. The recovery passphrase is the install's key
            # (secrets/recovery/<host>.yaml); the TPM2 keyslot is enrolled before the first boot.
            # Mounted on / during the install, so the store lands at its root: /persist/nix once booted.
            nixos = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                passwordFile = "/tmp/recovery.key";
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

      # Unattended unlock by the TPM2, bound to no PCR for now: without Secure Boot, any PCR worth
      # binding changes with every kernel. This only protects an NVMe taken out of the machine; PCR 7
      # comes with lanzaboote, Tang after that (both new keyslots, no reinstall).
      boot.initrd.luks.devices.cryptroot = {
        device = "/dev/disk/by-partlabel/disk-main-nixos";
        allowDiscards = true;
        crypttabExtraOpts = [ "tpm2-device=auto" ];
      };
      # impermanence's grower is for VM disk images; here the install fills the disk, and /persist
      # sits on the LUKS mapping, which has no partition number to grow.
      systemd.services.growpart-persist.enable = false;

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
