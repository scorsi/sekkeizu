# fish : shell de login (niveau système) + configuration (niveau home-manager).
# Exemple type du pattern dendritique : une fonctionnalité, trois classes, un seul fichier.
{ config, ... }:
let
  owner = config.homelab.owner.name;
in
{
  flake.modules.darwin.fish =
    { pkgs, ... }:
    {
      # Installe fish au niveau système et l'ajoute à /etc/shells.
      programs.fish.enable = true;
      environment.shells = [ pkgs.fish ];

      # nix-darwin ne change pas le shell d'un compte qu'il ne gère pas :
      # on le fait à l'activation, de façon idempotente.
      system.activationScripts.postActivation.text = ''
        target=/run/current-system/sw/bin/fish
        current=$(dscl . -read /Users/${owner} UserShell | awk '{print $2}')
        if [ "$current" != "$target" ]; then
          echo "homelab: shell de ${owner} -> $target"
          dscl . -create /Users/${owner} UserShell "$target"
        fi
      '';
    };

  flake.modules.nixos.fish =
    { pkgs, ... }:
    {
      programs.fish.enable = true;
      users.users.${owner}.shell = pkgs.fish;
    };

  flake.modules.homeManager.fish =
    { pkgs, ... }:
    {
      programs.fish = {
        enable = true;

        # Plugins repris de dev-configs (ex-fisher), désormais fournis par nixpkgs.
        plugins = map (p: { inherit (p) name src; }) (
          with pkgs.fishPlugins;
          [
            fzf-fish # Ctrl+R historique, Ctrl+Alt+F fichiers, Ctrl+Alt+L git log…
            autopair # ferme automatiquement () [] {} "" ''
            sponge # retire les commandes en échec de l'historique
          ]
        );

        interactiveShellInit = ''
          set -g fish_greeting
          set -g sponge_purge_only_on_exit true
          set -g fzf_preview_dir_cmd eza --tree --color=always
          set -g fzf_diff_highlighter delta --paging=never --width=20
        '';

        shellAliases = {
          ls = "eza --color=always --icons=always -A";
          ll = "ls --long --no-filesize --no-time --no-user --no-permissions --git";
          lt = "ll --tree";
          cat = "bat";
          vim = "nvim";
          vi = "nvim";
        };

        shellAbbrs = {
          g = "git";
          gs = "git status -sb";
          zz = "z -";
          # Rebuild du Mac depuis le repo (chemin par défaut du bootstrap).
          drs = "sudo darwin-rebuild switch --flake ~/homelab";
        };
      };

      # fzf.fish fournit ses propres raccourcis : on coupe ceux de fzf pour éviter les doublons.
      programs.fzf.enableFishIntegration = false;
      # Les alias ls/ll/lt ci-dessus remplacent ceux générés par home-manager.
      programs.eza.enableFishIntegration = false;

      # Prompt : rapide, informatif (git, nix shell), thème via catppuccin.
      programs.starship.enable = true;
    };
}
