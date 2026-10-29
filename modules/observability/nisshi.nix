# nisshi (logs), a store of the observability base (docs/observability.md). Persistent, not
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
    // lib.genAttrs observability.stores.nisshi.readerTokenHashes (_: "reader");
  retentionDays = builtins.fromJSON (builtins.readFile ./retention-days.json);
in
{
  flake.modules.nixos.nisshi =
    { config, ... }:
    let
      overlay = kekkai.nodes.${config.networking.hostName}.ipv4;
      port = observability.stores.nisshi.port;
    in
    {
      imports = [ inputs.scorsi-nisshi.nixosModules.default ];

      sops.secrets.nisshi-tls-key = {
        sopsFile = ../../secrets/${config.networking.hostName}/observability.yaml;
        restartUnits = [ "nisshi.service" ];
      };

      systemd.services.nisshi = {
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

      services.nisshi = {
        enable = true;
        inherit retentionDays tokens;
        listen = [ "${overlay}:${toString port}" ];
        tls = {
          certFile = "${../../modules-private/observability/nisshi.pem}";
          keyFile = config.sops.secrets.nisshi-tls-key.path;
        };
        metrics.listen = "127.0.0.1:9475";
      };

      sekkeizu.persist.directories = [
        {
          directory = "/var/lib/nisshi";
          user = "nisshi";
          group = "nisshi";
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
  #     --resolve nisshi.internal:9473:<nisshi's host kekkai address> \
  #     -H "Authorization: Bearer $(cat /run/secrets/nisshi-reader-token)" \
  #     https://nisshi.internal:9473/v1/status | jq
  flake.modules.darwin.nisshi-reader =
    { config, ... }:
    {
      sops.secrets.nisshi-reader-token = {
        sopsFile = ../../secrets/${config.networking.hostName}/nisshi-reader.yaml;
        owner = owner.name;
      };
    };
}
