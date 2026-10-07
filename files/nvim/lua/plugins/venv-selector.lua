return {
    "linux-cultist/venv-selector.nvim",
    dependencies = {
        "neovim/nvim-lspconfig",
        "nvim-telescope/telescope.nvim",
    },
    event = "VimEnter",
    config = function()
        local venv = vim.fn.findfile("pyproject.toml", ".;")
        print(venv)
        if venv ~= "" then
            local venv_selector = require("venv-selector")

            venv_selector.setup({
                name = { ".venv", "venv" },
                changed_venv_hooks = {
                    venv_selector.hooks.pyright,
                },
            })

            venv_selector.retrieve_from_cache()
        end
    end,
}
