# genkan, the lab's reverse proxy (docs/migration.md, step 4): the only thing on the web port.
# Features add their own sites (`services.genkan.sites.<host>`); this file runs genkan with
# hanko's `*.uchi` wildcard (hanko.nix: group genkan, reloads genkan.service after a renewal;
# genkan's module orders it after hanko).
#
# hashira-01 and hashira-02 (`genkan`, both addresses in annai): the same sites on each, each host
# with its own wildcard from its own hanko. `:443` on every address, the `default` listener: clients
# come over kekkai, where kekkai's allowInbound is the only filter (kekkai0 is trusted). The LAN
# keeps the web port closed (no firewall opening). Forgejo's name points here for both its ports:
# the web site goes to Forgejo's HTTP port, and the `forgejo-ssh` listener (`:2222`, mode tcp: a
# passthrough without SNI, genkan ADR 0012) forwards git over SSH raw to Forgejo's own SSH server,
# both over kekkai.
# hashira-02 alone (`edgeHost`) has the `edge` listener: it takes what torii-cdg forwards, behind a
# PROXY v2 header, and serves only the sites that name it (genkan ADR 0013), the ones with public
# names (services.nix). torii's tcp route has one backend: failing over to hashira-01 there waits
# for a genkan feature.
#
# torii-cdg (`genkan-edge`): public `:443`, the public names forwarded raw by SNI to the `edge`
# listener over kekkai; no TLS termination, so no certificate. Anything else is closed.
# Public `:80` is genkan's redirect listener (v1.1): 301 to https://, same host and path, answered on
# torii itself; port 80 never crosses kekkai.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) domain kekkai services;
  # Also opened from the gate in kekkai.nix's allowInbound.
  edgeHost = "hashira-02";
  edge = "${kekkai.nodes.${edgeHost}.ipv4}:8443";
  # Forgejo's node; its HTTP and SSH ports are opened to genkan's node in kekkai.nix.
  forgejo = kekkai.nodes.ishizue.ipv4;
  # Scraped by the local hikyaku only (masu metric convention: loopback).
  metrics = "127.0.0.1:9476";
in
{
  sekkeizu.genkanHosts = [
    "hashira-01"
    edgeHost
  ];

  flake.modules.nixos.genkan =
    { config, ... }:
    {
      imports = [ inputs.scorsi-genkan.nixosModules.default ];

      services.genkan = {
        enable = true;
        listeners = {
          default.address = ":443";
          forgejo-ssh.address = ":${toString services.forgejo-ssh.port}";
        }
        // lib.optionalAttrs (config.networking.hostName == edgeHost) {
          edge = {
            address = edge;
            acceptProxy = true;
            trustedSources = [ "${kekkai.nodes.torii-cdg.ipv4}/32" ];
          };
        };
        sites.${services.forgejo.host} = {
          backend = "http://${forgejo}:3000";
          # The runners poll FetchTask every ~2 s each: 96 % of genkan's request lines. Successful
          # polls are counted in metrics, not logged; failed ones and every other call still are (genkan ADR 0011).
          quietPaths = [ "/api/actions/runner.v1.RunnerService/FetchTask" ];
        };
        passthrough.forgejo-ssh = {
          listener = "forgejo-ssh";
          backend = "${forgejo}:${toString services.forgejo-ssh.port}";
          # Forgejo's SSH server expects it (SSH_SERVER_USE_PROXY_PROTOCOL): its logs show the client.
          sendProxy = true;
        };
        certificates.uchi = {
          hosts = [ "*.uchi.${domain}" ];
          cert = "/var/lib/hanko/uchi/fullchain.pem";
          key = "/var/lib/hanko/uchi/key.pem";
        };
        metrics.listen = metrics;
      };
    };

  flake.modules.nixos.genkan-edge = {
    imports = [ inputs.scorsi-genkan.nixosModules.default ];

    services.genkan = {
      enable = true;
      # The module's `default` listener, `:443` on both address families.
      passthrough.web = {
        listener = "default";
        sni = lib.concatMap (s: s.public) (lib.attrValues services);
        backend = edge;
        sendProxy = true;
      };
      # `:80`, both address families. Outside `listeners`: the `default` listener stays.
      httpRedirect.enable = true;
      metrics.listen = metrics;
    };

    # Vultr's firewall (infra/stacks/torii) opens the same ports.
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
