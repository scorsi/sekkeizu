# Yagura reads the stores with dedicated reader identities; genkan holds the browser-facing TLS.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu)
    kekkai
    observability
    services
    ;
  serverHost = "hashira-01";
  address = kekkai.nodes.${serverHost}.ipv4;
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
  # Browsers can reuse a wildcard HTTP/2 connection whose original SNI named another site.
  flake.modules.nixos.genkan.services.genkan.sites.${services.yagura.host}.backend =
    "http://${address}:${toString port}";

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
        host = address;
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

      sekkeizu.persist.directories = [
        {
          directory = cfg.dataDir;
          user = "yagura";
          group = "yagura";
          mode = "0700";
        }
      ];
      systemd.services.yagura = {
        # The existing kekkai sysctl permits binding its address before the interface is ready.
        after = [ "systemd-sysctl.service" ];
        unitConfig.RequiresMountsFor = [ cfg.dataDir ];
      };
    };
}
