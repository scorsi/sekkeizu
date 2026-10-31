# The observability base (docs/observability.md): where masu and nisshi listen, the names their
# certificates carry, and the SHA-256 of each host's hikyaku token and of the operator's reader
# tokens, one per store. The hashes are not secrets (masu ADR 0007, nisshi ADR 0008); the tokens
# are in secrets/<host>/hikyaku.yaml and secrets/jiban/<store>-reader.yaml.
#
# Values in modules-private/meta/observability.nix, certificates in modules-private/observability/.
#
# Certificates: ca.pem signed masu.pem and nisshi.pem, valid until 2036-10-18, and was then
# destroyed. Replacing a leaf (lost or compromised key) needs no flag day, with an overlapping CA:
# a new CA; every agent's caFile holds both CAs (PEMs concatenated) and is deployed; the new CA signs new leaves
# for both stores, deployed with their keys; once every agent pushes again, the old CA leaves
# caFile. No reminder before expiry: hansho will alert on it. Replaced by hanko certificates
# later (masu ADR 0007, nisshi ADR 0008).
#
# Backups: azukari's daily run on the stores' host exports their closed days, the open day never
# (exports masu-days and nisshi-days, backup/azukari.nix); the store keeps them on that host's DAS.
#
# Trust boundaries: an agent's token cannot read /v1/status, the reader token cannot push. Root
# on the stores' host reaches both stores and their export.
#
# /v1/status shows an agent's state as of its last successful push (nisshi keeps it in memory
# only, lost at restart): read `paused` and the rest against the last receive time, never as a
# live probe of the agent.
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
            readerTokenHashes = mkOption {
              type = types.listOf (types.strMatching "[0-9a-f]{64}");
              default = [ ];
              description = "Hex SHA-256 of the operator's tokens for this store, role `reader`: `/v1/status` only, never a push.";
            };
          };
        }
      );
    };
    agents = mkOption {
      description = "Each host running hikyaku: its spool limit (it reaches the stores through genkan, hikyaku.nix).";
      type = types.attrsOf (
        types.submodule {
          options.spoolLimit = mkOption { type = types.ints.positive; };
        }
      );
    };
    tokenHashes = mkOption {
      type = types.attrsOf (types.strMatching "[0-9a-f]{64}");
      description = "Hex SHA-256 of each host's hikyaku token, by host name (= the node name).";
    };
  };
}
