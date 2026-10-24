# genkan, the lab's reverse proxy (docs/migration.md, step 4): the only thing on the web port.
# Features add their own sites (`services.genkan.sites.<host>`); this file runs genkan with
# hanko's `*.uchi` wildcard (hanko.nix: group genkan, reloads genkan.service after a renewal;
# genkan's module orders it after hanko).
#
# ishizue (`genkan`): `:443` on every address, the `default` listener: clients come over kekkai,
# where kekkai's allowInbound is the only filter (kekkai0 is trusted), and ishizue's own runner over
# loopback (forgejo-runner.nix). The bridge address keeps the web port closed (no firewall
# opening). The `edge` listener takes what torii-cdg forwards, behind a PROXY v2 header: only the
# sites that name it are served there (genkan ADR 0013), the ones with public names (services.nix).
#
# torii-cdg (`genkan-edge`): public `:443`, the public names forwarded raw by SNI to ishizue's
# `edge` listener over kekkai; no TLS termination, so no certificate. Anything else is closed.
# No port 80: genkan's redirect listener is v1.1.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.sekkeizu) domain kekkai services;
  # Also opened from the gate in kekkai.nix's allowInbound.
  edge = "${kekkai.nodes.ishizue.ipv4}:8443";
  # Scraped by the local hikyaku only (masu metric convention: loopback).
  metrics = "127.0.0.1:9476";
in
{
  flake.modules.nixos.genkan = {
    imports = [ inputs.scorsi-genkan.nixosModules.default ];

    services.genkan = {
      enable = true;
      listeners = {
        default.address = ":443";
        edge = {
          address = edge;
          acceptProxy = true;
          trustedSources = [ "${kekkai.nodes.torii-cdg.ipv4}/32" ];
        };
      };
      certificates.uchi = {
        hosts = [ "*.uchi.${domain}" ];
        cert = "/var/lib/hanko/uchi/fullchain.pem";
        key = "/var/lib/hanko/uchi/key.pem";
      };
      metrics.listen = metrics;
    };

    # kekkai0 is a non-persistent TUN: binding its address must not depend on kekkai-node being up
    # (observability/stores.nix sets the same for masu and nisshi; mkDefault lets both define it).
    boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = lib.mkDefault 1;
  };

  flake.modules.nixos.genkan-edge = {
    imports = [ inputs.scorsi-genkan.nixosModules.default ];

    services.genkan = {
      enable = true;
      # The module's `default` listener, `:443` on both address families.
      passthrough.ishizue = {
        listener = "default";
        sni = lib.concatMap (s: s.public) (lib.attrValues services);
        backend = edge;
        sendProxy = true;
      };
      metrics.listen = metrics;
    };

    # Vultr's firewall (infra/stacks/torii) opens the same port.
    networking.firewall.allowedTCPPorts = [ 443 ];
  };
}
