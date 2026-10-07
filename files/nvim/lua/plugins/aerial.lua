return {
    "stevearc/aerial.nvim",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
        "nvim-tree/nvim-web-devicons",
    },
    config = function()
        require("aerial").setup({
            backends = { "treesitter", "lsp" },
        })

        local keymap = vim.keymap

        keymap.set("n", "<leader>ef", "<cmd>AerialToggle!<CR>", {})
    end,
}
