return {
    "saghen/blink.cmp",
    event = "InsertEnter",
    dependencies = {
        "saghen/blink.lib",
        {
            "L3MON4D3/LuaSnip",
            version = "v2.*",
            build = "make install_jsregexp",
        },
        "rafamadriz/friendly-snippets",
    },
    build = function()
        require("blink.cmp").build():pwait()
    end,
    opts = {
        keymap = {
            preset = "default",
            ["<C-j>"] = { "select_next", "fallback" },
            ["<C-k>"] = { "select_prev", "fallback" },
            ["<CR>"] = { "accept", "fallback" },
        },
        completion = {
            documentation = { auto_show = true },
        },
        snippets = { preset = "luasnip" },
        sources = {
            default = { "lsp", "path", "snippets", "buffer" },
        },
        fuzzy = { implementation = "rust" },
    },
}
