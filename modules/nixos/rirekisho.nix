# The résumé (rirekisho repository): genkan serves `dir` as static files, on the overlay as
# `rirekisho.uchi` and publicly under `rirekisho.public` (endpoints.nix) through torii-cdg's genkan
# (genkan.nix), with a certificate of their own from hanko. Its writer was the Forgejo Actions runner,
# removed: the directory waits for kajiba's CI to publish into it.
{ config, lib, ... }:
let
  inherit (config.sekkeizu) genkanRelayPort kekkai services;
  rirekisho = services.rirekisho;
  dir = "/var/lib/rirekisho";
in
{
  # The files exist on hashira-02 only: another genkan host forwards the
  # overlay name raw by SNI to hashira-02's genkan `relay` listener, which terminates it (genkan ADR 0012).
  flake.modules.nixos.genkan =
    { config, ... }:
    lib.mkIf (!config.services.genkan.sites ? ${rirekisho.host}) {
      services.genkan.passthrough.rirekisho = {
        listener = "default";
        sni = [ rirekisho.host ];
        backend = "${kekkai.nodes.hashira-02.ipv4}:${toString genkanRelayPort}";
        # The owner host's `relay` listener logs the client, not this genkan (genkan.nix).
        sendProxy = true;
      };
    };

  flake.modules.nixos.rirekisho = {
    sekkeizu.persist.directories = [
      {
        directory = dir;
        mode = "0755";
      }
    ];

    services.hanko-node.certificates.rirekisho-public = {
      hosts = rirekisho.public;
      reload = [ "genkan.service" ];
      group = "genkan";
    };

    services.genkan = {
      certificates.rirekisho-public = {
        hosts = rirekisho.public;
        cert = "/var/lib/hanko/rirekisho-public/fullchain.pem";
        key = "/var/lib/hanko/rirekisho-public/key.pem";
      };
      sites = {
        ${rirekisho.host}.root = dir;
      }
      // lib.genAttrs rirekisho.public (_: {
        root = dir;
        # Named, the PROXY listener serves them (genkan ADR 0013); `uchi` names stay off it.
        listeners = [
          "default"
          "edge"
        ];
      });
    };
  };
}
