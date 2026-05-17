local plenary_dir = os.getenv("NVIM_PLENARY_DIR") or "/tmp/plenary.nvim"
local is_not_a_directory = vim.fn.isdirectory(plenary_dir) == 0
if is_not_a_directory then
  print("cloning plenary into " .. plenary_dir)
  vim.fn.system({ "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir })
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

local keystone = require('keystone')
keystone.setup()

vim.cmd("runtime plugin/plenary.vim")
