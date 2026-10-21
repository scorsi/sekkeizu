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
    { config, ... }:
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

      sops.secrets.masu-tls-key = { inherit sopsFile; };
      sops.secrets.nisshi-tls-key = { inherit sopsFile; };

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

      # Matched on the bridge address, as annai's port 53: the tailnet never reaches the stores.
      networking.firewall.extraCommands = lib.concatMapStrings (store: ''
        iptables -A nixos-fw -d ${address} -p tcp --dport ${toString store.port} -j nixos-fw-accept
      '') (lib.attrValues observability.stores);
    };
}
