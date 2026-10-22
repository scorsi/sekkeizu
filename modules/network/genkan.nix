# genkan, the lab's reverse proxy (docs/migration.md, step 4): the only thing on the web port.
# Features add their own sites (`services.genkan.sites.<host>`); this file runs genkan with
# hanko's `*.uchi` wildcard (hanko.nix: group genkan, reloads genkan.service after a renewal;
# genkan's module orders it after hanko).
#
# `:443`, every address (the module's default listener): clients come over kekkai, where kekkai's
# allowInbound is the only filter (kekkai0 is trusted), and ishizue's own runner over loopback
# (forgejo-runner.nix). The bridge address keeps the web port closed (no firewall opening).
# No port 80: genkan's redirect listener is v1.1.
{ config, inputs, ... }:
let
  inherit (config.sekkeizu) domain;
in
{
  flake.modules.nixos.genkan = {
    imports = [ inputs.scorsi-genkan.nixosModules.default ];

    services.genkan = {
      enable = true;
      certificates.uchi = {
        hosts = [ "*.uchi.${domain}" ];
        cert = "/var/lib/hanko/uchi/fullchain.pem";
        key = "/var/lib/hanko/uchi/key.pem";
      };
      # Scraped by the local hikyaku only (masu metric convention: loopback).
      metrics.listen = "127.0.0.1:9476";
    };
  };
}
