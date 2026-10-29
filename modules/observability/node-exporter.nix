# node_exporter, the host's metrics until mihari exists: on loopback only, scraped by the local
# hikyaku (hikyaku.nix adds it to its targets wherever it is on).
let
  exporter = {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
  };
in
{
  flake.modules.nixos.node-exporter = exporter;
  flake.modules.darwin.node-exporter = exporter;
}
