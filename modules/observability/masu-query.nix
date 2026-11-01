# The query listener reuses Masu's TLS identity on a separate port: the existing genkan SNI
# stays attached to ingestion. Only the operator's Jiban reaches it directly over kekkai.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) kekkai observability;
  store = observability.stores.masu;
  address = kekkai.nodes.${store.host}.ipv4;
  port = 9482;
  origin = "https://${store.serverName}:${toString port}";
  caFile = "${../../modules-private/observability/ca.pem}";
in
{
  flake.modules.nixos.masu-query =
    { config, ... }:
    {
      services.masu.query = {
        enable = true;
        listen = [ "${address}:${toString port}" ];
        dataDir = config.services.masu.dataDir;
        tls = config.services.masu.tls;
        tokens = lib.genAttrs store.readerTokenHashes (_: "reader");
      };

      sops.secrets.masu-tls-key.restartUnits = [ "masu-query.service" ];
      systemd.services.masu-query = {
        after = [ "systemd-sysctl.service" ];
        unitConfig.RequiresMountsFor = [ config.services.masu.query.dataDir ];
        serviceConfig = {
          IPAddressDeny = "any";
          IPAddressAllow = [
            "localhost"
            kekkai.nodes.jiban.ipv4
            kekkai.nodes.jiban.ipv6
          ];
        };
      };
      networking.firewall.extraCommands = lib.concatMapStrings (iface: ''
        iptables -I nixos-fw -i ${iface} -p tcp --dport ${toString port} -j nixos-fw-refuse
      '') (lib.subtractLists [ "lo" "kekkai0" ] config.networking.firewall.trustedInterfaces);
    };

  flake.modules.darwin.masu-query-client =
    { config, ... }:
    {
      # Darwin has no networking.hosts option; keep every unmanaged hosts entry intact.
      system.activationScripts.postActivation.text = lib.mkAfter ''
        /usr/bin/sed -i "" '/ # sekkeizu-masu-query$/d' /etc/hosts
        if [ -n "$(/usr/bin/tail -c 1 /etc/hosts)" ]; then
          printf '\n' >> /etc/hosts
        fi
        printf '%s\n' '${address} ${store.serverName} # sekkeizu-masu-query' >> /etc/hosts
        /usr/bin/dscacheutil -flushcache
      '';
      environment.variables = {
        MASU_QUERY_URL = origin;
        MASU_TOKEN_FILE = config.sops.secrets.masu-reader-token.path;
        MASU_CA_FILE = caFile;
      };
    };

  flake.modules.homeManager.masu-cli =
    { pkgs, ... }:
    {
      home.packages = [ inputs.scorsi-masu.packages.${pkgs.stdenv.hostPlatform.system}.masu ];
    };
}
