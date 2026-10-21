# The observability base (docs/observability.md): where masu and nisshi listen, the names their
# certificates carry, and the SHA-256 of each host's hikyaku token. The hashes are not secrets
# (masu ADR 0007, nisshi ADR 0008); the tokens are in secrets/<host>/hikyaku.yaml.
#
# Values in modules-private/meta/observability.nix, certificates in modules-private/observability/.
#
# Certificates: ca.pem signed masu.pem and nisshi.pem (10 years, from
# 2026-10-21) and was then destroyed: replacing them means a new CA, both leaves and every agent's
# caFile at once. Replaced by hanko certificates later (masu ADR 0007, nisshi ADR 0008).
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.sekkeizu.observability = {
    stores = mkOption {
      description = "The two stores, by name: host they run on, ingestion port, and the name their certificate carries.";
      type = types.attrsOf (
        types.submodule {
          options = {
            host = mkOption { type = types.str; };
            port = mkOption { type = types.port; };
            serverName = mkOption { type = types.str; };
          };
        }
      );
    };
    agents = mkOption {
      description = "Each host running hikyaku: its spool limit, and the address it reaches the stores' host on.";
      type = types.attrsOf (
        types.submodule {
          options = {
            spoolLimit = mkOption { type = types.ints.positive; };
            storeAddress = mkOption { type = types.str; };
          };
        }
      );
    };
    tokenHashes = mkOption {
      type = types.attrsOf (types.strMatching "[0-9a-f]{64}");
      description = "Hex SHA-256 of each host's hikyaku token, by host name (= the node name).";
    };
  };
}
