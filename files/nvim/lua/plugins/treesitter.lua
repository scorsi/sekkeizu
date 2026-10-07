return {
    {
        "nvim-treesitter/nvim-treesitter",
        -- Branche historique (API `configs`) ; la branche main a une API différente.
        branch = "master",
        build = ":TSUpdate",
        config = function()
            local config = require("nvim-treesitter.configs")
            config.setup({
                ensure_installed = {
                    "vimdoc",
                    "lua",
                    "rust",
                    "python",
                    "hcl",
                    "terraform",
                    "yaml",
                    "toml",
                    "nix",
                    "go",
                    "zig",
                    "fish",
                    "bash",
                    "json",
                },
                highlight = {
                    enable = true,
                    additional_vim_regex_highlighting = false,
                },
                indent = {
                    enable = true,
                },
            })
        end,
    },
}
