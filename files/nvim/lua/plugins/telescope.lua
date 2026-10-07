return {
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.5",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope-ui-select.nvim",
            { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
            "nvim-tree/nvim-web-devicons",
            "folke/todo-comments.nvim",
        },
        config = function()
            local telescope = require("telescope")

            local additional_rg_args = { "--hidden", "--glob", "!**/.git/*", "--glob", "!**/node_modules/*" }

            telescope.setup({
                defaults = {
                    theme = "ivy",
                },

                pickers = {
                    find_files = {
                        theme = "ivy",
                        find_command = { "rg", "--files", "--hidden", "--glob", "!**/.git/*" },
                    },
                    live_grep = {
                        theme = "ivy",
                        additional_args = additional_rg_args,
                    },
                    grep_string = {
                        theme = "ivy",
                        additional_args = additional_rg_args,
                    },
                    oldfiles = { theme = "ivy" },
                    buffers = { theme = "ivy" },
                },

                extensions = {
                    ["ui-select"] = {
                        require("telescope.themes").get_dropdown({}),
                    },

                    aerial = {
                        show_nesting = {
                            ["_"] = true,
                        },
                    },
                },
            })

            telescope.load_extension("ui-select")
            telescope.load_extension("fzf")
            telescope.load_extension("aerial")

            local keymap = vim.keymap
            keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Fuzzy find files in cwd" })
            keymap.set("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Fuzzy find recent files" })
            keymap.set("n", "<leader>fs", "<cmd>Telescope live_grep<cr>", { desc = "Find string in cwd" })
            keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Display buffers" })
            keymap.set(
                "n",
                "<leader>fc",
                "<cmd>Telescope grep_string<cr>",
                { desc = "Find string under cursor in cwd" }
            )
            keymap.set("n", "<leader>ft", "<cmd>TodoTelescope theme=ivy<cr>", { desc = "Find todos" })
            keymap.set("n", "<leader>fa", "<cmd>Telescope aerial theme=ivy<cr>", { desc = "Find symbols" })
            -- TODO: when available, use ivy theme
            keymap.set("n", "<leader>fv", "<cmd>VenvSelect<cr>", { desc = "Find python virtualenv" })
        end,
    },
}
