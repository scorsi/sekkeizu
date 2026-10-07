# Catppuccin Mocha partout : chaque outil activé et supporté par catppuccin/nix
# (bat, delta, fish, starship, tmux, lazygit, btop, fzf…) reçoit le thème.
{ inputs, ... }:
{
  flake.modules.homeManager.theme = {
    imports = [ inputs.catppuccin.homeModules.catppuccin ];

    catppuccin = {
      enable = true;
      flavor = "mocha";
      # Neovim garde son propre plugin catppuccin (files/nvim/lua/plugins/catppuccin.lua).
      nvim.enable = false;
    };
  };
}
