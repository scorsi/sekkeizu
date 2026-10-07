vim.g.mapleader = " "

local keymap = vim.keymap

keymap.set("n", "<leader>pv", vim.cmd.Ex, {})

keymap.set("n", "<leader>sv", "<C-w>v", { desc = "Split window vertically" })
keymap.set("n", "<leader>sh", "<C-w>s", { desc = "Split window horizontally" })
keymap.set("n", "<leader>se", "<C-w>=", { desc = "Make splits equal size" })
keymap.set("n", "<leader>sx", "<cmd>close<CR>", { desc = "Close current split" })

keymap.set("n", "<M-Left>", "<C-w>h", { desc = "Move window left" })
keymap.set("n", "<M-Right>", "<C-w>l", { desc = "Move window right" })
keymap.set("n", "<M-Up>", "<C-w>k", { desc = "Move window up" })
keymap.set("n", "<M-Down>", "<C-w>j", { desc = "Move window down" })
