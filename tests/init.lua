local PLENARY_REPO   = "https://github.com/nvim-lua/plenary.nvim"
local PLENARY_COMMIT = "74b06c6c75e4eeb3108ec01852001636d85a932b"
local plenary_dir    = os.getenv("NVIM_PLENARY_DIR") or "/tmp/plenary.nvim"

if vim.fn.isdirectory(plenary_dir) == 0 then
    print("cloning plenary.nvim @ " .. PLENARY_COMMIT .. " …")
    vim.fn.system({ "git", "init", plenary_dir })
    vim.fn.system({ "git", "-C", plenary_dir, "fetch", "--depth", "1", PLENARY_REPO, PLENARY_COMMIT })
    vim.fn.system({ "git", "-C", plenary_dir, "checkout", "FETCH_HEAD" })
end

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

-- easytasks.setup() requires `tomltools`; make it discoverable. Prefer an
-- explicit override, otherwise fall back to the sibling plugin directory.
local tomltools_dir = os.getenv("NVIM_TOMLTOOLS_DIR") or "../tomltools.nvim"
if vim.fn.isdirectory(tomltools_dir) == 1 then
    vim.opt.rtp:append(tomltools_dir)
end

local easytasks = require("easytasks")
easytasks.setup()

vim.cmd("runtime plugin/plenary.vim")
