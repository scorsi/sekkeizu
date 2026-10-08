# Neovim: the kanna flake (github:scorsi/kanna), its own repo with its own lockfile. Its
# home-manager module installs Neovim and owns ~/.config/nvim.
#
#   kanna      the config from the store: frozen, the plugins follow the lockfile pinned by flake.lock.
#   kanna-dev  where the config is worked on: ~/.config/nvim links to the live clone in
#              <reposDir>/kanna (Lua edits apply without a rebuild, lazy.nvim updates the clone's
#              lockfile), plus the LSP servers and formatters.
{ config, inputs, ... }:
let
  inherit (config.sekkeizu) reposDir;
in
{
  flake.modules.homeManager.kanna = {
    imports = [ inputs.kanna.homeModules.default ];
  };

  flake.modules.homeManager.kanna-dev =
    { config, ... }:
    {
      programs.kanna = {
        devPath = "${config.home.homeDirectory}/${reposDir}/kanna";
        withDevTools = true;
      };
    };
}
