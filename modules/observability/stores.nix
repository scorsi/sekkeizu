# masu (metrics) and nisshi (logs), the stores of the observability base (docs/observability.md),
# on ishizue: persistent, not exposed. They listen on the vfkit bridge address, for the agents of
# ishizue and jiban, and on ishizue's kekkai address for torii-cdg's (network/kekkai.nix opens the
# ports to it), and accept each host's token as `node:<host>`. Their own /metrics stay on
# loopback, for ishizue's hikyaku.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) bridgeAddresses kekkai observability;
  tokens = lib.mapAttrs' (
    host: hash: lib.nameValuePair hash "node:${host}"
  ) observability.tokenHashes;
  sopsFile = ../../secrets/ishizue/observability.yaml;
  retentionDays = builtins.fromJSON (builtins.readFile ../backup/observability-retention-days.json);
in
{
  flake.modules.nixos.observability-stores =
    { config, pkgs, ... }:
    let
      address = bridgeAddresses.${config.networking.hostName};
      overlay = kekkai.nodes.${config.networking.hostName}.ipv4;
      subnet = "${lib.concatStringsSep "." (lib.take 3 (lib.splitString "." address))}.0/24";
      archives = "${pkgs.python3}/bin/python3 ${../backup/observability-archives.py}";
      # How long jiban may miss pulls before a day exists nowhere but in the store itself.
      keepDays = 90;
      store = name: {
        enable = true;
        inherit retentionDays;
        listen = map (a: "${a}:${toString observability.stores.${name}.port}") [
          address
          overlay
        ];
        tls = {
          certFile = "${../../modules-private/observability/${name}.pem}";
          keyFile = config.sops.secrets."${name}-tls-key".path;
        };
        inherit tokens;
      };
    in
    {
      imports = [
        inputs.scorsi-masu.nixosModules.default
        inputs.scorsi-nisshi.nixosModules.default
      ];

      sops.secrets.masu-tls-key = {
        inherit sopsFile;
        restartUnits = [ "masu.service" ];
      };
      sops.secrets.nisshi-tls-key = {
        inherit sopsFile;
        restartUnits = [ "nisshi.service" ];
      };

      # kekkai0 and its address exist only while kekkai-node runs (a non-persistent TUN): without
      # this, a store starting while kekkai is down fails to bind and loses its bridge listener too.
      # A listener bound early serves the address whenever it is (re)added.
      boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;
      # At boot systemd-sysctl precedes sysinit.target; at a switch that sets it, only this orders them.
      systemd.services.masu.after = [ "systemd-sysctl.service" ];
      systemd.services.nisshi.after = [ "systemd-sysctl.service" ];

      services.masu = store "masu" // {
        metrics.listen = "127.0.0.1:9474";
      };
      services.nisshi = store "nisshi" // {
        metrics.listen = "127.0.0.1:9475";
      };

      sekkeizu.persist.directories =
        map
          (name: {
            directory = "/var/lib/${name}";
            user = name;
            group = name;
            mode = "0750";
          })
          [
            "masu"
            "nisshi"
          ];

      # Backups (backup-source), twice a day: RPO 12 h on jiban (modules/meta/observability.nix).
      # A day is sealed once its manifest exists, and never changes again (both storage formats):
      # hard links into /persist/backups, data before manifest, no extra space. The open day is a
      # COPY of its prefix up to the committed length in state.json (`<day>.ndjson.zst.partial`,
      # replaced each run, dropped once the day is linked): a link would follow the live file, and
      # the bytes past that length may be torn. Links of days older than `keepDays` are deleted, so
      # the stores' own retention (400 days of data) frees space again on this disk; jiban and
      # restic keep every day (pull never deletes), nisshi's whole manifest chain included. On
      # /persist itself, since a link cannot cross the bind mount of /var/lib/<store>. LAST_RUN
      # (time, then every exported sealed file) is written last, only after a successful run:
      # jiban's pull checks it (backup/pull.nix).
      #
      # The export directories are root's, 0700 with an ACL for backup-source's account (traverse
      # and read, as for forgejo-dump): the links share the store's inodes, masu's are 0644, so the
      # directories alone keep every other account out. Fixed on each run, existing trees included.
      systemd.services.observability-backup = {
        description = "Export the days of masu and nisshi into /persist/backups";
        startAt = [
          "*-*-* 04:45:00"
          "*-*-* 16:45:00"
        ];
        path = [
          pkgs.acl
          pkgs.coreutils
          pkgs.findutils
        ];
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          for store in masu nisshi; do
            out=/persist/backups/$store
            install -d -m 0700 -o root -g root "$out"
            # chmod drops the ACL mask; setfacl below recomputes it.
            find "$out" -type d -exec chown root:root {} + -exec chmod 0700 {} +
            ${archives} export "/persist/var/lib/$store" "$out" ${toString retentionDays} ${toString keepDays}
            # On the shared inodes, so backup can read the store's own copies too, never write them.
            setfacl -R -m u:backup:rX "$out"
            ${archives} marker "$out"
            setfacl -m u:backup:r "$out/LAST_RUN"
          done
        '';
      };

      # From the bridge's subnet to the bridge address only (jiban and ishizue's own agents; vfkit's
      # NAT hands out a /24). Trusted interfaces are accepted before any of these rules, so the
      # stores' ports are refused on them first, except loopback (ishizue's own hikyaku) and kekkai0,
      # where kekkai's own allowInbound (network/kekkai.nix) already limits which peer reaches them.
      networking.firewall.extraCommands = lib.concatMapStrings (
        store:
        let
          port = toString store.port;
        in
        ''
          iptables -A nixos-fw -s ${subnet} -d ${address} -p tcp --dport ${port} -j nixos-fw-accept
        ''
        +
          lib.concatMapStrings
            (iface: ''
              iptables -I nixos-fw -i ${iface} -p tcp --dport ${port} -j nixos-fw-refuse
            '')
            (
              lib.subtractLists [
                "lo"
                "kekkai0"
              ] config.networking.firewall.trustedInterfaces
            )
      ) (lib.attrValues observability.stores);
    };
}
