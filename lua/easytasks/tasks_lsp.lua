local completion = require("easytasks.lsp.completion")
local hover = require("easytasks.lsp.hover")
local code_action = require("easytasks.lsp.code_action")
local diagnostics = require("easytasks.lsp.diagnostics")
local format = require("easytasks.lsp.format")

local M = {}

M.SERVER_NAME = "easytasks-toml"
M.SERVER_VERSION = "0.1.0"

---@type table<vim.lsp.protocol.Method, fun(context: table, params: table, callback: fun(err: lsp.ResponseError?, result: any))>
local handlers = {}

---@type table<integer, integer>
local attached_clients = {}

local features = {
  completion = completion,
  hover = hover,
  code_action = code_action,
  diagnostics = diagnostics,
  format = format,
}

local ms = vim.lsp.protocol.Methods

---@type lsp.InitializeResult
local initialize_result = {
  capabilities = {
    hoverProvider = true,
    completionProvider = {
      triggerCharacters = { ".", "[", '"', "=", " " },
    },
    codeActionProvider = {
      codeActionKinds = { "quickfix" },
    },
    documentFormattingProvider = true,
    documentRangeFormattingProvider = true,
  },
  serverInfo = {
    name = M.SERVER_NAME,
    version = M.SERVER_VERSION,
  },
}

---@param feature string
---@param mod { handler: fun(context: table, params: table, callback: fun(err?: lsp.ResponseError, result: any)) }
function M.register_feature(feature, mod)
  features[feature] = mod
  M._bind_handlers()
end

function M._bind_handlers()
  handlers[ms.initialize] = function(_, _, callback)
    callback(nil, initialize_result)
  end
  handlers[ms.textDocument_completion] = features.completion.handler
  handlers[ms.textDocument_hover] = features.hover.handler
  handlers[ms.textDocument_codeAction] = features.code_action.handler
  handlers[ms.textDocument_formatting] = features.format.handler
  handlers[ms.textDocument_rangeFormatting] = features.format.handler
end

M._bind_handlers()

---@class easytasks.LspStartOpts
---@field schema table?

---@param buf integer
---@param opts easytasks.LspStartOpts?
---@return integer? client_id
function M.start(buf, opts)
  opts = opts or {}
  if attached_clients[buf] then
    M.stop(buf)
  end

  ---@class easytasks.LspBufferContext
  local context = {
    schema = opts.schema,
    parse_results = nil,
    bufnr = buf,
  }

  -- Build a direct, loopback interface matching Neovim's expected RPC interface layout
  local dispatch = {
    request = function(method, params, callback)
      local handler = handlers[method]
      if handler then
        -- FIXED: context is safely passed as the first parameter
        handler(context, params, callback)
        return true, nil
      end
      return false, nil
    end,
    notify = function(_, _) end,
    is_closing = function() return false end,
    terminate = function() end,
  }

  ---@type vim.lsp.ClientConfig
  local client_cfg = {
    name = M.SERVER_NAME,
    -- FIXED: Wrapped inside an initialization function matching internal core API expectations
    cmd = function(dispatchers)
      return dispatch
    end,
  }

  local client_id = vim.lsp.start(client_cfg, { bufnr = buf, silent = false })
  if client_id then
    attached_clients[buf] = client_id
    diagnostics.attach(buf, context, client_id)
  end

  return client_id
end

---@param buf integer
function M.stop(buf)
  diagnostics.detach(buf)

  local clients = vim.lsp.get_clients({ bufnr = buf, name = M.SERVER_NAME })
  for _, client in ipairs(clients) do
    if client.id == attached_clients[buf] then
      ---@diagnostic disable-next-line: deprecated
      vim.lsp.stop_client(client.id, true)
    end
  end

  attached_clients[buf] = nil
end

return M
