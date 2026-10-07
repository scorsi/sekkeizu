-- LSP : les serveurs sont fournis par Nix (plus de mason), nvim-lspconfig
-- ne sert qu'à fournir leurs configurations par défaut (dossier lsp/).
-- Un serveur n'est activé que si son binaire est dans le PATH : la même config
-- marche sur le serveur (peu d'outils) comme sur le laptop (outils de dev complets).

local servers = {
    "lua_ls",
    "nil_ls", -- Nix
    "rust_analyzer",
    "gopls",
    "zls", -- Zig
    "pyright",
    "terraformls",
    "yamlls",
    "taplo", -- TOML
    "dockerls",
    "docker_compose_language_service",
    "bashls",
    "jsonls",
}

return {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        { "antosha417/nvim-lsp-file-operations", config = true },
        -- Remplace neodev.nvim (abandonné) : complétion de l'API Neovim dans les fichiers Lua.
        { "folke/lazydev.nvim", ft = "lua", opts = {} },
    },
    config = function()
        local keymap = vim.keymap

        vim.api.nvim_create_autocmd("LspAttach", {
            group = vim.api.nvim_create_augroup("UserLspConfig", {}),
            callback = function(ev)
                local opts = { buffer = ev.buf, silent = true }

                opts.desc = "Show LSP references"
                keymap.set("n", "gR", "<cmd>Telescope lsp_references<CR>", opts)

                opts.desc = "Go to declaration"
                keymap.set("n", "gD", vim.lsp.buf.declaration, opts)

                opts.desc = "Show LSP definitions"
                keymap.set("n", "gd", "<cmd>Telescope lsp_definitions<CR>", opts)

                opts.desc = "Show LSP implementations"
                keymap.set("n", "gi", "<cmd>Telescope lsp_implementations<CR>", opts)

                opts.desc = "Show LSP type definitions"
                keymap.set("n", "gt", "<cmd>Telescope lsp_type_definitions<CR>", opts)

                opts.desc = "See available code actions"
                keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)

                opts.desc = "Smart rename"
                keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

                opts.desc = "Show buffer diagnostics"
                keymap.set("n", "<leader>D", "<cmd>Telescope diagnostics bufnr=0<CR>", opts)

                opts.desc = "Show line diagnostics"
                keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)

                opts.desc = "Go to previous diagnostic"
                keymap.set("n", "[d", function()
                    vim.diagnostic.jump({ count = -1, float = true })
                end, opts)

                opts.desc = "Go to next diagnostic"
                keymap.set("n", "]d", function()
                    vim.diagnostic.jump({ count = 1, float = true })
                end, opts)

                opts.desc = "Show documentation for what is under cursor"
                keymap.set("n", "K", vim.lsp.buf.hover, opts)

                opts.desc = "Restart LSP"
                keymap.set("n", "<leader>rs", ":LspRestart<CR>", opts)
            end,
        })

        -- API native de Neovim (0.11+) : capacités de complétion communes à tous les serveurs.
        vim.lsp.config("*", {
            capabilities = require("cmp_nvim_lsp").default_capabilities(),
        })

        for _, name in ipairs(servers) do
            local cfg = vim.lsp.config[name]
            local cmd = cfg and cfg.cmd
            if type(cmd) == "table" and vim.fn.executable(cmd[1]) == 1 then
                vim.lsp.enable(name)
            end
        end
    end,
}
