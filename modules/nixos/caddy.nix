# Caddy: the only thing listening on the web ports. Features add their own virtual hosts
# (`services.caddy.virtualHosts.<url>`); this file only runs Caddy and wires its certificates.
#
# HTTPS certificates come from Tailscale (Let's Encrypt behind it): for a *.ts.net name Caddy asks
# tailscaled by itself, provided tailscaled lets the caddy user ask. Needs "HTTPS Certificates"
# enabled once in the Tailscale admin console (DNS tab).
{
  flake.modules.nixos.caddy = {
    services.caddy.enable = true;
    services.tailscale.permitCertUid = "caddy";

    # Without it, the VM would ask for its certificates again at every boot.
    sekkeizu.persist.directories = [
      {
        directory = "/var/lib/caddy";
        user = "caddy";
        group = "caddy";
        mode = "0700";
      }
    ];
  };
}
