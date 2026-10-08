# Tailscale: reach the machines from anywhere (iPhone, laptop) without opening ports.
# One-time login after the first switch: `sudo tailscale up`.
{
  flake.modules.darwin.tailscale = {
    services.tailscale.enable = true;
  };

  flake.modules.nixos.tailscale = {
    services.tailscale.enable = true;
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
    # Node identity: without it the VM would register as a new machine at every boot.
    sekkeizu.persist.directories = [ "/var/lib/tailscale" ];
  };
}
