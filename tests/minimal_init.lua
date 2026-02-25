-- tests/minimal_init.lua
-- Bootstraps plenary.nvim and citeref for headless test runs.
-- Run via: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {sequential=true}"

-- Point rtp at the plugin root (citeref) and at plenary.
vim.opt.rtp:prepend(".")

-- Plenary is cloned by the CI workflow into a known location.
local plenary_path = vim.fn.expand("~/.local/share/nvim/site/pack/test/start/plenary.nvim")
vim.opt.rtp:append(plenary_path)

-- Required so vim.filetype and other basics work in headless mode.
vim.cmd("runtime! plugin/plenary.vim")
