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

      # Health in the journal (nisshi); the bridges pass SMART through without a -d flag.
      services.smartd.enable = true;
    };
}
