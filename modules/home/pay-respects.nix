# pay-respects: fixes the previous command (`f`), replaces the unmaintained thefuck.
{
  flake.modules.homeManager.pay-respects = {
    programs.pay-respects = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
