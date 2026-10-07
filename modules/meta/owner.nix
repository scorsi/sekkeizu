# Seul fichier d'identité du repo : à adapter avant le premier switch.
{
  homelab.owner = {
    name = "scorsi"; # TODO: doit correspondre à `whoami` sur le Mac (le bootstrap vérifie)
    fullName = "scorsi";
    email = "8389441+scorsi@users.noreply.github.com";

    # Clés FIDO2 (YubiKey, Thetis) : connexion SSH aux machines ET signature des commits.
    # Une clé par appareil, générée avec :
    #   ssh-keygen -t ed25519-sk -O resident -C "scorsi@<appareil>"
    # Pas de -O verify-required : ssh-agent (LaunchAgent, pas de terminal) ne peut
    # pas demander le PIN à la signature ("agent refused operation"). Juste le toucher ;
    # le PIN du device reste utile pour gérer les credentials résidents (fido2-token -L -r/-D).
    sshKeys = [
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIC8LxDRDZknAoWqM6cOAj8aY01yxL852YNMPESKgN/naAAAABHNzaDo= scorsi@yubikey"
      # TODO: "sk-ssh-ed25519@openssh.com AAAA... scorsi@thetis"
    ];
  };

  homelab.stateVersions = {
    darwin = 6;
    homeManager = "26.05";
  };
}
