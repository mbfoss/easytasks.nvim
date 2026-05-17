local M = {}

---@class keystone.tasks.Config
---@field enabled boolean
---@field schema keystone.tasks.JsonSchema?

local tasks_lsp = require("keystone.tasks.tasks_lsp")
local default_schema = require("keystone.tasks.parse.schema")

local function _get_default_config()
  ---@type keystone.tasks.Config
  return {
    enabled = true,
    schema = default_schema,
  }
end

---@type keystone.tasks.Config
M.config = _get_default_config()

local enabled = false

function M.enable()
  if enabled then
    return
  end
  enabled = true
  local augroup = vim.api.nvim_create_augroup("keystone_tasks_lsp", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "toml" },
    group = augroup,
    callback = function(ev)
      tasks_lsp.start(ev.buf, { schema = M.config.schema })
    end,
  })
end

function M.disable()
  if not enabled then
    return
  end
  enabled = false
  vim.api.nvim_del_augroup_by_name("keystone_tasks_lsp")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "toml" then
      tasks_lsp.stop(buf)
    end
  end
end

function M.clear()
  vim.lsp.buf.clear_references()
end

---@param opts keystone.tasks.Config?
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", _get_default_config(), opts or {})
  tasks_lsp.set_schema(M.config.schema)

  if M.config.enabled then
    M.enable()
  else
    M.disable()
  end
end

return M
