# The repo's only identity file: adapt before the first switch. The options are kiso's
# (github:scorsi/kiso), the values are this repo's.
{
  kiso.owner = {
    name = "scorsi"; # TODO: must match `whoami` on the Mac (checked by the bootstrap script)
    fullName = "scorsi";
    email = "8389441+scorsi@users.noreply.github.com";

    # sshKeys, in private/keys.nix (encrypted, see .gitattributes): FIDO2 keys (YubiKey, Thetis),
    # SSH login to the machines AND commit signing. One key per device, generated with:
    #   ssh-keygen -t ed25519-sk -O resident -C "scorsi@<device>"
    # No -O verify-required: ssh-agent (a LaunchAgent, no terminal) can't prompt
    # for the PIN at signing time ("agent refused operation"). Touch only is required;
    # the device PIN is still useful for managing resident credentials (fido2-token -L -r/-D).
    # aaguid: FIDO2 model identifier (`fido2-token -I`), used to pick the signing key
    # based on the device actually plugged in (modules/home/git.nix).
  };

  # Where the bootstrap script clones this repo (`drs` rebuilds from there).
  kiso.configDir = "repositories/sekkeizu";

  kiso.stateVersions = {
    darwin = 6;
    nixos = "26.05";
    homeManager = "26.05";
  };
}
