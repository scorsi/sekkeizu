# The repo's only identity file: adapt before the first switch.
{
  sekkeizu.owner = {
    name = "scorsi"; # TODO: must match `whoami` on the Mac (checked by the bootstrap script)
    fullName = "scorsi";
    email = "8389441+scorsi@users.noreply.github.com";

    # FIDO2 keys (YubiKey, Thetis): SSH login to the machines AND commit signing.
    # One key per device, generated with:
    #   ssh-keygen -t ed25519-sk -O resident -C "scorsi@<device>"
    # No -O verify-required: ssh-agent (a LaunchAgent, no terminal) can't prompt
    # for the PIN at signing time ("agent refused operation"). Touch only is required;
    # the device PIN is still useful for managing resident credentials (fido2-token -L -r/-D).
    # aaguid: FIDO2 model identifier (`fido2-token -I`), used to pick the signing key
    # based on the device actually plugged in (modules/home/git.nix).
    sshKeys = [
      {
        aaguid = "d7781e5de35346aaafe23ca49f13332a";
        key = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIC8LxDRDZknAoWqM6cOAj8aY01yxL852YNMPESKgN/naAAAABHNzaDo= scorsi@yubikey";
      }
      {
        aaguid = "a3975549b191fd67b8fb017e2917fdb3";
        key = "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAICS1s1Wu3JDybJN9jDpfuojAu5HIwiGCKp3PuRbZ1MFVAAAABHNzaDo= scorsi@thetis";
      }
    ];
  };

  sekkeizu.stateVersions = {
    darwin = 6;
    homeManager = "26.05";
  };
}
