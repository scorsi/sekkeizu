# Tailscale: reach the machines from anywhere (iPhone, laptop) without opening ports.
# One-time login after the first switch: `sudo tailscale up`.
{
  flake.modules.darwin.tailscale = {
    services.tailscale.enable = true;
  };

  flake.modules.nixos.tailscale = {
    services.tailscale.enable = true;
    networking.firewall.trustedInterfaces = [ "tailscale0" ];
  };
}
