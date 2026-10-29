# azukari, the lab's object store (its own repo, consumed as `scorsi-azukari`): the store on
# hashira-01 (`azukari-server`), one `backup` bucket on a single DAS disk, and on each node a daily
# `azukari-backup` run (`azukari-backup`) that sends what the node's services export under
# /persist/backups/<export> (azukari ADR 0020, 0021). Both sides authenticate with hanko-ca's SVIDs
# (hanko-ca.nix): the store accepts the nodes' `azukari-backup` IDs, the nodes pin the store's ID.
#
# Runs next to the earlier backups (backup/pull.nix, the masu and nisshi exports) until a restore
# from azukari has been compared with them; the exports here take names of their own so the two
# systems never share a directory. hashira-01 does not back up yet: masu's and nisshi's exports are
# hard links to their stores' 0640 files, in the stores' own groups, which azukari-backup cannot read.
#
# Data keys: secrets/<host>/azukari.yaml (`azukari-data-key`, 32 random bytes as 64 hex, azukari
# ADR 0006). Losing one loses that node's backups: it is in sops only, with the FIDO2 and admin
# recipients as its copies.
#
# No retention yet (owner, 2026-10-29): every snapshot is kept. No alert on a stale
# `azukari_last_snapshot_timestamp_seconds` either: the lab has no alerting yet (hanshou).
{ config, inputs, ... }:
let
  inherit (config.sekkeizu) domain kekkai;
  trustDomain = "uchi.${domain}";
  storeHost = "hashira-01";
  # After kekkai (4800-4802) and hanko-ca (4900); kekkai.nix opens it to the backing-up nodes.
  port = 5000;
  # The 1 TB disk (modules/nixos/das.nix), the healthiest; no service keeps live data on the DAS.
  disk = "/mnt/das/ZN1374ZM";
  # The hosts hanko-ca issues an `azukari-backup` SVID to (hanko-ca.nix).
  backupHosts = [
    "ishizue"
    "hashira-01"
    "hashira-02"
  ];

  idOf = host: service: "spiffe://${trustDomain}/${host}/${service}";
  # hanko-node's files for an internal certificate (hanko ADR 0004), group-readable by the service.
  tls = service: {
    trust_domain = trustDomain;
    svid_file = "/var/lib/hanko/${service}/svid.pem";
    key_file = "/var/lib/hanko/${service}/key.pem";
    bundle_file = "/var/lib/hanko/${service}/bundle.pem";
  };
in
{
  flake.modules.nixos.azukari-server =
    { config, ... }:
    let
      metrics = "127.0.0.1:9477";
    in
    {
      imports = [ inputs.scorsi-azukari.nixosModules.azukari-server ];

      services.azukari-server = {
        enable = true;
        settings = {
          listen = [ "${kekkai.nodes.${config.networking.hostName}.ipv4}:${toString port}" ];
          listen_metrics = metrics;
          tls = tls "azukari-server";
          classes.standard.replicas = [ ];
          buckets = [
            {
              name = "backup";
              type = "backup";
              class = "standard";
              path = "${disk}/azukari/backup";
              mount_point = disk;
              # A chunk is at most 4 MiB plus the 42 bytes of its seal (azukari ADR 0006).
              max_object_bytes = 16 * 1024 * 1024;
              # Above mergerfs's own minfreespace (20G, das.nix), which shares this disk.
              disk_reserve = "50GiB";
              nodes = map (host: idOf host "azukari-backup") backupHosts;
              retention = {
                enabled = false;
                keep = "365d";
                run_at = "03:30";
              };
            }
          ];
        };
      };

      # Binding the kekkai address needs kekkai.nix's ip_nonlocal_bind: at boot systemd-sysctl
      # precedes sysinit.target; at a switch that sets it, only this orders them.
      systemd.services.azukari-server.after = [ "systemd-sysctl.service" ];

      # Its loopback /metrics, for the host's hikyaku (hikyaku.nix lists the services with a
      # `metrics.listen` option; azukari's is in its TOML).
      services.hikyaku.targets.azukari-server.url = "http://${metrics}/metrics";
    };

  flake.modules.nixos.azukari-backup =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      host = config.networking.hostName;
      cfg = config.services.azukari-backup;
      forgejo = config.services.forgejo;
      hanko = config.services.hanko-node;
      # The host's hanko-node holds an ACME account (hanko.nix): its key is exported.
      acme = lib.any (c: c.issuer == "acme") (lib.attrValues (hanko.certificates or { }));
      # shortcut: the same script as hanko.nix's hanko-backup, until both move to Nushell (the old
      # backups' removal).
      hankoAccount = pkgs.writeShellApplication {
        name = "export-hanko-account";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.diffutils
          pkgs.openssl
        ];
        text = builtins.readFile ./hanko-account.sh;
      };
    in
    {
      imports = [ inputs.scorsi-azukari.nixosModules.azukari-backup ];

      sops.secrets.azukari-data-key = {
        sopsFile = ../../secrets/${host}/azukari.yaml;
        owner = "azukari-backup";
        mode = "0400";
      };

      services.azukari-backup = {
        enable = true;
        settings = {
          server = "https://${kekkai.nodes.${storeHost}.ipv4}:${toString port}";
          bucket = "backup";
          data_key_file = config.sops.secrets.azukari-data-key.path;
          tls = tls "azukari-backup" // {
            server_id = idOf storeHost "azukari-server";
          };
        };

        exports = {
          # A full dump, replaced at every run; the store dedups what did not change. Same command
          # and environment as nixpkgs' forgejo-dump, which keeps running for backup/pull.nix.
          forgejo-dump = lib.mkIf forgejo.enable {
            inherit (forgejo) user group;
            command = ''
              cd "$EXPORT_DIR"
              rm -f forgejo.tar
              ${lib.getExe forgejo.package} dump --type tar --file forgejo.tar
              # Forgejo leaves its archive 0600; the backup reads it through the group.
              chmod 0640 forgejo.tar
            '';
          };
          # Every account key ever used, by digest: an older one may still be pinned in CAA.
          hanko-account = lib.mkIf acme {
            user = "hanko";
            command = ''${lib.getExe hankoAccount} ${lib.escapeShellArg hanko.acme.accountKeyFile} "$EXPORT_DIR"'';
          };
        };
      };

      systemd.services = {
        azukari-backup.unitConfig.RequiresMountsFor = [ cfg.exportsDir ];
      }
      // lib.optionalAttrs forgejo.enable {
        azukari-export-forgejo-dump = {
          after = [ "forgejo.service" ];
          unitConfig.RequiresMountsFor = [ cfg.exportsDir ];
          environment = {
            USER = forgejo.user;
            HOME = forgejo.stateDir;
            FORGEJO_WORK_DIR = forgejo.stateDir;
            FORGEJO_CUSTOM = forgejo.customDir;
          };
          # SQLite takes a write lock even to read (Forgejo's immediate transactions).
          serviceConfig.ReadWritePaths = [ forgejo.stateDir ];
        };
      }
      // lib.optionalAttrs acme {
        azukari-export-hanko-account = {
          after = [ "hanko-node.service" ];
          unitConfig.RequiresMountsFor = [
            cfg.exportsDir
            "/var/lib/hanko"
          ];
        };
      };

      # azukari's module creates the base only when absent: fix an existing one (backup/pull.nix's
      # `backup` account joins the group to keep crossing it).
      systemd.tmpfiles.rules = [ "z ${cfg.exportsDir} 0750 root azukari-backup -" ];
    };
}
