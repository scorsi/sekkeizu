return {
    "mrjones2014/smart-splits.nvim",
    lazy = false,
    config = function()
        local smart_splits = require("smart-splits")

        smart_splits.setup({
            default_amount = 3,
            at_edge = "wrap",
        })

        local keymap = vim.keymap
        keymap.set("n", "<C-h>", smart_splits.move_cursor_left, { desc = "Move to window left" })
        keymap.set("n", "<C-j>", smart_splits.move_cursor_down, { desc = "Move to window down" })
        keymap.set("n", "<C-k>", smart_splits.move_cursor_up, { desc = "Move to window up" })
        keymap.set("n", "<C-l>", smart_splits.move_cursor_right, { desc = "Move to window right" })

        keymap.set("n", "<A-h>", smart_splits.resize_left, { desc = "Resize window left" })
        keymap.set("n", "<A-j>", smart_splits.resize_down, { desc = "Resize window down" })
        keymap.set("n", "<A-k>", smart_splits.resize_up, { desc = "Resize window up" })
        keymap.set("n", "<A-l>", smart_splits.resize_right, { desc = "Resize window right" })
    end,
}
