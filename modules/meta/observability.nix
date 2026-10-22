# The observability base (docs/observability.md): where masu and nisshi listen, the names their
# certificates carry, and the SHA-256 of each host's hikyaku token and of the operator's reader
# token. The hashes are not secrets (masu ADR 0007, nisshi ADR 0008); the tokens are in
# secrets/<host>/hikyaku.yaml and secrets/jiban/observability-reader.yaml.
#
# Values in modules-private/meta/observability.nix, certificates in modules-private/observability/.
#
# Certificates: ca.pem signed masu.pem and nisshi.pem, valid until 2036-10-18, and was then
# destroyed. Replacing a leaf (lost or compromised key) needs no flag day, with an overlapping CA:
# a new CA; every agent's caFile holds both CAs (PEMs concatenated) and is deployed; the new CA signs new leaves
# for both stores, deployed with their keys; once every agent pushes again, the old CA leaves
# caFile. No reminder before expiry: hanshou will alert on it. Replaced by hanko certificates
# later (masu ADR 0007, nisshi ADR 0008).
#
# RPO: 12 h on jiban (ishizue exports at 04:45 and 16:45, the open day as a committed prefix;
# jiban pulls 30 min later), 24 h off site (restic, daily). backup/pull.nix, observability/stores.nix.
#
# Trust boundaries: an agent's token cannot read /v1/status, the reader token cannot push. Root
# on ishizue reaches both stores and their export. Root on jiban (hikyaku runs as root there, the
# pull as the owner) reaches the hypervisor, every pulled backup and the Mac's secrets: a
# dedicated pull account is future work (backup/pull.nix).
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
    readerTokenHashes = mkOption {
      type = types.listOf (types.strMatching "[0-9a-f]{64}");
      default = [ ];
      description = "Hex SHA-256 of the operator's tokens, role `reader` in both stores: `/v1/status` only, never a push.";
    };
  };
}
