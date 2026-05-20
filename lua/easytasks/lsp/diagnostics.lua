-- easytasks/lsp/diagnostics.lua

local validator = require("easytasks.toml.validator")
local decoder = require("easytasks.toml.decoder")
local M = {}

local SERVER_NAME = "easytasks-toml"

M.namespace = vim.api.nvim_create_namespace("easytasks-toml")
M.debounce_ms = 250

---@type table<integer, integer?>
local debounce_timers = {}

---@type table<integer, integer[]>
local autocmd_ids = {}

---@param range easytasks.Range4
---@return lsp.Range
local function to_lsp_range(range)
  return {
    start = { line = range[1], character = range[2] },
    ["end"] = { line = range[3], character = range[4] },
  }
end

---@param range easytasks.Range4|nil
---@param bufnr integer
---@return lsp.Range
local function fallback_range(range, bufnr)
  if range then
    return to_lsp_range(range)
  end

  -- Tie it exactly to the user's active cursor line without compounding line splits
  local current_win = vim.fn.bufwinid(bufnr)
  if current_win ~= -1 then
    local cursor = vim.api.nvim_win_get_cursor(current_win)
    local row = math.max(0, cursor[1] - 1) -- 1-indexed to 0-indexed conversion
    return {
      start = { line = row, character = 0 },
      ["end"] = { line = row, character = 0 },
    }
  end

  -- Safe fallback if window context is completely detached
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local target_line = math.max(0, line_count - 1)
  return {
    start = { line = target_line, character = 0 },
    ["end"] = { line = target_line, character = 0 },
  }
end

---@param bufnr integer
---@param context easytasks.LspBufferContext
---@return lsp.Diagnostic[]
function M.build(bufnr, context)
  local diagnostics = {}
  local accumulated_errors = {}

  -- If upstream has not populated an AST tree yet, skip validation and return clean
  if not context.ast then
    return diagnostics
  end

  -- 1. Semantic decode/evaluation using the pre-existing AST tree block
  local decoded = decoder.decode(context.ast)

  for _, err in ipairs(decoded.errors or {}) do
    table.insert(accumulated_errors, err)
    diagnostics[#diagnostics + 1] = {
      range = fallback_range(err.range, bufnr),
      severity = vim.lsp.protocol.DiagnosticSeverity.Error,
      source = SERVER_NAME,
      message = err.message,
    }
  end

  -- Stop if semantic evaluation failed
  if not decoded.ok or not decoded.data then
    context.parse_results = { data = nil, pointer_map = decoded.pointer_map, errors = accumulated_errors }
    return diagnostics
  end

  -- 2. Schema validation running on top of decoded outputs
  if context.schema then
    local valid, errors = validator.validate(context.schema, decoded.data)

    if not valid then
      for _, err in ipairs(errors) do
        table.insert(accumulated_errors, err)
        local range = decoded.pointer_map[err.path]

        diagnostics[#diagnostics + 1] = {
          range = fallback_range(range, bufnr),
          severity = vim.lsp.protocol.DiagnosticSeverity.Error,
          source = SERVER_NAME,
          message = err.err_msg,
        }
      end
    end
  end

  -- Safely sync all accumulated state details back to context closure tracking
  context.parse_results = {
    data = decoded.data,
    pointer_map = decoded.pointer_map,
    errors = accumulated_errors,
  }

  return diagnostics
end

---@param bufnr integer
---@param diagnostics lsp.Diagnostic[]
---@param client_id integer?
function M.publish(bufnr, diagnostics, client_id)
  if client_id then
    vim.lsp.handlers[vim.lsp.protocol.Methods.textDocument_publishDiagnostics](
      nil,
      {
        uri = vim.uri_from_bufnr(bufnr),
        diagnostics = diagnostics,
      },
      { client_id = client_id, method = vim.lsp.protocol.Methods.textDocument_publishDiagnostics }
    )
    return
  end

  local items = {}
  for _, diag in ipairs(diagnostics) do
    items[#items + 1] = {
      lnum = diag.range.start.line,
      col = diag.range.start.character,
      end_lnum = diag.range["end"].line,
      end_col = diag.range["end"].character,
      severity = vim.diagnostic.severity.ERROR,
      message = diag.message,
      source = diag.source,
    }
  end
  vim.diagnostic.set(M.namespace, bufnr, items)
end

---@param bufnr integer
---@param context easytasks.LspBufferContext
---@param client_id integer?
function M.run(bufnr, context, client_id)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local diagnostics = M.build(bufnr, context)
  M.publish(bufnr, diagnostics, client_id)
end

---@param bufnr integer
---@param context easytasks.LspBufferContext
---@param client_id integer?
local function schedule(bufnr, context, client_id)
  if debounce_timers[bufnr] then
    vim.fn.timer_stop(debounce_timers[bufnr])
  end
  debounce_timers[bufnr] = vim.fn.timer_start(M.debounce_ms, function()
    debounce_timers[bufnr] = nil
    vim.schedule(function()
      M.run(bufnr, context, client_id)
    end)
  end)
end

---@param bufnr integer
function M.detach(bufnr)
  if debounce_timers[bufnr] then
    vim.fn.timer_stop(debounce_timers[bufnr])
    debounce_timers[bufnr] = nil
  end
  for _, id in ipairs(autocmd_ids[bufnr] or {}) do
    pcall(vim.api.nvim_del_autocmd, id)
  end
  autocmd_ids[bufnr] = nil
  vim.diagnostic.reset(M.namespace, bufnr)
end

---@param bufnr integer
---@param context easytasks.LspBufferContext
---@param client_id integer?
function M.attach(bufnr, context, client_id)
  M.detach(bufnr)
  autocmd_ids[bufnr] = {}

  local group = vim.api.nvim_create_augroup("easytasks_toml_diag_" .. bufnr, { clear = true })
  local events = { "BufEnter", "TextChanged", "InsertLeave", "BufWritePost" }
  for _, event in ipairs(events) do
    autocmd_ids[bufnr][#autocmd_ids[bufnr] + 1] = vim.api.nvim_create_autocmd(event, {
      group = group,
      buffer = bufnr,
      callback = function()
        schedule(bufnr, context, client_id)
      end,
    })
  end

  M.run(bufnr, context, client_id)
end

return M
