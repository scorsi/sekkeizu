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

    services.openssh.enable = true;

    networking.applicationFirewall = {
      enable = true;
      enableStealthMode = true;
      allowSigned = true;
    };
  };
}
