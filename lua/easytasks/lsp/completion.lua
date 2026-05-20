-- easytasks/lsp/completion.lua
local M = {}

local s_util = require("easytasks.toml.schema_util")

--------------------------------------------------------------------------------
-- LSP Range & Item Mapping Formatter Helpers
--------------------------------------------------------------------------------

local function replace_range(line, col, prefix, kind)
  if kind == "table_header" then
    local open = line:find("%[")
    if open and not line:find("%]", open) then
      return open, col + 1
    end
  end
  if prefix ~= "" then
    return col - #prefix, col
  end
  return col, col
end

local function text_edit(row, start_col, end_col, new_text)
  return {
    range = {
      start = { line = row, character = start_col },
      ["end"] = { line = row, character = end_col },
    },
    newText = new_text,
  }
end

local function make_item(row, start_col, end_col, new_text, label, kind, detail, documentation)
  return {
    label = label,
    kind = kind,
    detail = detail,
    documentation = documentation,
    insertText = new_text,
    textEdit = text_edit(row, start_col, end_col, new_text),
  }
end

local function sort_items(a, b)
  local ar = a.sortText == "0"
  local br = b.sortText == "0"
  if ar ~= br then
    return ar
  end
  return (a.label or "") < (b.label or "")
end

local function partial_header(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return line:match("%[([^%]]*)$") or ""
end

--------------------------------------------------------------------------------
-- Completion Request Dispatcher
--------------------------------------------------------------------------------

---@param context easytasks.LspBufferContext buffer context
---@param params lsp.CompletionParams
---@param callback fun(err?: lsp.ResponseError, result?: lsp.CompletionList)
function M.handler(context, params, callback)
  local bufnr = context.bufnr or vim.uri_to_bufnr(params.textDocument.uri)
  local row = params.position.line
  local col = params.position.character

  if not context.schema or not context.parse_results then
    callback(nil, { isIncomplete = false, items = {} })
    return
  end

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local line_before_cursor = line:sub(1, col)

  -- 1. Classify typing target via line string pattern inspection
  local kind = "root_key"
  local prefix = ""
  local active_key = nil

  if line_before_cursor:match("%[[^%]]*$") then
    kind = "table_header"
    prefix = line_before_cursor:match("([^%.%[%s]+)$") or ""
  else
    local has_equals = line_before_cursor:find("=")
    if not has_equals then
      prefix = line_before_cursor:match("([%w%-_]+)$") or ""
    else
      kind = "table_value"
      prefix = line_before_cursor:match("([^%s=]+)$") or ""
      active_key = line_before_cursor:match("^%s*([%w%-_]+)%s*=")
    end
  end

  -- 2. Trace the target sub-table block position inside cached pointer_map
  local active_table_path = ""
  local highest_row = -1
  local pointer_map = context.parse_results.pointer_map or {}

  for path, range in pairs(pointer_map) do
    if path ~= "/" and range[1] <= row and range[1] > highest_row then
      active_table_path = path
      highest_row = range[1]
    end
  end

  -- Resolve matching nested sub-tree layout node inside schema blueprints
  local schema_node = context.schema
  if active_table_path ~= "" then
    kind = (kind == "root_key") and "table_key" or kind
    for segment in active_table_path:gmatch("[^/]+") do
      segment = segment:gsub("~1", "/"):gsub("~0", "~")
      if schema_node and schema_node.properties and schema_node.properties[segment] then
        schema_node = schema_node.properties[segment]
      end
    end
  end

  -- Collect brother elements declared inside the target block to block duplicate entry variants
  local existing_keys = {}
  if kind == "table_key" and context.parse_results.data then
    local current_data = context.parse_results.data
    for segment in active_table_path:gmatch("[^/]+") do
      segment = segment:gsub("~1", "/"):gsub("~0", "~")
      if type(current_data) == "table" then
        current_data = current_data[segment]
      end
    end
    if type(current_data) == "table" then
      for k, _ in pairs(current_data) do
        existing_keys[k] = true
      end
    end
  end

  -- 3. Populate LSP results
  local items = {}
  local start_col, end_col = replace_range(line, col, prefix, kind)

  if kind == "table_header" then
    local paths = {}
    s_util.gather_table_paths(context.schema, "", paths)
    for _, entry in ipairs(paths) do
      if s_util.matches_filter(prefix, entry.path) then
        items[#items + 1] = make_item(
          row, start_col, end_col,
          entry.path, entry.path,
          vim.lsp.protocol.CompletionItemKind.Module,
          "table block", s_util.get_description(entry.node)
        )
      end
    end
  elseif kind == "root_key" or kind == "table_key" then
    for _, entry in ipairs(s_util.get_ordered_properties(schema_node)) do
      if not existing_keys[entry.key] and s_util.matches_filter(prefix, entry.key) then
        local detail = s_util.get_type_label(entry.schema)
        local default = s_util.get_default_toml(entry.schema)
        if s_util.is_required(schema_node, entry.key) then
          detail = detail and ("required · " .. detail) or "required"
        end
        if default ~= "" and default ~= '""' then
          detail = detail and (detail .. " · default " .. default) or ("default " .. default)
        end

        items[#items + 1] = make_item(
          row, start_col, end_col,
          entry.key, entry.key,
          vim.lsp.protocol.CompletionItemKind.Property,
          detail, s_util.get_description(entry.schema)
        )
        if s_util.is_required(schema_node, entry.key) then
          items[#items].sortText = "0"
        end
      end
    end
  elseif kind == "table_value" and active_key then
    local key_schema = schema_node and schema_node.properties and schema_node.properties[active_key]
    if key_schema then
      local t = s_util.get_type_label(key_schema)
      local item_kind = (t == "boolean") and vim.lsp.protocol.CompletionItemKind.Keyword or
      vim.lsp.protocol.CompletionItemKind.Value

      local candidates = {}
      if t == "boolean" then candidates = { "true", "false" } end
      if key_schema.enum then
        for _, v in ipairs(key_schema.enum) do
          table.insert(candidates, type(v) == "string" and string.format("%q", v) or tostring(v))
        end
      end

      for _, val in ipairs(candidates) do
        if s_util.matches_filter(prefix, val) then
          items[#items + 1] = make_item(row, start_col, end_col, val, val, item_kind)
        end
      end

      local default = s_util.get_default_toml(key_schema)
      if default ~= "" and s_util.matches_filter(prefix, default) then
        local seen = false
        for _, item in ipairs(items) do if item.label == default then
            seen = true
            break
          end end
        if not seen then
          items[#items + 1] = make_item(
            row, start_col, end_col,
            default, default, item_kind,
            "default", s_util.get_description(key_schema)
          )
        end
      end
    end
  end

  table.sort(items, sort_items)

  callback(nil, {
    isIncomplete = prefix ~= "",
    items = items,
  })
end

return M
