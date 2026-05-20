-- easytasks/lsp/hover.lua
local M = {}

local s_util = require("easytasks.toml.schema_util")

---@param node table?
---@return string|nil
local function hover_text(node)
  if not node then
    return nil
  end

  local lines = {}
  if node.title then
    lines[#lines + 1] = "**" .. node.title .. "**"
  end
  if node.description then
    lines[#lines + 1] = node.description
  end

  local type_label = s_util.get_type_label(node)
  if type_label ~= "any" then
    lines[#lines + 1] = ("Type: `%s`"):format(type_label)
  end

  local default_val = s_util.get_default_toml(node)
  if default_val ~= "" then
    lines[#lines + 1] = ("Default: `%s`"):format(default_val)
  end

  if node.required and #node.required > 0 then
    lines[#lines + 1] = "Required keys: " .. table.concat(node.required, ", ")
  end

  if #lines == 0 then
    return nil
  end
  return table.concat(lines, "\n\n")
end

---@param context easytasks.LspBufferContext buffer context
---@param params lsp.HoverParams
---@param callback fun(err?: lsp.ResponseError, result?: lsp.Hover)
function M.handler(context, params, callback)
  if not context.schema or not context.parse_results then
    callback(nil, nil)
    return
  end

  local row = params.position.line
  local col = params.position.character

  local pointer_map = context.parse_results.pointer_map or {}
  local matched_path = nil
  local smallest_range_width = math.huge

  -- 1. Scan pointer_map to find the tightest matched structural path enclosing the cursor
  for path, range in pairs(pointer_map) do
    local s_row, s_col, e_row, e_col = range[1], range[2], range[3], range[4]

    local inside = true
    if row < s_row or row > e_row then inside = false end
    if row == s_row and col < s_col then inside = false end
    if row == e_row and col > e_col then inside = false end

    if inside then
      local width = (e_row - s_row) * 1000 + (e_col - s_col)
      if width < smallest_range_width then
        smallest_range_width = width
        matched_path = path
      end
    end
  end

  -- 2. Trace down the matched JSON-pointer inside the schema tree node layout
  local node = context.schema
  if matched_path and matched_path ~= "/" then
    for segment in matched_path:gmatch("[^/]+") do
      segment = segment:gsub("~1", "/"):gsub("~0", "~") -- unescape JSON-Pointer tokens
      if node and node.properties and node.properties[segment] then
        node = node.properties[segment]
      else
        node = nil
        break
      end
    end
  end

  -- 3. Stringify structural constraints to fulfill Markdown block protocol
  local contents = hover_text(node)
  if not contents then
    callback(nil, nil)
    return
  end

  callback(nil, {
    contents = {
      kind = "markdown",
      value = contents,
    },
  })
end

return M
