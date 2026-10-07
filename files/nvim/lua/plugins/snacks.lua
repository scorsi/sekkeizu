-- Remplace indent-blankline (indent), vim-maximizer (zen.zoom) et telescope (picker).
return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
        indent = {},
        zen = {},
        picker = { ui_select = true },
    },
    keys = {
        { "<leader>ff", function() Snacks.picker.files() end, desc = "Fuzzy find files in cwd" },
        { "<leader>fr", function() Snacks.picker.recent() end, desc = "Fuzzy find recent files" },
        { "<leader>fs", function() Snacks.picker.grep() end, desc = "Find string in cwd" },
        { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Display buffers" },
        { "<leader>fc", function() Snacks.picker.grep_word() end, desc = "Find string under cursor in cwd" },
        { "<leader>ft", function() Snacks.picker.todo_comments() end, desc = "Find todos" },
        { "<leader>fa", function() Snacks.picker.lsp_symbols() end, desc = "Find symbols" },
        { "<leader>sm", function() Snacks.zen.zoom() end, desc = "Maximize/minimize a split" },
    },
}
