# Headless server behaviour: never sleeps, restarts by itself, Remote Login on, firewall up.
{
  flake.modules.darwin.server = {
    power = {
      sleep = {
        computer = "never";
        display = "never";
        harddisk = "never";
      };
      restartAfterPowerFailure = true;
      restartAfterFreeze = true;
    };

    services.openssh = {
      enable = true;
      # Apple's 100-macos.conf sets none of these, and sshd keeps the first value it reads,
      # so 100-nix-darwin.conf wins (to re-check with `sudo sshd -T` after a switch).
      extraConfig = ''
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PermitRootLogin no
        AuthenticationMethods publickey
      '';
    };

    networking.applicationFirewall = {
      enable = true;
      enableStealthMode = true;
      allowSigned = true;
    };
  };
}
