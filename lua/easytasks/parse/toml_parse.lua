local tomldecoder = require("easytasks.toml.decoder")

local M = {}

---@class easytasks.TomlParseResult
---@field ok boolean
---@field data table|nil
---@field syntax_errors easytasks.TomlSyntaxError[]
---@field pointer_map table<string, easytasks.Range4>
---@field err string|nil

---@param bufnr integer
---@return string
function M.buf_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  if #lines == 0 then
    return ""
  end

  return table.concat(lines, "\n") .. "\n"
end

---@param bufnr integer
---@return easytasks.TomlParseResult
function M.parse(bufnr)
  local text = M.buf_text(bufnr)

  if text == "" then
    return {
      ok = true,
      data = {},
      syntax_errors = {},
    }
  end

  local result = tomldecoder.decode(text)

  if not result.ok then
    return {
      ok = false,
      data = nil,
      pointer_map = result.pointer_map,
      syntax_errors = result.errors,
      err = (
        result.errors[1]
        and result.errors[1].message
      ) or "syntax error",
    }
  end

  return {
    ok = true,
    pointer_map = result.pointer_map,
    data = result.data,
    syntax_errors = {},
  }
end

return M
