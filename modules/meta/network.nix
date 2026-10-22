# The lab's network addressing, beyond the services of services.nix: the domain the internal zone
# hangs from, the public hosts' addresses, the VMs' addresses on vfkit's NAT bridge, and kekkai's
# overlay allocation. Values in modules-private/meta/ (endpoints.nix, public.nix, kekkai.nix).
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.sekkeizu = {
    domain = mkOption {
      type = types.str;
      description = "The owner's primary domain; the internal zone is `uchi.<domain>` (annai ADR 0005).";
    };

    bridgeAddresses = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = ''
        IPv4 address of each VM on vfkit's NAT bridge, by host name. Reserved for the VM's MAC
        (`sekkeizu.vms.<name>.mac`) in macOS's /etc/bootptab by vfkit-host; independent of DHCP leases.
      '';
    };

    publicAddresses = mkOption {
      default = { };
      description = "Public IPv4 and IPv6 of each internet-facing host, by host name: infra/stacks/torii's outputs.";
      type = types.attrsOf (
        types.submodule {
          options = {
            ipv4 = mkOption { type = types.str; };
            ipv6 = mkOption { type = types.str; };
          };
        }
      );
    };

    publicZones = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = { };
      description = ''
        Public records by apex zone (no final dot), as annai's `names` (annai ADR 0003). The same
        records as infra/stacks/dns at Porkbun until the NS switch; SOA, NS, glue and CAA come from
        the annai-soto feature.
      '';
    };

    acmeAccounts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        ACME account URLs allowed to issue for the public zones (RFC 8657 `accounturi` in their CAA),
        one per hanko host (hanko ADR 0003). Set by hand from hanko's `acme-account` log event, never
        automated: pinning stays an out-of-band decision. Empty: CAA allows any Let's Encrypt account.
      '';
    };

    kekkai = {
      ipv4Prefix = mkOption {
        type = types.str;
        description = "kekkai's IPv4 range, inside 10.0.0.0/8 (kekkai ADR 0010); ends on an octet boundary for its reverse zone.";
      };
      ipv6Prefix = mkOption {
        type = types.str;
        description = "kekkai's ULA /48 (RFC 4193, kekkai ADR 0010).";
      };
      lighthousePublicKey = mkOption {
        type = types.str;
        description = "The lighthouse's own public key (kekkai ADR 0017), distinct from its host's node key.";
      };
      relayPublicKey = mkOption {
        type = types.str;
        description = "The relay's own public key (kekkai ADR 0017), distinct from its host's node key.";
      };
      nodes = mkOption {
        description = "kekkai nodes by name: one /32 and one /128 each, inside the prefixes above.";
        default = { };
        type = types.attrsOf (
          types.submodule {
            options = {
              ipv4 = mkOption { type = types.str; };
              ipv6 = mkOption { type = types.str; };
              publicKey = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "The node's public key (`kekkai pubkey`); null until its key exists.";
              };
            };
          }
        );
      };
    };
  };
}
