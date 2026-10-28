# SSH to the jailbroken Kindles: KOReader's dropbear (Network → SSH server, key-only login), up only
# while KOReader runs. A dedicated passphrase-less key, since dropbear may not take FIDO2 keys.
{ config, ... }:
{
  flake.modules.homeManager.kindle = {
    programs.ssh.settings.kindle-pw3 = {
      HostName = config.sekkeizu.lanAddresses.kindle-pw3;
      Port = 2222;
      User = "root";
      IdentityFile = "~/.ssh/kindle_ed25519";
      IdentitiesOnly = true;
    };
  };
}
