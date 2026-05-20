-- easytasks/lsp/code_action.lua
local M = {}

local s_util = require("easytasks.toml.schema_util")

--------------------------------------------------------------------------------
-- Provider Actions
--------------------------------------------------------------------------------

---@param context easytasks.LspBufferContext
---@param bufnr integer
---@param row integer
---@return lsp.CodeAction[]
local function apply_default_actions(context, bufnr, row)
  local actions = {}
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local eq = line:find("=")
  if not eq then
    return actions
  end

  local key_name = line:sub(1, eq - 1):match("([%w%-_]+)%s*$")
  if not key_name then
    return actions
  end

  local pointer_map = context.parse_results.pointer_map or {}
  local active_table_path = ""
  local highest_table_start = -1

  for path, range in pairs(pointer_map) do
    if path ~= "/" and range[1] <= row and range[1] > highest_table_start then
      active_table_path = path
      highest_table_start = range[1]
    end
  end

  local schema_node = context.schema
  if active_table_path ~= "" then
    for segment in active_table_path:gmatch("[^/]+") do
      segment = segment:gsub("~1", "/"):gsub("~0", "~")
      if schema_node and schema_node.properties and schema_node.properties[segment] then
        schema_node = schema_node.properties[segment]
      end
    end
  end

  local key_schema = schema_node and schema_node.properties and schema_node.properties[key_name]
  if not key_schema or key_schema.default == nil then
    return actions
  end

  local default = s_util.get_default_toml(key_schema)
  if default == "" then return actions end

  actions[#actions + 1] = {
    title = ("Set default for %s"):format(key_name),
    kind = "quickfix",
    edit = {
      changes = {
        [vim.uri_from_bufnr(bufnr)] = {
          {
            newText = "= " .. default,
            range = {
              start = { line = row, character = eq - 1 },
              ["end"] = { line = row, character = #line },
            },
          },
        },
      },
    },
  }
  return actions
end

--------------------------------------------------------------------------------
-- LSP Request Interface
--------------------------------------------------------------------------------

---@param context easytasks.LspBufferContext buffer context
---@param params lsp.CodeActionParams
---@param callback fun(err?: lsp.ResponseError, result?: lsp.CodeAction[])
function M.handler(context, params, callback)
  if not context.parse_results then
    callback(nil, {})
    return
  end

  local bufnr = context.bufnr or vim.uri_to_bufnr(params.textDocument.uri)
  local row = params.range.start.line

  local actions = {}

  -- 1. Apply defaults quickfix mapping
  if context.schema then
    vim.list_extend(actions, apply_default_actions(context, bufnr, row))
  end

  -- 2. Inspect active runtime parsed data by replacing buffer contents with TOML comments
  if context.parse_results.data then
    local uri = vim.uri_from_bufnr(bufnr)
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    -- Split the text into lines, prefix each line with '#', and join them back
    local inspect_lines = vim.split(vim.inspect(context.parse_results.data), "\n")
    for idx, line in ipairs(inspect_lines) do
      inspect_lines[idx] = "# " .. line
    end

    local replacement_text = "# DECODED TOML DATASET STRUCTURE DUMP:\n"
        .. table.concat(inspect_lines, "\n")
        .. "\n"

    actions[#actions + 1] = {
      title = "Replace buffer with decoded TOML structure dump",
      kind = "source.inspect",
      edit = {
        changes = {
          [uri] = {
            {
              newText = replacement_text,
              range = {
                start = { line = 0, character = 0 },
                ["end"] = { line = line_count, character = 0 },
              },
            },
          },
        },
      },
    }
  end

  callback(nil, actions)
end

return M
