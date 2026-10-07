# Seul fichier d'identité du repo : à adapter avant le premier switch.
{
  homelab.owner = {
    name = "scorsi"; # TODO: doit correspondre à `whoami` sur le Mac (le bootstrap vérifie)
    fullName = "scorsi";
    email = "8389441+scorsi@users.noreply.github.com";

    # Clés FIDO2 (YubiKey, Thetis) : connexion SSH aux machines ET signature des commits.
    # Une clé par appareil, générée avec :
    #   ssh-keygen -t ed25519-sk -O resident -O verify-required -C "scorsi@<appareil>"
    sshKeys = [
      # TODO: "sk-ssh-ed25519@openssh.com AAAA... scorsi@yubikey"
      # TODO: "sk-ssh-ed25519@openssh.com AAAA... scorsi@thetis"
    ];
  };

  homelab.stateVersions = {
    darwin = 6;
    homeManager = "26.05";
  };
}
