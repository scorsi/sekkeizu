# Neovim avec ta config Lua (lazy.nvim), reprise de dev-configs dans files/nvim.
#
# ~/.config/nvim pointe directement vers files/nvim dans le repo (lien « hors store ») :
# tu modifies la config sans rebuild, et lazy.nvim écrit son lazy-lock.json dans le repo,
# ce qui épingle les versions des plugins avec git.
#
# Les LSP et formateurs viennent de Nix (feature `neovim-dev`), plus de mason :
# la config Lua n'active un serveur que si son binaire est présent.
{ config, ... }:
let
  inherit (config.sekkeizu) repoDir;
in
{
  flake.modules.homeManager.neovim =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      home.packages = [
        pkgs.neovim
        pkgs.tree-sitter
        # blink.cmp compile son matcher flou en Rust au premier démarrage.
        pkgs.cargo
        pkgs.rustc
      ]
      # nvim-treesitter compile ses parseurs : macOS a clang via les Command Line Tools.
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.gcc ];

      home.sessionVariables.EDITOR = "nvim";

      xdg.configFile."nvim".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${repoDir}/files/nvim";
    };

  # Outils de dev pour Neovim : à importer sur les machines où tu codes (laptop),
  # pas forcément sur le serveur.
  flake.modules.homeManager.neovim-dev =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # LSP
        lua-language-server
        nil
        yaml-language-server
        taplo
        bash-language-server
        vscode-langservers-extracted # jsonls
        # Formateurs et linters
        stylua
        nixfmt
        shfmt
        yamlfmt
        yamllint
        prettier
      ];
    };
}
