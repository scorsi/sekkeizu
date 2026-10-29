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
  inherit (config.kiso) owner;
  tokens =
    lib.mapAttrs' (host: hash: lib.nameValuePair hash "node:${host}") observability.tokenHashes
    // lib.genAttrs observability.stores.masu.readerTokenHashes (_: "reader");
  retentionDays = builtins.fromJSON (builtins.readFile ./retention-days.json);
in
{
  flake.modules.nixos.masu =
    { config, ... }:
    let
      overlay = kekkai.nodes.${config.networking.hostName}.ipv4;
      port = observability.stores.masu.port;
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

      # Trusted interfaces are accepted before any rule, so the port is refused on them
      # first, except loopback (the host's own hikyaku) and kekkai0, where kekkai's own allowInbound
      # (network/kekkai.nix) already limits which peer reaches it.
      networking.firewall.extraCommands = lib.concatMapStrings (iface: ''
        iptables -I nixos-fw -i ${iface} -p tcp --dport ${toString port} -j nixos-fw-refuse
      '') (lib.subtractLists [ "lo" "kekkai0" ] config.networking.firewall.trustedInterfaces);
    };

  # The operator's reader token on jiban, for the manual silence check (/v1/status: last receive
  # time per agent, refreshed by a successful push only):
  #   curl --cacert modules-private/observability/ca.pem \
  #     --resolve masu.internal:9472:<masu's host kekkai address> \
  #     -H "Authorization: Bearer $(cat /run/secrets/masu-reader-token)" \
  #     https://masu.internal:9472/v1/status | jq
  flake.modules.darwin.masu-reader =
    { config, ... }:
    {
      sops.secrets.masu-reader-token = {
        sopsFile = ../../secrets/${config.networking.hostName}/masu-reader.yaml;
        owner = owner.name;
      };
    };
}
