# The lab's network addressing, beyond the services of services.nix: the domain the internal zone
# hangs from, the VMs' addresses on vfkit's NAT bridge, and kekkai's overlay allocation. Values in
# modules-private/meta/ (endpoints.nix, kekkai.nix).
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
        IPv4 address of each VM on vfkit's NAT bridge, by host name. Fixed by the VM's MAC
        (`sekkeizu.vms.<name>.mac`) in macOS's DHCP leases (/var/db/dhcpd_leases).
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
      nodes = mkOption {
        description = "kekkai nodes by name: one /32 and one /128 each, inside the prefixes above.";
        default = { };
        type = types.attrsOf (
          types.submodule {
            options = {
              ipv4 = mkOption { type = types.str; };
              ipv6 = mkOption { type = types.str; };
            };
          }
        );
      };
    };
  };
}
