# azukari, the lab's object store and its only backup (its own repo, consumed as `scorsi-azukari`):
# the store on hashira-01 (`azukari-server`), one `backup` bucket on a single DAS disk, and on each
# node one `azukari-backup-<export>` unit and timer per export (azukari ADR 0030: daily, the stores'
# days just after their 00:10 UTC seal), each sending one service's export under /persist/backups/<export> (ADR 0020, 0021). Both sides authenticate with hanko-ca's
# SVIDs (hanko-ca.nix): the store accepts the nodes' `azukari-backup` IDs, the nodes pin the store's ID.
#
# The store replicates every 6 h (azukari ADR 0008): to the Storage Box's `backup` subaccount over
# SSH (`offsite`, key azukari-offsite-key, the box's host key pinned) and to its own USB disk
# (`local`, modules/nixos/replica-disk.nix). The earlier pull to jiban and its restic copies are gone
# (README, Backups: the box's snapshots keep the last restic repository for a few weeks). The exports'
# names differ from the earlier directories under /persist/backups (forgejo, hanko, masu, nisshi),
# left in place, never reused.
#
# Data keys: secrets/<host>/azukari.yaml (`azukari-data-key`, 32 random bytes as 64 hex, azukari
# ADR 0006). Losing one loses that node's backups: it is in sops only, with the FIDO2 and admin
# recipients as its copies.
#
# Retention runs dry (`enabled = false`, owner, 2026-10-29): its daily `prune-completed` logs what it
# would delete, every snapshot is kept. The owner administers the store with `azukari` (member of
# `azukari-admin`, azukari ADR 0024). No alert on a stale
# `azukari_last_snapshot_timestamp_seconds` either: the lab has no alerting yet (hansho).
{ config, inputs, ... }:
let
  inherit (config.sekkeizu) domain kekkai;
  inherit (config.kiso) owner;
  trustDomain = "uchi.${domain}";
  storeHost = "hashira-01";
  box = config.sekkeizu.services.backup-offsite;
  # A subaccount's login is the first label of its host name (u<id>-sub<n>.your-storagebox.de).
  boxLogin = builtins.head (builtins.split "\\." box.host);
  # After kekkai (4800-4802) and hanko-ca (4900); kekkai.nix opens it to the backing-up nodes.
  # hashira-01's own run reaches its kekkai address over loopback, which neither kekkai's rules
  # nor the firewall filter.
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
    { config, pkgs, ... }:
    let
      metrics = "127.0.0.1:9477";
      knownHosts = pkgs.writeText "azukari-offsite-known-hosts" ''
        [${box.host}]:${toString box.port} ${box.hostKey}
      '';
    in
    {
      imports = [ inputs.scorsi-azukari.nixosModules.azukari-server ];

      users.users.${owner.name}.extraGroups = [ "azukari-admin" ];

      # ssh refuses a private key others can read.
      sops.secrets.azukari-offsite-key = {
        sopsFile = ../../secrets/${config.networking.hostName}/azukari-offsite.yaml;
        owner = "azukari";
        mode = "0400";
      };

      services.azukari-server = {
        enable = true;
        settings = {
          listen = [ "${kekkai.nodes.${config.networking.hostName}.ipv4}:${toString port}" ];
          listen_metrics = metrics;
          tls = tls "azukari-server";
          classes.standard.replicas = [
            "offsite"
            "local"
          ];
          replicas = [
            {
              name = "offsite";
              kind = "ssh";
              # Made once on the box (README, Backups): rsync creates the bucket's directory, not its parent.
              destination = "${boxLogin}@${box.host}:azukari";
              inherit (box) port;
              ssh_key_file = config.sops.secrets.azukari-offsite-key.path;
              known_hosts_file = "${knownHosts}";
              every = "6h";
            }
            {
              name = "local";
              kind = "dir";
              destination = "/mnt/replica/53RFWOD0T/azukari";
              mount_point = "/mnt/replica/53RFWOD0T";
              every = "6h";
            }
          ];
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
                # A week, dry, to see in the logs what a real prune would delete (owner, 2026-10-30);
                # back to a long keep before enabling.
                keep = "7d";
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
      # The observability stores on this host (observability/masu.nix, nisshi.nix).
      stores = lib.filter (store: config.services.${store}.enable or false) [
        "masu"
        "nisshi"
      ];
      exportHankoAccount = pkgs.writers.writeNu "export-hanko-account" (
        builtins.readFile ./hanko-account.nu
      );
      exportDays = pkgs.writers.writeNu "export-observability-days" (
        builtins.readFile ./observability-export.nu
      );
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
          # and environment as nixpkgs' forgejo-dump.
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
          hanko-account = lib.mkIf acme {
            user = "hanko";
            command = ''${exportHankoAccount} ${lib.escapeShellArg hanko.acme.accountKeyFile} "$EXPORT_DIR"'';
          };
        }
        # The stores' closed days, hard-linked (azukari ADR 0022): from /persist itself, since a link
        # cannot cross the bind mount of /var/lib/<store>, and with /persist writable as a whole
        # (ADR 0023). Same ext4 filesystem on hashira-01 (m75q.nix); the script checks it anyway.
        // lib.genAttrs' stores (
          store:
          lib.nameValuePair "${store}-days" {
            user = store;
            # Each store seals the previous UTC day at 00:10 UTC (their ADR 0006): daily, just after.
            every = "*-*-* 01:00:00 UTC";
            writablePaths = [ "/persist" ];
            command = ''${exportDays} /persist/var/lib/${store} "$EXPORT_DIR" azukari-export-${store}-days'';
          }
        );
      };

      # The module only creates the base (`d`); the old pull left it 0700 root:root, which export
      # users could not traverse.
      systemd.tmpfiles.rules = [ "z ${cfg.exportsDir} 0711 root root -" ];

      systemd.services = {
      }
      // lib.mapAttrs' (
        name: _:
        lib.nameValuePair "azukari-backup-${name}" { unitConfig.RequiresMountsFor = [ cfg.exportsDir ]; }
      ) cfg.exports
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
          path = [ pkgs.openssl ];
        };
      }
      // lib.genAttrs' stores (
        store:
        lib.nameValuePair "azukari-export-${store}-days" {
          after = [ "${store}.service" ];
          unitConfig.RequiresMountsFor = [ cfg.exportsDir ];
        }
      );
    };
}
