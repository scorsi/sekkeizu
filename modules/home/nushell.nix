# nushell : shell secondaire, à côté de fish (qui reste le shell de login).
# Utile pour manipuler des données structurées et écrire des scripts d'ops :
#   ls | where size > 1gb | sort-by modified
#   open flake.lock | get nodes | columns
#   http get https://api.github.com/... | select name stars
# On le lance avec `nu`, depuis fish ou en SSH.
{
  flake.modules.homeManager.nushell = {
    programs.nushell = {
      enable = true;
      settings = {
        show_banner = false;
        history.file_format = "sqlite"; # historique interrogeable comme une table
      };
      shellAliases = {
        g = "git";
        drs = "sudo darwin-rebuild switch --flake ~/homelab";
      };
    };

    # starship, zoxide, direnv… s'intègrent automatiquement à nushell quand il est activé.
    # carapace fournit à nushell les complétions de centaines de commandes (git, nix, docker…).
    programs.carapace = {
      enable = true;
      enableFishIntegration = false; # fish a déjà ses propres complétions
    };
  };
}
