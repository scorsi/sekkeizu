# masu (metrics) and nisshi (logs), the stores of the observability base (docs/observability.md),
# on ishizue: persistent, not exposed. They listen on the vfkit bridge address, for the agents of
# ishizue and jiban (torii-cdg spools until kekkai links the hosts), and accept each host's token
# as `node:<host>`. Their own /metrics stay on loopback, for ishizue's hikyaku.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) bridgeAddresses observability;
  tokens = lib.mapAttrs' (
    host: hash: lib.nameValuePair hash "node:${host}"
  ) observability.tokenHashes;
  sopsFile = ../../secrets/ishizue/observability.yaml;
in
{
  flake.modules.nixos.observability-stores =
    { config, pkgs, ... }:
    let
      address = bridgeAddresses.${config.networking.hostName};
      store = name: {
        enable = true;
        listen = [ "${address}:${toString observability.stores.${name}.port}" ];
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
      # space, and a copy outlives the store's retention. On /persist itself, since a link cannot
      # cross the bind mount of /var/lib/<store>. jiban pulls them at 05:15.
      systemd.services.observability-backup = {
        description = "Hard-link the sealed days of masu and nisshi into /persist/backups";
        startAt = "*-*-* 04:45:00";
        serviceConfig.Type = "oneshot";
        script = ''
          for store in masu nisshi; do
            src=/persist/var/lib/$store dst=/persist/backups/$store
            cd "$src"
            [ -e "$dst/FORMAT" ] || { mkdir -p "$dst"; ln FORMAT "$dst/FORMAT"; }
            find . -name '*.manifest.json' | while read -r manifest; do
              data=''${manifest%.manifest.json}.ndjson.zst
              [ -e "$dst/$manifest" ] && continue
              mkdir -p "$dst/$(dirname "$manifest")"
              # A manifest without its data file: retention already deleted the data.
              if [ -e "$data" ] && [ ! -e "$dst/$data" ]; then ln "$data" "$dst/$data"; fi
              ln "$manifest" "$dst/$manifest"
            done
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
