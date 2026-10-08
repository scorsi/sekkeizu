# Ephemeral root: / is a tmpfs rebuilt empty at every boot, only what is declared survives, on the
# ext4 disk mounted at /persist (which also carries /nix).
#
# Each feature declares its own state in `sekkeizu.persist.{directories,files}` (e.g. tailscale.nix
# keeps /var/lib/tailscale); this file only aggregates them and lists what is true of any machine.
#
# preservation rather than impermanence: bind mounts and symlinks are systemd mount/tmpfiles units,
# no activation script, and it is built for the systemd initrd this repo already uses. Root on tmpfs
# rather than a btrfs rollback: the VM's disk is ext4, nothing to snapshot, and the volatile part is
# small (/nix and /home are on disk).
{ config, inputs, ... }:
let
  inherit (config.sekkeizu) owner;
  persistRoot = "/persist";
in
{
  flake.modules.nixos.impermanence =
    { config, lib, ... }:
    let
      cfg = config.sekkeizu.persist;
      entry = lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything);
      hostKey = "${persistRoot}/etc/ssh/ssh_host_ed25519_key";
    in
    {
      imports = [ inputs.preservation.nixosModules.default ];

      options.sekkeizu.persist = {
        directories = lib.mkOption {
          type = lib.types.listOf entry;
          default = [ ];
          description = "Directories to keep across reboots: a path, or a preservation directory submodule.";
        };
        files = lib.mkOption {
          type = lib.types.listOf entry;
          default = [ ];
          description = "Files to keep across reboots: a path, or a preservation file submodule.";
        };
      };

      config = {
        # /persist is the disk labelled "nixos" (see vfkit-guest.nix, which mounts it on / by default).
        fileSystems = {
          "/" = {
            device = "none";
            fsType = "tmpfs";
            # The store and the home are on disk: this only holds /etc, /run-ish leftovers and /tmp.
            options = [
              "defaults"
              "size=1G"
              "mode=755"
            ];
          };
          ${persistRoot} = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
            autoResize = true;
            # Mounted in the initrd: sops decrypts and the machine-id is read before any bind mount.
            neededForBoot = true;
          };
          # The disk image's store sits at the root of the ext4 filesystem, i.e. at /persist/nix.
          "/nix" = {
            device = "${persistRoot}/nix";
            fsType = "none";
            options = [ "bind" ];
            depends = [ persistRoot ];
            neededForBoot = true;
          };
        };

        # Builds happen in /tmp by default, which is a 1 GB tmpfs here.
        nix.settings.build-dir = "/nix/var/nix/builds";

        # sops-nix decrypts during activation, before the bind mounts of the units below exist:
        # the host key is read straight from the persistent volume.
        services.openssh.hostKeys = lib.mkForce [
          {
            type = "ed25519";
            path = hostKey;
          }
        ];
        sops.age.sshKeyPaths = lib.mkForce [ hostKey ];
        # sshd generates the key on first boot but does not create its directory.
        systemd.tmpfiles.settings.preservation."${persistRoot}/etc/ssh".d.mode = "0755";

        sekkeizu.persist = {
          directories = [
            # uid/gid map: activation reads it, so it has to be there in the initrd.
            {
              directory = "/var/lib/nixos";
              inInitrd = true;
            }
            "/var/lib/systemd"
            "/var/log"
            {
              directory = "/home/${owner.name}";
              user = owner.name;
              group = config.users.users.${owner.name}.group;
              mode = "0700";
            }
          ];
          files = [
            {
              file = "/etc/machine-id";
              inInitrd = true;
            }
          ];
        };

        preservation = {
          enable = true;
          preserveAt.${persistRoot} = {
            inherit (cfg) directories files;
          };
        };

        # Committing the id to a bind-mounted file can't work, and the id already persists.
        systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];
      };
    };
}
