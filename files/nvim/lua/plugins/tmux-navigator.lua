return {
    "christoomey/vim-tmux-navigator",
    cmd = {
        "TmuxNavigateLeft",
        "TmuxNavigateDown",
        "TmuxNavigateUp",
        "TmuxNavigateRight",
        "TmuxNavigatePrevious",
    },
    keys = {
        { "<M-Left>", "<cmd>TmuxNavigateLeft<cr>", "Move window left" },
        { "<M-Down>", "<cmd>TmuxNavigateDown<cr>", "Move window down" },
        { "<M-Up>", "<cmd>TmuxNavigateUp<cr>", "Move window up" },
        { "<M-Right>", "<cmd>TmuxNavigateRight<cr>", "Move window right" },
        { "<M-\\>", "<cmd>TmuxNavigatePrevious<cr>" },
    },
}
