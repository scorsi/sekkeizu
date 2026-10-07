# Boîte à outils en ligne de commande, identique sur le Mac, la VM et le futur laptop.
{
  flake.modules.homeManager.cli =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        ripgrep
        fd
        jq
        yq-go
        dust # du lisible
        duf # df lisible
        tree
        just
        curl
        wget
      ];

      programs = {
        # fish active le cache des pages man par défaut ; sur macOS home-manager ne fournit
        # pas `man` (celui du système est utilisé), le cache n'a donc aucun effet.
        man.generateCaches = false;

        eza.enable = true;
        btop.enable = true;
        bat.enable = true;
        fzf.enable = true;
        zoxide.enable = true;

        # `use flake` dans un .envrc : environnement de dev par projet, mis en cache.
        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
      };
    };
}
