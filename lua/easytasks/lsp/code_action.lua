-- easytasks/lsp/code_action.lua
local M = {}

local s_util = require("easytasks.toml.schema_util")

---@param bufnr integer
---@param row integer
---@param lines string[]
---@return lsp.TextEdit[]
local function insert_lines_edit(bufnr, row, lines)
  local line = (vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or "")
  return {
    {
      newText = (#line > 0 and "\n" or "") .. table.concat(lines, "\n") .. "\n",
      range = {
        start = { line = row, character = 0 },
        ["end"] = { line = row, character = 0 },
      },
    },
  }
end

---@param context easytasks.LspBufferContext
---@param bufnr integer
---@param row integer
---@return lsp.CodeAction[]
local function missing_required_actions(context, bufnr, row)
  local actions = {}
  local pointer_map = context.parse_results.pointer_map or {}

  -- 1. Locate the active table path and its maximum row bound
  local active_table_path = ""
  local highest_table_start = -1
  local table_end_row = vim.api.nvim_buf_line_count(bufnr)

  for path, range in pairs(pointer_map) do
    if path ~= "/" and range[1] <= row and range[1] > highest_table_start then
      active_table_path = path
      highest_table_start = range[1]
    end
  end

  -- Find where this specific table block ends by finding the next table or end of file
  if active_table_path ~= "" then
    for path, range in pairs(pointer_map) do
      if path ~= "/" and path ~= active_table_path and range[1] > highest_table_start and range[1] < table_end_row then
        -- If this path belongs to a different table block, it caps the current block bounds
        if not path:winfind(active_table_path, 1, true) then
          table_end_row = range[1]
        end
      end
    end
  end

  -- 2. Resolve matching node inside schema
  local schema_node = context.schema
  if active_table_path ~= "" then
    for segment in active_table_path:gmatch("[^/]+") do
      segment = segment:gsub("~1", "/"):gsub("~0", "~")
      if schema_node and schema_node.properties and schema_node.properties[segment] then
        schema_node = schema_node.properties[segment]
      end
    end
  end

  if not schema_node or not schema_node.required then
    return actions
  end

  -- 3. Cross-reference existing data keys to find missing requirements
  local existing_keys = {}
  if context.parse_results.data then
    local current_data = context.parse_results.data
    if active_table_path ~= "" then
      for segment in active_table_path:gmatch("[^/]+") do
        segment = segment:gsub("~1", "/"):gsub("~0", "~")
        if type(current_data) == "table" then current_data = current_data[segment] end
      end
    end
    if type(current_data) == "table" then
      for k, _ in pairs(current_data) do existing_keys[k] = true end
    end
  end

  -- 4. Create text quickfix corrections
  local uri = vim.uri_from_bufnr(bufnr)
  for _, key in ipairs(schema_node.required) do
    if not existing_keys[key] and schema_node.properties and schema_node.properties[key] then
      local prop = schema_node.properties[key]
      local default_val = s_util.get_default_toml(prop)
      if default_val == "" then default_val = '""' end

      local line = ("%s = %s"):format(key, default_val)
      actions[#actions + 1] = {
        title = ("Add required key: %s"):format(key),
        kind = "quickfix",
        edit = {
          changes = {
            [uri] = insert_lines_edit(bufnr, table_end_row, { line }),
          },
        },
      }
    end
  end

  return actions
end

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

  -- Extract key fragment leading up to assignment operator
  local key_name = line:sub(1, eq - 1):match("([%w%-_]+)%s*$")
  if not key_name then
    return actions
  end

  -- Trace active table block to locate property schema constraints
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

---@param context easytasks.LspBufferContext buffer context
---@param params lsp.CodeActionParams
---@param callback fun(err?: lsp.ResponseError, result?: lsp.CodeAction[])
function M.handler(context, params, callback)
  if not context.schema or not context.parse_results then
    callback(nil, {})
    return
  end

  local bufnr = context.bufnr or vim.uri_to_bufnr(params.textDocument.uri)
  local row = params.range.start.line

  local actions = {}
  vim.list_extend(actions, missing_required_actions(context, bufnr, row))
  vim.list_extend(actions, apply_default_actions(context, bufnr, row))

  callback(nil, actions)
end

return M
