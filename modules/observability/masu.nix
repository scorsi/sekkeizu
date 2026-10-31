# masu (metrics), a store of the observability base (docs/observability.md). Persistent, not
# exposed: it listens on the host's kekkai address only, which genkan (both hosts) forwards the
# store's TLS name to, raw (the agents push to genkan's `services` listener; network/kekkai.nix opens the
# port to the genkan hosts), and accepts each host's token as `node:<host>` and the operator's
# as `reader`. Its own /metrics stays on loopback, for the host's hikyaku.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) genkanHosts kekkai observability;
  inherit (config.kiso) owner;
  tokens =
    lib.mapAttrs' (host: hash: lib.nameValuePair hash "node:${host}") observability.tokenHashes
    // lib.genAttrs observability.stores.masu.readerTokenHashes (_: "reader");
  retentionDays = builtins.fromJSON (builtins.readFile ./retention-days.json);
  # The hosts whose hikyaku pushes here, and the genkan hosts themselves: a host's own genkan sees
  # its own kekkai address as the peer (hairpin), the other's sees it over kekkai. Both families:
  # the nodes pin genkan's IPv4, jiban resolves it through annai (A and AAAA).
  allow = lib.concatMap (h: [
    kekkai.nodes.${h}.ipv4
    kekkai.nodes.${h}.ipv6
  ]) (lib.unique (lib.attrNames observability.agents ++ genkanHosts));
  store = observability.stores.masu;
in
{
  # TLS end to end: genkan forwards the certificate's name by SNI (genkan ADR 0012).
  flake.modules.nixos.genkan.services.genkan.passthrough.masu = {
    listener = "services";
    sni = [ store.serverName ];
    backend = "${kekkai.nodes.${store.host}.ipv4}:${toString store.port}";
    inherit allow;
  };

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
        # Only genkan pushes to it (over kekkai, or locally on its own host), hikyaku scrapes loopback.
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
      # first, except loopback (the host's own hikyaku and genkan) and kekkai0, where kekkai's allowInbound
      # (network/kekkai.nix) already limits which peer reaches it.
      networking.firewall.extraCommands = lib.concatMapStrings (iface: ''
        iptables -I nixos-fw -i ${iface} -p tcp --dport ${toString port} -j nixos-fw-refuse
      '') (lib.subtractLists [ "lo" "kekkai0" ] config.networking.firewall.trustedInterfaces);
    };

  # The operator's reader token on jiban, for the manual silence check (/v1/status: last receive
  # time per agent, refreshed by a successful push only):
  #   curl --cacert modules-private/observability/ca.pem \
  #     --resolve masu.internal:9443:<a genkan host's kekkai address> \
  #     -H "Authorization: Bearer $(cat /run/secrets/masu-reader-token)" \
  #     https://masu.internal:9443/v1/status | jq
  flake.modules.darwin.masu-reader =
    { config, ... }:
    {
      sops.secrets.masu-reader-token = {
        sopsFile = ../../secrets/${config.networking.hostName}/masu-reader.yaml;
        owner = owner.name;
      };
    };
}
