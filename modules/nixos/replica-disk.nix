# The USB disk azukari-server replicates its buckets to (`dir` replica `local`, modules/backup/azukari.nix):
# a salvaged Toshiba MQ01ABD050, one LUKS + ext4, apart from the DAS (not under /mnt/das, not in
# mergerfs) so the copy never shares a disk or a key with the store it copies. Its own LUKS key
# (secrets/replica/luks.yaml): moving the disk = import this feature on the new host and change the
# file's recipient in .sops.yaml (`sops updatekeys`).
#
# Formatting, once (destroys the disk's content), with the key on stdin, never on disk:
#   sops -d --extract '["replica-luks-key"]' secrets/replica/luks.yaml \
#     | ssh root@<host> cryptsetup luksFormat --batch-mode --key-file=- /dev/disk/by-id/<id>
#   then `cryptsetup open --key-file=- /dev/disk/by-id/<id> replica-<serial>` the same way, and
#   `mkfs.ext4 -m 0 -L replica-<serial> /dev/mapper/replica-<serial>` (ext4 keeps 16 characters of
#   the label; the mount goes by the mapper name). sops runs from `nix develop .#infra` (its FIDO2
#   age plugin). The key has no trailing newline: sops-nix writes exactly these bytes.
{
  flake.modules.nixos.replica-disk =
    {
      config,
      pkgs,
      utils,
      ...
    }:
    let
      serial = "53RFWOD0T";
      name = "replica-${serial}";
      mountPoint = "/mnt/replica/${serial}";
      mountUnit = "${utils.escapeSystemdPath mountPoint}.mount";
    in
    {
      sops.secrets.replica-luks-key.sopsFile = ../../secrets/replica/luks.yaml;

      # Unlocked in stage 2, after sops has decrypted the key; nofail so the host boots without the disk.
      environment.etc.crypttab.text = ''
        ${name} /dev/disk/by-id/ata-TOSHIBA_MQ01ABD050_${serial} ${config.sops.secrets.replica-luks-key.path} luks,nofail
      '';

      fileSystems.${mountPoint} = {
        device = "/dev/mapper/${name}";
        fsType = "ext4";
        options = [
          "nofail"
          "noatime"
        ];
      };

      # azukari's `dir` destination, made each time the disk mounts and before the store starts (azukari
      # ADR 0008, its nix/tests/replication.nix): bound to the mount rather than tmpfiles, so it never
      # lands on the root filesystem when the disk is absent.
      systemd.services.azukari-replica-dir = {
        wantedBy = [ mountUnit ];
        bindsTo = [ mountUnit ];
        after = [ mountUnit ];
        before = [ "azukari-server.service" ];
        serviceConfig.Type = "oneshot";
        script = "${pkgs.coreutils}/bin/install -d -o azukari -g azukari -m 0700 ${mountPoint}/azukari";
      };
    };
}
