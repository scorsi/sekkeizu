# The physical nodes' system disk (hashira's M75q, naya's NAB6): one NVMe, UEFI, LUKS2 around the
# ext4 that becomes /persist, unlocked by the TPM2. Pairs with the impermanence feature, which mounts
# the disk by label, and a hardware feature (m75q, nab6). The host sets
# `disko.devices.disk.main.device` to its NVMe by id: a host carrying the DAS has /dev/sd* disks too,
# and their names are not stable.
# Install from the USB key, not by kexec: on hashira-02 a kexec from the running sekkeizu system froze
# the machine twice (no network, power cycle needed).
#   1. Build a minimal NixOS installer (sekkeizu's nixpkgs) with SSH and a throwaway key for root,
#      write it to the node's USB key, check its SHA-256, and boot it once: `efibootmgr -n <USB entry>`.
#   2. Keep the host key: copy /persist/etc/ssh/ssh_host_ed25519_key to <dir>/etc/ssh/ (the disk's
#      root is /persist once booted), or generate one and add its age recipient to .sops.yaml first.
#   3. The recovery passphrase in a local file, from `sops -d secrets/recovery/<host>.yaml`.
#   4. `SSH_AUTH_SOCK= nixos-anywhere -i <key> --phases disko,install --build-on remote
#      --disk-encryption-keys /tmp/recovery.key <local file> --extra-files <dir>
#      --flake .#<host> root@<ip>`.
#   5. Still in the installer: `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=
#      --unlock-key-file=/tmp/recovery.key /dev/disk/by-partlabel/disk-main-nixos`, then reboot.
#      Delete the throwaway key and the local copies.
#   Over a previous install, disko can find a leftover FAT signature on the new ESP, skip mkfs,
#   and fail to mount /mnt/boot ("can't read superblock"). Then, still in the installer:
#   `mkfs.vfat -F 32 -n ESP /dev/disk/by-partlabel/disk-main-ESP`, mount it on /mnt/boot
#   (umask=0077), and rerun with `--phases install`.
{ inputs, ... }:
{
  flake.modules.nixos.luks-nvme = {
    imports = [ inputs.disko.nixosModules.disko ];

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
    # No swap partition: enough RAM, and zram covers a build's peak.
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
