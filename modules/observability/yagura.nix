# Yagura reads the stores with dedicated reader identities; genkan holds the browser-facing TLS.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu)
    genkanRelayPort
    kekkai
    observability
    services
    ;
  serverHost = "hashira-01";
  port = 9481;
  storeConfig =
    config: name:
    let
      store = observability.stores.${name};
    in
    {
      url = "https://${store.serverName}:${toString store.port}";
      tokenFile = config.sops.secrets."yagura-${name}-reader-token".path;
      caFile = "${../../modules-private/observability/ca.pem}";
    };
in
{
  flake.modules.nixos.genkan =
    { config, ... }:
    lib.mkIf (!config.services.genkan.sites ? ${services.yagura.host}) {
      services.genkan.passthrough.yagura = {
        listener = "default";
        sni = [ services.yagura.host ];
        backend = "${kekkai.nodes.${serverHost}.ipv4}:${toString genkanRelayPort}";
        sendProxy = true;
      };
    };

  flake.modules.nixos.yagura =
    { config, ... }:
    let
      cfg = config.services.yagura;
    in
    {
      imports = [ inputs.scorsi-yagura.nixosModules.default ];

      sops.secrets = lib.genAttrs [ "yagura-masu-reader-token" "yagura-nisshi-reader-token" ] (_: {
        sopsFile = ../../secrets/hashira-01/yagura.yaml;
        restartUnits = [ "yagura.service" ];
      });

      services.yagura = {
        enable = true;
        origin = services.yagura.url;
        inherit port;
        masu = storeConfig config "masu";
        nisshi = storeConfig config "nisshi";
      };

      # The store certificates carry these private names, not their overlay addresses.
      networking.hosts = lib.mkMerge (
        map (store: {
          ${kekkai.nodes.${store.host}.ipv4} = [ store.serverName ];
        }) (lib.attrValues observability.stores)
      );

      services.genkan.sites.${services.yagura.host}.backend = "http://127.0.0.1:${toString port}";

      sekkeizu.persist.directories = [
        {
          directory = cfg.dataDir;
          user = "yagura";
          group = "yagura";
          mode = "0700";
        }
      ];
      systemd.services.yagura.unitConfig.RequiresMountsFor = [ cfg.dataDir ];
    };
}
