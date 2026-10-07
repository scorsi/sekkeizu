# Client SSH + agent, compatibles clés FIDO2 (ed25519-sk).
#
# macOS fournit son propre ssh/ssh-agent, compilés SANS support des clés matérielles :
# on les remplace par ceux de nixpkgs. L'agent tourne en LaunchAgent (macOS) ou en
# service systemd utilisateur (NixOS). Une session SSH entrante avec un agent transféré
# (`ssh -A`) garde l'agent du laptop : home-manager ne l'écrase pas.
{
  flake.modules.homeManager.ssh =
    { pkgs, ... }:
    {
      services.ssh-agent = {
        enable = true;
        package = pkgs.openssh;
      };

      programs.ssh = {
        enable = true;
        package = pkgs.openssh;
        enableDefaultConfig = false;
        # Directives OpenSSH telles quelles (ssh_config(5)), un bloc par motif d'hôte.
        settings = {
          "*" = {
            # La clé utilisée (handle de la clé matérielle) est ajoutée à l'agent :
            # git peut ensuite signer avec, et `ssh -A` la transfère.
            AddKeysToAgent = "yes";
          };
          # Machines de sekkeizu : agent transféré pour signer les commits depuis le serveur.
          "jiban jiban.local ishizue" = {
            ForwardAgent = true;
          };
        };
      };
    };
}
