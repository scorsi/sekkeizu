# masu (metrics), a store of the observability base (docs/observability.md). Persistent, not
# exposed: it listens on the host's kekkai address only, where every agent pushes (network/kekkai.nix
# opens the port to each peer), and accepts each host's token as `node:<host>` and the operator's
# as `reader`. Its own /metrics stays on loopback, for the host's hikyaku.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) kekkai observability;
  tokens =
    lib.mapAttrs' (host: hash: lib.nameValuePair hash "node:${host}") observability.tokenHashes
    // lib.genAttrs observability.readerTokenHashes (_: "reader");
  retentionDays = builtins.fromJSON (builtins.readFile ../backup/observability-retention-days.json);
in
{
  flake.modules.nixos.masu =
    { config, pkgs, ... }:
    let
      overlay = kekkai.nodes.${config.networking.hostName}.ipv4;
      port = observability.stores.masu.port;
      archives = "${pkgs.python3}/bin/python3 ${../backup/observability-archives.py}";
      # How long the export keeps a day's links; masu's own retention frees it afterwards.
      keepDays = 90;
    in
    {
      imports = [ inputs.scorsi-masu.nixosModules.default ];

      sops.secrets.masu-tls-key = {
        sopsFile = ../../secrets/${config.networking.hostName}/observability.yaml;
        restartUnits = [ "masu.service" ];
      };

      systemd.services.masu = {
        # Binding the kekkai address needs kekkai.nix's ip_nonlocal_bind: at boot systemd-sysctl
        # precedes sysinit.target; at a switch that sets it, only this orders them.
        after = [ "systemd-sysctl.service" ];
        # Only the agents talk to it (kekkai), and hikyaku scrapes it on loopback.
        serviceConfig = {
          IPAddressDeny = "any";
          IPAddressAllow = [
            "localhost"
            kekkai.ipv4Prefix
          ];
        };
      };

      services.masu = {
        enable = true;
        inherit retentionDays tokens;
        listen = [ "${overlay}:${toString port}" ];
        tls = {
          certFile = "${../../modules-private/observability/masu.pem}";
          keyFile = config.sops.secrets.masu-tls-key.path;
        };
        metrics.listen = "127.0.0.1:9474";
      };

      sekkeizu.persist.directories = [
        {
          directory = "/var/lib/masu";
          user = "masu";
          group = "masu";
          mode = "0750";
        }
      ];

      # Export for the backups, twice a day (modules/meta/observability.nix). A day is sealed once
      # its manifest exists, and never changes again (both storage formats): hard links into
      # /persist/backups, data before manifest, no extra space. The open day is a COPY of its prefix
      # up to the committed length in state.json (`<day>.ndjson.zst.partial`, replaced each run,
      # dropped once the day is linked): a link would follow the live file, and the bytes past that
      # length may be torn. Links of days older than `keepDays` are deleted, so masu's own
      # retention (400 days of data) frees space again on this disk. On /persist itself, since a
      # link cannot cross the bind mount of /var/lib/masu. LAST_RUN (time, then every exported
      # sealed file) is written last, only after a successful run.
      #
      # The export directory is root's, 0700: the links share masu's inodes, which are 0644, so the directory alone keeps
      # every other account out. Fixed on each run, existing trees included.
      systemd.services.masu-backup = {
        description = "Export the days of masu into /persist/backups";
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
          out=/persist/backups/masu
          install -d -m 0700 -o root -g root "$out"
          find "$out" -type d -exec chown root:root {} + -exec chmod 0700 {} +
          ${archives} export "/persist/var/lib/masu" "$out" ${toString retentionDays} ${toString keepDays}
          ${archives} marker "$out"
        '';
      };

      # Trusted interfaces are accepted before any rule, so the port is refused on them
      # first, except loopback (the host's own hikyaku) and kekkai0, where kekkai's own allowInbound
      # (network/kekkai.nix) already limits which peer reaches it.
      networking.firewall.extraCommands = lib.concatMapStrings (iface: ''
        iptables -I nixos-fw -i ${iface} -p tcp --dport ${toString port} -j nixos-fw-refuse
      '') (lib.subtractLists [ "lo" "kekkai0" ] config.networking.firewall.trustedInterfaces);
    };
}
