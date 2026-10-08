# Neovim with the Lua config (lazy.nvim), carried over from dev-configs into files/nvim.
#
# ~/.config/nvim links straight to files/nvim in the repo (an "out of store" symlink):
# edits apply without a rebuild, and lazy.nvim writes its lazy-lock.json into the repo,
# pinning plugin versions with git.
#
# LSPs and formatters come from Nix (the `neovim-dev` feature), no more mason:
# the Lua config only enables a server if its binary is present.
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
        # blink.cmp compiles its fuzzy matcher in Rust on first start.
        pkgs.cargo
        pkgs.rustc
      ]
      # nvim-treesitter compiles its parsers: macOS has clang via the Command Line Tools.
      ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.gcc ];

      home.sessionVariables.EDITOR = "nvim";

      xdg.configFile."nvim".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${repoDir}/files/nvim";
    };

  # Dev tools for Neovim: import on machines where you code (laptop),
  # not necessarily on the server.
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
        nimlangserver
        vscode-langservers-extracted # jsonls
        # Formatters and linters
        stylua
        nixfmt
        shfmt
        yamlfmt
        yamllint
        prettier
        # nimlangserver drives nimsuggest from the compiler, nimpretty ships with it.
        nim
        nimble
      ];
    };
}
