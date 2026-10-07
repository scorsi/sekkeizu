return {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
        -- Les formateurs viennent du PATH (fournis par Nix) ; un formateur absent est ignoré.
        local conform = require("conform")

        conform.setup({
            formatters_by_ft = {
                lua = { "stylua" },
                nix = { "nixfmt" },
                go = { "gofmt" },
                zig = { "zigfmt" },
                rust = { "rustfmt" },
                python = { "isort", "black" },
                yaml = { "yamlfmt" },
                hcl = { "hclfmt" },
                terraform = { "hclfmt" },
                bash = { "shfmt" },
                json = { "prettier" },
            },
            format_on_save = {
                lsp_fallback = true,
                async = false,
                timeout_ms = 1000,
            },
        })

        vim.keymap.set({ "n", "v" }, "<leader>mp", function()
            conform.format({
                lsp_fallback = true,
                async = false,
                timeout_ms = 1000,
            })
        end, { desc = "Format file or range (in visual mode)" })
    end,
}
