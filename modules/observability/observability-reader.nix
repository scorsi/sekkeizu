{ config, ... }:
let
  inherit (config.kiso) owner;
in
{
  # The operator's reader token on jiban, for the manual silence check (/v1/status: last receive
  # time per agent, refreshed by a successful push only):
  #   curl --cacert modules-private/observability/ca.pem \
  #     --resolve masu.internal:9472:<the stores' host kekkai address> \
  #     -H "Authorization: Bearer $(cat /run/secrets/observability-reader-token)" \
  #     https://masu.internal:9472/v1/status | jq
  # nisshi alike on nisshi.internal:9473.
  flake.modules.darwin.observability-reader =
    { config, ... }:
    {
      sops.secrets.observability-reader-token = {
        sopsFile = ../../secrets/${config.networking.hostName}/observability-reader.yaml;
        owner = owner.name;
      };
    };
}
