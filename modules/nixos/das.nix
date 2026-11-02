# The USB DAS (3 bays, salvaged disks): one LUKS + ext4 per disk, pooled by mergerfs at /srv/das.
# No parity (owner, 2026-10-28): losing a disk loses its files only; nothing irreplaceable lives here.
# Host-agnostic: the disks are named by id and the LUKS key is the storage's, not the host's
# (secrets/das/luks.yaml). Moving the DAS = import this feature on the new host and change the
# file's recipient in .sops.yaml (`sops updatekeys`); the disks are not touched.
#
# Formatting, once per disk (destroys its content), with the key on stdin, never on disk:
#   sops -d --extract '["das-luks-key"]' secrets/das/luks.yaml \
#     | ssh root@<host> cryptsetup luksFormat --batch-mode --key-file=- /dev/disk/by-id/<id>
#   then `cryptsetup open --key-file=- <id> das-<serial>` the same way, and
#   `mkfs.ext4 -m 0 -L das-<serial> /dev/mapper/das-<serial>`. The key has no trailing newline:
#   sops-nix writes exactly these bytes.
{
  flake.modules.nixos.das =
    {
      config,
      lib,
      pkgs,
      utils,
      ...
    }:
    let
      # Serial → model prefix of /dev/disk/by-id/ata-<model>_<serial>.
      disks = {
        W625JZKH = "ST500LM021-1KJ152";
        S3PNQ734 = "ST500LT012-1DG142";
        ZN1374ZM = "ST1000DM010-2EP102";
      };
      # Outside /srv/das: a branch under the pool's own mount point makes an ordering cycle.
      mountOf = serial: "/mnt/das/${serial}";
      cryptUnit = serial: "systemd-cryptsetup@${utils.escapeSystemdPath "das-${serial}"}";
      # Removes the mapper $1 if its disk vanished (the kernel keeps a dangling slave link); fails when
      # there is nothing to remove.
      dropStale = pkgs.writeShellScript "das-drop-stale" ''
        dm=$(${lib.getExe' pkgs.lvm2 "dmsetup"} info -c --noheadings -o blkdevname "$1" 2>/dev/null) || exit 1
        ! [ -e /sys/class/block/$dm/slaves/* ] || exit 1
        exec ${lib.getExe' pkgs.lvm2 "dmsetup"} remove "$1"
      '';
    in
    {
      sops.secrets.das-luks-key.sopsFile = ../../secrets/das/luks.yaml;

      # Unlocked in stage 2, after sops has decrypted the key; nofail so the host boots without the DAS.
      environment.etc.crypttab.text = lib.concatStrings (
        lib.mapAttrsToList (serial: model: ''
          das-${serial} /dev/disk/by-id/ata-${model}_${serial} ${config.sops.secrets.das-luks-key.path} luks,nofail
        '') disks
      );

      fileSystems =
        lib.mapAttrs' (
          serial: _:
          lib.nameValuePair (mountOf serial) {
            device = "/dev/mapper/das-${serial}";
            fsType = "ext4";
            options = [
              "nofail"
              "noatime"
            ];
          }
        ) disks
        // {
          "/srv/das" = {
            device = lib.concatMapStringsSep ":" mountOf (lib.attrNames disks);
            fsType = "fuse.mergerfs";
            # Every disk required: a missing one would leave its empty mount point, on the tmpfs root,
            # as a branch that swallows writes into RAM. Options: mergerfs's quick start.
            options = [
              "nofail"
              "cache.files=off"
              "category.create=pfrd"
              "func.getattr=newest"
              "dropcacheonclose=false"
              "moveonenospc=true"
              "minfreespace=20G"
              "fsname=das"
            ]
            ++ map (serial: "x-systemd.requires-mounts-for=${mountOf serial}") (lib.attrNames disks);
          };
        };
      system.fsPackages = [ pkgs.mergerfs ];

      # Re-plug after the DAS loses power: systemd stops the LUKS units while the ext4 above them is still
      # tearing down, so they fail "busy" and leave mappers on the vanished disks, which a later attach
      # takes as "already active"; and nothing (nofail) pulls the pool again when the disks come back.
      # systemd-fsck then preens each disk before it mounts and refuses one that needs a manual fsck.
      systemd.services =
        lib.mapAttrs' (
          serial: _:
          lib.nameValuePair (cryptUnit serial) {
            overrideStrategy = "asDropin";
            serviceConfig.ExecStartPre = "-${dropStale} das-${serial}";
          }
        ) disks
        // {
          # Each disk's arrival, and every boot and switch (a deploy while the pool is down): idempotent.
          das-recover = {
            wantedBy = [
              "multi-user.target"
            ]
            ++ lib.mapAttrsToList (
              serial: model: "${utils.escapeSystemdPath "/dev/disk/by-id/ata-${model}_${serial}"}.device"
            ) disks;
            # A power supply that flaps: give up rather than remount into I/O errors forever.
            startLimitIntervalSec = 600;
            startLimitBurst = 5;
            path = [ config.systemd.package ];
            serviceConfig.Type = "oneshot";
            # A unit still "active" over a stale mapper: restarting it reattaches the disk.
            script =
              lib.concatMapStrings (serial: ''
                if ${dropStale} das-${serial}; then systemctl restart ${lib.escapeShellArg (cryptUnit serial)}; fi
              '') (lib.attrNames disks)
              + ''
                systemctl start --no-block srv-das.mount
              '';
          };
        };

      # Health in the journal (nisshi); the bridges pass SMART through without a -d flag.
      services.smartd.enable = true;
    };
}
