# hikyaku, the node agent of the observability base (docs/observability.md), with node_exporter
# as the host exporter until mihari exists. Pushes to masu and nisshi with the host's own token,
# pinning the stores' CA (ca.pem). Targets follow what the host runs: node and hikyaku itself
# everywhere, annai, genkan, kekkai-node, masu and nisshi wherever their loopback /metrics is on.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) bridgeAddresses kekkai observability;

  agent =
    platform:
    { config, ... }:
    let
      host = config.networking.hostName;
      self = observability.agents.${host};
      destination = name: {
        url = "https://${self.storeAddress}:${toString observability.stores.${name}.port}";
        inherit (observability.stores.${name}) serverName;
        caFile = "${../../modules-private/observability/ca.pem}";
        tokenFile = config.sops.secrets.hikyaku-token.path;
      };
      # A loopback /metrics of a service this host runs, by name; absent when it has none.
      serviceTargets = lib.filterAttrs (_: t: t != null) (
        lib.genAttrs
          [
            "annai"
            "genkan"
            "kekkai-node"
            "masu"
            "nisshi"
          ]
          (
            name:
            let
              listen = config.services.${name}.metrics.listen or null;
            in
            if (config.services.${name}.enable or false) && listen != null then
              { url = "http://${listen}/metrics"; }
            else
              null
          )
      );
    in
    {
      imports = [ inputs.scorsi-hikyaku.${platform}.default ];

      sops.secrets.hikyaku-token.sopsFile = ../../secrets/${host}/hikyaku.yaml;

      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = "127.0.0.1";
      };

      services.hikyaku = {
        enable = true;
        inherit (self) spoolLimit;
        targets = serviceTargets // {
          # node_exporter on Linux is well above the 2000 series meant for house services.
          node = {
            url = "http://127.0.0.1:${toString config.services.prometheus.exporters.node.port}/metrics";
            maxSeries = 10000;
          };
        };
        masu = destination "masu";
        nisshi = destination "nisshi";
      };
    };
in
{
  flake.modules.nixos.observability-agent = {
    imports = [
      (agent "nixosModules")
    ];
    sops.secrets.hikyaku-token.restartUnits = [ "hikyaku.service" ];
    # hikyaku scrapes loopback and pushes to the stores' host, at either of its addresses.
    systemd.services.hikyaku.serviceConfig = {
      IPAddressDeny = "any";
      IPAddressAllow = [
        "localhost"
      ]
      ++ lib.unique (
        lib.concatMap (
          store:
          let
            host = observability.stores.${store}.host;
          in
          [
            bridgeAddresses.${host}
            kekkai.nodes.${host}.ipv4
          ]
        ) (lib.attrNames observability.stores)
      );
    };
    # journald stays the logs' second buffer (/var/log is persistent); the spool must survive too.
    sekkeizu.persist.directories = [
      {
        directory = "/var/lib/hikyaku";
        user = "hikyaku";
        group = "hikyaku";
        mode = "0700";
      }
    ];
  };

  flake.modules.darwin.observability-agent =
    { config, ... }:
    {
      imports = [ (agent "darwinModules") ];
      # Darwin has no SOPS restart hooks; run after its secret installation (order 1500).
      system.activationScripts.hikyaku-secrets.text = ''
        if [ "$(cat /var/db/hikyaku.secrets 2>/dev/null)" != "${config.sops.secrets.hikyaku-token.sopsFileHash}" ]; then
          /bin/launchctl kickstart -k system/${config.launchd.daemons.hikyaku.serviceConfig.Label}
          printf '%s\n' '${config.sops.secrets.hikyaku-token.sopsFileHash}' > /var/db/hikyaku.secrets
        fi
      '';
      system.activationScripts.postActivation.text = lib.mkOrder 1650 config.system.activationScripts.hikyaku-secrets.text;
      # No journald on macOS: kekkai-node's LaunchDaemon writes its log lines to this file.
      services.hikyaku.files = lib.optionalAttrs (config.services.kekkai-node.enable or false) {
        kekkai-node.path = config.launchd.daemons.kekkai-node.serviceConfig.StandardErrorPath;
      };
    };
}
