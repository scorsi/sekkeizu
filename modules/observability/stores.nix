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

      # Backups (backup-source): a day is sealed once its manifest exists, and never changes again
      # (both storage formats). Hard links into /persist/backups, data before manifest: no extra
      # space. Data retention is 400 days (plus each node's last complete day); FORMAT and all
      # manifests stay, since nisshi verifies its whole chain. On /persist itself, since a link
      # cannot cross the bind mount of /var/lib/<store>. jiban pulls them at 05:15.
      systemd.services.observability-backup = {
        description = "Hard-link the sealed days of masu and nisshi into /persist/backups";
        startAt = "*-*-* 04:45:00";
        serviceConfig.Type = "oneshot";
        script = ''
          for store in masu nisshi; do
            ${pkgs.python3}/bin/python3 ${../backup/observability-archives.py} link \
              "/persist/var/lib/$store" "/persist/backups/$store" ${toString retentionDays}
          done
          # nisshi writes 0640: backup-source's account reads through an ACL, as for forgejo-dump
          # (on the shared inodes, so it can read the store's own copies too, never write them).
          ${pkgs.acl}/bin/setfacl -R -m u:backup:rX /persist/backups/masu /persist/backups/nisshi
        '';
      };

      # Matched on the bridge address, as annai's port 53: the tailnet never reaches the stores.
      networking.firewall.extraCommands = lib.concatMapStrings (store: ''
        iptables -A nixos-fw -d ${address} -p tcp --dport ${toString store.port} -j nixos-fw-accept
      '') (lib.attrValues observability.stores);
    };
}
