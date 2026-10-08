# Catppuccin Mocha everywhere: every tool enabled and supported by catppuccin/nix
# (bat, delta, fish, starship, tmux, btop, fzf…) gets the theme.
{ inputs, ... }:
{
  flake.modules.homeManager.theme = {
    imports = [ inputs.catppuccin.homeModules.catppuccin ];

    catppuccin = {
      enable = true;
      flavor = "mocha";
      # Neovim keeps its own catppuccin plugin (kanna, lua/plugins/catppuccin.lua).
      nvim.enable = false;
    };
  };
}
