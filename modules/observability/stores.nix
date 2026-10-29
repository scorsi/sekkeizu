# masu (metrics) and nisshi (logs), the stores of the observability base (docs/observability.md):
# persistent, not exposed. They listen on the host's kekkai address only, where every agent pushes
# (network/kekkai.nix opens the ports to each peer), and accept each host's token as `node:<host>`
# and the operator's as `reader`. Their own /metrics stay on loopback, for the host's hikyaku.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) kekkai observability;
  inherit (config.kiso) owner;
  tokens =
    lib.mapAttrs' (host: hash: lib.nameValuePair hash "node:${host}") observability.tokenHashes
    // lib.genAttrs observability.readerTokenHashes (_: "reader");
  retentionDays = builtins.fromJSON (builtins.readFile ../backup/observability-retention-days.json);
in
{
  flake.modules.nixos.observability-stores =
    { config, pkgs, ... }:
    let
      overlay = kekkai.nodes.${config.networking.hostName}.ipv4;
      sopsFile = ../../secrets/${config.networking.hostName}/observability.yaml;
      archives = "${pkgs.python3}/bin/python3 ${../backup/observability-archives.py}";
      # How long the export keeps a day's links; the stores' own retention frees it afterwards.
      keepDays = 90;
      unit = {
        # At boot systemd-sysctl precedes sysinit.target; at a switch that sets it, only this orders them.
        after = [ "systemd-sysctl.service" ];
        # Only the agents talk to a store (kekkai), and hikyaku scrapes it on loopback.
        serviceConfig = {
          IPAddressDeny = "any";
          IPAddressAllow = [
            "localhost"
            kekkai.ipv4Prefix
          ];
        };
      };
      store = name: {
        enable = true;
        inherit retentionDays;
        listen = [ "${overlay}:${toString observability.stores.${name}.port}" ];
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
      systemd.services.masu = unit;
      systemd.services.nisshi = unit;

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

      # Exports for the backups, twice a day (modules/meta/observability.nix). A day is sealed once its manifest exists, and never changes again (both storage formats):
      # hard links into /persist/backups, data before manifest, no extra space. The open day is a
      # COPY of its prefix up to the committed length in state.json (`<day>.ndjson.zst.partial`,
      # replaced each run, dropped once the day is linked): a link would follow the live file, and
      # the bytes past that length may be torn. Links of days older than `keepDays` are deleted, so
      # the stores' own retention (400 days of data) frees space again on this disk. On /persist
      # itself, since a link cannot cross the bind mount of /var/lib/<store>. LAST_RUN (time, then
      # every exported sealed file) is written last, only after a successful run.
      #
      # The export directories are root's, 0700: the links share the store's inodes, masu's are
      # 0644, so the directories alone keep every other account out. Fixed on each run, existing
      # trees included.
      systemd.services.observability-backup = {
        description = "Export the days of masu and nisshi into /persist/backups";
        startAt = [
          "*-*-* 04:45:00"
          "*-*-* 16:45:00"
        ];
        path = [
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
            find "$out" -type d -exec chown root:root {} + -exec chmod 0700 {} +
            ${archives} export "/persist/var/lib/$store" "$out" ${toString retentionDays} ${toString keepDays}
            ${archives} marker "$out"
          done
        '';
      };

      # Trusted interfaces are accepted before any rule, so the stores' ports are refused on them
      # first, except loopback (the host's own hikyaku) and kekkai0, where kekkai's own allowInbound
      # (network/kekkai.nix) already limits which peer reaches them.
      networking.firewall.extraCommands = lib.concatMapStrings (
        store:
        lib.concatMapStrings
          (iface: ''
            iptables -I nixos-fw -i ${iface} -p tcp --dport ${toString store.port} -j nixos-fw-refuse
          '')
          (
            lib.subtractLists [
              "lo"
              "kekkai0"
            ] config.networking.firewall.trustedInterfaces
          )
      ) (lib.attrValues observability.stores);
    };

  # The operator's reader token on jiban, for the manual silence check (/v1/status: last receive
  # time per agent, refreshed by a successful push only):
  #   curl --cacert modules-private/observability/ca.pem \
  #     --resolve masu.internal:9472:<the stores' host kekkai address> \
  #     -H "Authorization: Bearer $(cat /run/secrets/observability-reader-token)" \
  #     https://masu.internal:9472/v1/status | jq
  # nisshi alike on nisshi.internal:9473.
  flake.modules.darwin.observability-reader =
    { config, ... }:
    {
      sops.secrets.observability-reader-token = {
        sopsFile = ../../secrets/${config.networking.hostName}/observability-reader.yaml;
        owner = owner.name;
      };
    };
}
