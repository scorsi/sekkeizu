# hikyaku, the node agent of the observability base (docs/observability.md). Pushes to masu and
# nisshi with the host's own token, pinning the stores' CA (ca.pem), through genkan on 443 (either
# genkan host; masu.nix and nisshi.nix add the SNI routes): the name in the URL only picks genkan,
# the TLS name stays the store's `serverName`. Targets follow what the host
# runs: hikyaku itself everywhere, node_exporter (node-exporter.nix) and annai, genkan, kekkai-node,
# masu and nisshi wherever their loopback /metrics is on.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu)
    domain
    genkanHosts
    kekkai
    observability
    ;
  genkan = "genkan.uchi.${domain}";
  genkanAddresses = map (host: kekkai.nodes.${host}.ipv4) genkanHosts;

  agent =
    platform:
    { config, ... }:
    let
      host = config.networking.hostName;
      self = observability.agents.${host};
      destination = name: {
        url = "https://${genkan}";
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

      services.hikyaku = {
        enable = true;
        inherit (self) spoolLimit;
        targets =
          serviceTargets
          // lib.optionalAttrs config.services.prometheus.exporters.node.enable {
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
  flake.modules.nixos.hikyaku =
    { config, ... }:
    {
      imports = [
        (agent "nixosModules")
      ];
      sops.secrets.hikyaku-token.restartUnits = [ "hikyaku.service" ];
      # hikyaku scrapes loopback and pushes to genkan.
      systemd.services.hikyaku.serviceConfig = {
        IPAddressDeny = "any";
        IPAddressAllow = [ "localhost" ] ++ genkanAddresses;
      };
      # The nodes ask Quad9, not annai (annai.nix); hikyaku tries each address in turn.
      networking.hosts = lib.genAttrs genkanAddresses (_: [ genkan ]);
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

  flake.modules.darwin.hikyaku =
    { config, ... }:
    {
      imports = [ (agent "darwinModules") ];
      # A dedicated, hidden, non-admin account (as the Forgejo runner's): the agent only needs its
      # spool, its token and logs that are world-readable (kekkai-node's), never root.
      users = {
        knownGroups = [ "_hikyaku" ];
        knownUsers = [ "_hikyaku" ];
        groups._hikyaku = {
          gid = 402;
          description = "hikyaku observability agent";
        };
        users._hikyaku = {
          uid = 402;
          gid = 402;
          home = "/var/lib/hikyaku";
          createHome = false;
          isHidden = true;
          shell = "/usr/bin/false";
          description = "hikyaku observability agent";
        };
      };
      services.hikyaku = {
        user = "_hikyaku";
        group = "_hikyaku";
      };
      sops.secrets.hikyaku-token.owner = "_hikyaku";
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
