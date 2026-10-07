local opt = vim.opt

opt.expandtab = true
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.smartindent = true

opt.number = true
opt.relativenumber = true
opt.cursorline = true

opt.splitright = true
opt.splitbelow = true

opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false
opt.incsearch = true

opt.backspace = "indent,eol,start"

opt.swapfile = true
opt.backup = false
opt.undofile = true
opt.directory = os.getenv("HOME") .. "/.local/share/nvim/swap"
opt.undodir = os.getenv("HOME") .. "/.local/share/nvim/undo"

opt.termguicolors = true

opt.scrolloff = 8
opt.signcolumn = "yes"
opt.isfname:append("@-@")

opt.updatetime = 50

-- vim.opt.colorcolumn = "80"

vim.g.loaded_python3_provider = false
vim.g.loaded_ruby_provider = false
vim.g.loaded_node_provider = false
vim.g.loaded_perl_provider = false
