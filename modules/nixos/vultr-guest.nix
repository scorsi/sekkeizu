# NixOS on a Vultr instance (infra/modules/vultr-node). Pairs with the impermanence feature, which
# mounts the disk by label. Install, without kexec (its initrd alone does not fit in 1 GB):
#   1. `tofu apply -var iso_url=<NixOS minimal ISO>` in the stack: the instance boots the installer.
#   2. Vultr console: `passwd` for the `nixos` user, typed by hand (the console mangles pastes), with
#      `install_password` from secrets/infra/tofu.yaml.
#   3. With that password, once: put a throwaway key in the `nixos` user's and root's authorized_keys.
#      Without the kexec phase nixos-anywhere connects as root whatever user is given, and its
#      ssh-copy-id retries trip sshd's PerSourcePenalties.
#   4. `SSH_AUTH_SOCK= nixos-anywhere -i <key> --phases disko,install --build-on remote
#      --no-disko-deps --flake .#<host> root@<ip>`: the system is built into /mnt (disk), but the
#      disko script into the ISO's RAM store, hence no deps. That script leaves the swap off: run
#      `swapon /dev/disk/by-label/swap` on the target as soon as "Building the system closure" shows.
#   5. Vultr console, Settings → Custom ISO → Remove ISO: the instance reboots on its disk. tofu
#      cannot do it: one apply detaches and deletes the ISO at once, and Vultr refuses the delete.
#      Then a plain `tofu apply` deletes the ISO.
{ inputs, ... }:
{
  flake.modules.nixos.vultr-guest =
    { modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        inputs.disko.nixosModules.disko
      ];

      # disko only formats at install time; the mounts are impermanence's (by label) plus /boot below.
      disko.enableConfig = false;
      disko.devices.disk.main = {
        device = "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # GRUB's core image on a GPT disk booted by SeaBIOS.
            bios = {
              size = "1M";
              type = "EF02";
            };
            ESP = {
              size = "512M";
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
            # 1 GB of RAM does not survive an install or a switch alone.
            swap = {
              size = "2G";
              content = {
                type = "swap";
                extraArgs = [
                  "-L"
                  "swap"
                ];
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
      swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

      # Vultr boots with SeaBIOS; the removable EFI copy only matters if that ever changes.
      boot.loader.grub = {
        enable = true;
        device = "/dev/vda";
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
      boot.initrd.systemd.enable = true;

      # The reserved IPv4 comes over DHCP, IPv6 from router advertisements.
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
