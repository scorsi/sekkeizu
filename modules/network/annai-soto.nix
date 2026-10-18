# annai `soto` (docs/migration.md, step 2): the public authoritative nameservers ns1 and ns2 of the
# apex zones, both on this one host until a second torii exists (accepted in migration.md). The
# records are `sekkeizu.publicZones`, the dns stack's (infra/stacks/dns) at Porkbun; this adds SOA,
# NS, the glue and CAA. Unsigned: no DNSSEC, never a DS at the registry (annai ADR 0009).
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) domain publicAddresses publicZones;
in
{
  flake.modules.nixos.annai-soto =
    { config, ... }:
    let
      address = publicAddresses.${config.networking.hostName};
      nameservers = [
        "ns1.${domain}."
        "ns2.${domain}."
      ];
      glue = {
        a = [ address.ipv4 ];
        aaaa = [ address.ipv6 ];
      };
      # RFC 8657: only DNS-01 (hanko), the only issuance path. TODO(owner): add
      # `; accounturi=<hanko's ACME account URL>` to both once hanko has created its account.
      caaValue = "letsencrypt.org; validationmethods=dns-01";

      zone = apex: records: {
        # Porkbun's TTL for every record of the dns stack: the switch changes no cache behaviour.
        ttl = 600;
        serial = inputs.self.lastModified;
        soa = {
          mname = "ns1.${domain}.";
          rname = "hostmaster.${apex}.";
          refresh = 3600;
          retry = 600;
          expire = 604800;
          minimum = 300;
        };
        names =
          records
          // {
            "@" = (records."@" or { }) // {
              ns = nameservers;
              caa = [
                {
                  flags = 0;
                  tag = "issue";
                  value = caaValue;
                }
                {
                  flags = 0;
                  tag = "issuewild";
                  value = caaValue;
                }
              ];
            };
          }
          # In-bailiwick NS need glue; the other apexes point at them out of bailiwick (annai ADR 0009).
          // lib.optionalAttrs (apex == domain) {
            ns1 = glue;
            ns2 = glue;
          };
      };
    in
    {
      imports = [ inputs.scorsi-annai.nixosModules.default ];

      sops.secrets.hanko-tsig.sopsFile = ../../secrets/hanko/tsig.yaml;

      services.annai = {
        enable = true;
        mode = "soto";
        listen = [
          "${address.ipv4}:53"
          "[${address.ipv6}]:53"
        ];
        zones = lib.mapAttrs' (apex: records: lib.nameValuePair "${apex}." (zone apex records)) publicZones;
        update.keys.hanko.secretFile = config.sops.secrets.hanko-tsig.path;
      };

      # The addresses come from DHCP and router advertisements: binding before them fails.
      systemd.services.annai = {
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };

      # Vultr's firewall (infra/stacks/torii) opens the same ports.
      networking.firewall = {
        allowedUDPPorts = [ 53 ];
        allowedTCPPorts = [ 53 ];
      };
    };
}
