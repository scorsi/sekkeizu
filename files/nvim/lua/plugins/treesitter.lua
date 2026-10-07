-- La branche "master" (ancienne API) a été figée par upstream puis le repo
-- a été archivé le 2026-04-03 : la réécriture "main" (API différente, nécessite
-- Neovim >=0.12) est la seule branche qui reçoit encore des mises à jour.
return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    config = function()
        local languages = {
            "bash",
            "c",
            "fish",
            "json",
            "lua",
            "markdown",
            "markdown_inline",
            "nix",
            "query",
            "toml",
            "vim",
            "vimdoc",
            "yaml",
        }

        require("nvim-treesitter").install(languages)

        -- La branche main ne gère plus highlight/indent automatiquement :
        -- ce sont les fonctionnalités natives de Neovim, activées par filetype.
        vim.api.nvim_create_autocmd("FileType", {
            pattern = {
                "sh",
                "c",
                "fish",
                "json",
                "lua",
                "markdown",
                "nix",
                "toml",
                "vim",
                "help",
                "yaml",
            },
            callback = function()
                vim.treesitter.start()
                vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end,
        })
    end,
}
