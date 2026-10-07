# nushell: secondary shell, alongside fish (which stays the login shell).
# Useful for structured data and ops scripts:
#   ls | where size > 1gb | sort-by modified
#   open flake.lock | get nodes | columns
#   http get https://api.github.com/... | select name stars
# Launched with `nu`, from fish or over SSH.
{
  flake.modules.homeManager.nushell = {
    programs.nushell = {
      enable = true;
      settings = {
        show_banner = false;
        history.file_format = "sqlite"; # history queryable like a table
      };
      shellAliases = {
        g = "git";
        drs = "sudo darwin-rebuild switch --flake ~/sekkeizu";
      };
    };

    # starship, zoxide, direnv… integrate automatically with nushell once enabled.
    # carapace gives nushell completions for hundreds of commands (git, nix, docker…).
    programs.carapace = {
      enable = true;
      enableFishIntegration = false; # fish already has its own completions
    };
  };
}
