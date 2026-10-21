# annai, the lab's DNS (docs/migration.md, step 1): a `uchi` instance on ishizue, authoritative for
# uchi.<domain> and forwarding everything else, reached by jiban over vfkit's NAT bridge until
# kekkai exists. The zone is generated from kekkai's node allocation and the services of
# services.nix (annai ADR 0005); kekkai addresses answer before kekkai runs, on purpose.
#
# nixos.annai: the server. darwin.annai: points the Mac's resolver at it — ALL its DNS, so jiban
# resolves nothing but *.ts.net (Tailscale's /etc/resolver/ts.net) and *.local while ishizue is down.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu)
    domain
    bridgeAddresses
    kekkai
    services
    ;
  zone = "uchi.${domain}.";
  # The host every client resolves through (one uchi instance).
  uchiAddress = bridgeAddresses.ishizue;

  nodeNames = lib.mapAttrs' (
    name: node:
    lib.nameValuePair "${name}.kekkai" {
      a = [ node.ipv4 ];
      aaaa = [ node.ipv6 ];
    }
  ) kekkai.nodes;

  # <service>.uchi → the node its endpoint names (first label of `host`), when that is a kekkai node.
  serviceNames = lib.concatMapAttrs (
    name: svc:
    let
      node = lib.head (lib.splitString "." svc.host);
    in
    lib.optionalAttrs (kekkai.nodes ? ${node}) { ${name}.cname = "${node}.kekkai"; }
  ) services;
in
{
  flake.modules.nixos.annai =
    { config, ... }:
    let
      address = bridgeAddresses.${config.networking.hostName};
    in
    {
      imports = [ inputs.scorsi-annai.nixosModules.default ];

      services.annai = {
        enable = true;
        mode = "uchi";
        # The bridge only: not the tailnet, not kekkai (not there yet). Upstreams: annai's (Quad9).
        listen = [ "${address}:53" ];
        # Scraped by the local hikyaku only (masu metric convention: loopback).
        metrics.listen = "127.0.0.1:9153";
        zones.${zone} = {
          ttl = 300;
          serial = inputs.self.lastModified;
          soa = {
            mname = "annai.${zone}";
            rname = "hostmaster.${domain}.";
            refresh = 3600;
            retry = 600;
            expire = 604800;
            minimum = 300;
          };
          names = {
            "@".ns = [ "annai.${zone}" ];
            # Where annai will listen once kekkai runs; an NS target cannot be a CNAME.
            annai = {
              a = [ kekkai.nodes.ishizue.ipv4 ];
              aaaa = [ kekkai.nodes.ishizue.ipv6 ];
            };
          }
          // nodeNames
          // serviceNames;
        };
        reverse = {
          inherit zone;
          prefixes = [
            kekkai.ipv4Prefix
            kekkai.ipv6Prefix
          ];
        };
      };

      # The listen address comes from DHCP: binding before the lease fails.
      systemd.services.annai = {
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };

      # Matched on the bridge address rather than the interface, whose name the repo never fixes.
      networking.firewall.extraCommands =
        lib.concatMapStrings
          (proto: ''
            iptables -A nixos-fw -d ${address} -p ${proto} --dport 53 -j nixos-fw-accept
          '')
          [
            "udp"
            "tcp"
          ];

      # ishizue itself keeps systemd-resolved, but asks the upstreams directly instead of macOS's
      # NAT DNS proxy, which follows jiban's resolver, i.e. annai: a broken annai must not take
      # away the DNS that rebuilding ishizue needs. Its own resolver moves to annai with kekkai
      # (annai's nixosModules.resolver on kekkai0).
      systemd.network.networks."10-uplink" = {
        dhcpV4Config.UseDNS = false;
        networkConfig.DNS = config.services.annai.forwarding.upstreams;
      };
    };

  flake.modules.darwin.annai = {
    imports = [ inputs.scorsi-annai.darwinModules.resolver ];

    services.annai.resolver = {
      enable = true;
      address = uchiAddress;
      domain = "uchi.${domain}";
    };
    # The Mac's real services (`networksetup -listallnetworkservices`); the VPN keeps its own DNS.
    networking.knownNetworkServices = [
      "Ethernet"
      "Wi-Fi"
    ];
    # TODO(owner): temporary workaround, must not persist; it departs from annai ADR 0002 (scoped
    # and fallback queries go straight to Quad9). macOS also resolves per interface (Private Relay,
    # NAT64 probes): those queries are scoped to en1 and cannot reach the bridge-only uchi address;
    # unanswered, they make Wi-Fi "DNS failure recovery" reassociate every ~20 min, which cuts
    # ishizue's NAT uplink. Remove once uchi is reachable on that path (bridged ishizue or kekkai).
    networking.dns = lib.mkAfter [ "9.9.9.9" ];
  };
}
