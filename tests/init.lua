local plenary_dir = os.getenv("NVIM_PLENARY_DIR")
    or vim.fn.expand("~/.config/nvim/pack/plugins/opt/plenary.nvim")

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

local easytasks = require('easytasks')
easytasks.setup()

vim.cmd("runtime plugin/plenary.vim")
