-- easytasks LSP server — runs as a headless Neovim subprocess.
-- Launched via: nvim --headless -l <this file>
-- Communicates with the Neovim LSP client over stdin/stdout using JSON-RPC
-- with Content-Length framing (standard LSP transport).
--
-- All parsing, decoding, and validation runs here, off the main Neovim thread.

-- ── Module resolution ────────────────────────────────────────────────────────
-- The plugin's lua/ directory must be on package.path before any require().
local _src  = debug.getinfo(1, "S").source:sub(2)          -- strip leading "@"
local _lua  = vim.fn.fnamemodify(_src, ":h:h:h")           -- .../lua
package.path = _lua .. "/?.lua;" .. _lua .. "/?/init.lua;" .. package.path

-- ── Imports ──────────────────────────────────────────────────────────────────
local parser      = require("easytasks.toml.parser")
local decoder     = require("easytasks.toml.decoder")
local diagnostics = require("easytasks.lsp.diagnostics")
local completion  = require("easytasks.lsp.completion")
local hover       = require("easytasks.lsp.hover")
local code_action = require("easytasks.lsp.code_action")
local doc_symbol  = require("easytasks.lsp.document_symbol")
local fmt         = require("easytasks.lsp.format")

-- ── Transport ─────────────────────────────────────────────────────────────────
local uv     = vim.uv
local stdin  = uv.new_pipe(false)
local stdout = uv.new_pipe(false)
stdin:open(0)
stdout:open(1)

-- ── Logger ───────────────────────────────────────────────────────────────────
local log = vim.lsp.log
log.info("easytasks-server", "server starting")

---@param obj table
local function write_msg(obj)
    local json = vim.json.encode(obj)
    stdout:write(("Content-Length: %d\r\n\r\n%s"):format(#json, json))
end

-- ── Server state ─────────────────────────────────────────────────────────────
---@type table<string, easytasks.LspBufferContext>
local documents = {}   -- uri → context (duck-typed LspBufferContext)
---@type table?
local schema    = nil
local _req_id   = 0    -- outgoing request counter (for workspace/applyEdit if needed)

-- ── Capabilities ─────────────────────────────────────────────────────────────
local INITIALIZE_RESULT = {
    capabilities = {
        textDocumentSync      = { openClose = true, change = 1 }, -- Full sync
        hoverProvider         = true,
        completionProvider    = { triggerCharacters = { ".", "[", '"', "=", " " } },
        codeActionProvider    = { codeActionKinds = { "quickfix", "refactor.extract" } },
        documentFormattingProvider      = true,
        documentRangeFormattingProvider = true,
        documentSymbolProvider          = true,
    },
    serverInfo = { name = "easytasks-toml", version = "0.1.0" },
}

-- ── Document helpers ──────────────────────────────────────────────────────────

---@param uri  string
---@param text string
local function update_document(uri, text)
    local lines  = vim.split(text, "\n", { plain = true })
    local parsed = parser.parse(text)
    local ctx    = {
        bufnr         = nil,
        schema        = schema,
        text          = text,
        lines         = lines,
        cst           = parsed.cst,
        parse_errors  = parsed.errors,
        data          = nil,
        decode_errors = {},
        decode_tree   = nil,
        parse_results = nil,
    }
    if parsed.cst then
        local decoded         = decoder.decode(parsed.cst)
        ctx.data          = decoded.data
        ctx.decode_errors = decoded.errors
        ctx.decode_tree   = decoded.decode_tree
    end
    documents[uri] = ctx

    -- Publish diagnostics as a notification (no round-trip needed).
    local diags = diagnostics.build(nil, ctx)
    write_msg({
        jsonrpc = "2.0",
        method  = "textDocument/publishDiagnostics",
        params  = { uri = uri, diagnostics = diags },
    })
end

-- ── Request / notification dispatch ─────────────────────────────────────────

---@param id     integer|string|nil
---@param result any
local function respond(id, result)
    if id == nil then return end
    write_msg({ jsonrpc = "2.0", id = id, result = result })
end

---@param id  integer|string|nil
---@param code integer
---@param message string
local function respond_err(id, code, message)
    if id == nil then return end
    write_msg({ jsonrpc = "2.0", id = id, error = { code = code, message = message } })
end

---@param uri string
---@return easytasks.LspBufferContext?
local function doc_ctx(uri)
    return documents[uri]
end

---@param msg table
local function dispatch(msg)
    local method = msg.method
    local id     = msg.id
    local params = msg.params or {}

    -- ── Lifecycle ────────────────────────────────────────────────────────────
    if method == "initialize" then
        local opts = params.initializationOptions
        if opts and opts.schema then
            local ok, s = pcall(vim.json.decode, opts.schema)
            if ok then
                schema = s
                log.info("easytasks-server", "schema loaded")
            else
                log.warn("easytasks-server", "schema decode failed")
            end
        else
            log.warn("easytasks-server", "no initializationOptions.schema")
        end
        respond(id, INITIALIZE_RESULT)
        log.info("easytasks-server", "initialize done")
        return
    end

    if method == "initialized" then return end   -- notification, no response

    if method == "shutdown" then
        respond(id, vim.NIL)
        return
    end

    if method == "exit" then
        uv.stop()
        return
    end

    -- ── Text synchronisation ─────────────────────────────────────────────────
    if method == "textDocument/didOpen" then
        update_document(params.textDocument.uri, params.textDocument.text)
        return
    end

    if method == "textDocument/didChange" then
        local changes = params.contentChanges
        if changes and #changes > 0 then
            -- change = 1 (Full): the last entry is the full text.
            update_document(params.textDocument.uri, changes[#changes].text)
        end
        return
    end

    if method == "textDocument/didClose" then
        documents[params.textDocument.uri] = nil
        return
    end

    -- ── Feature requests ─────────────────────────────────────────────────────
    local uri = params.textDocument and params.textDocument.uri
    if not uri then
        respond_err(id, -32602, "missing textDocument.uri")
        return
    end

    local ctx = doc_ctx(uri)
    if not ctx then
        -- Document not yet opened; send empty/nil response.
        respond(id, vim.NIL)
        return
    end

    local function cb(err, result)
        if err then
            respond_err(id, err.code or -32603, err.message or "internal error")
        else
            respond(id, result ~= nil and result or vim.NIL)
        end
    end

    if method == "textDocument/completion" then
        completion.handler(ctx, params, cb)
        return
    end

    if method == "textDocument/hover" then
        hover.handler(ctx, params, cb)
        return
    end

    if method == "textDocument/codeAction" then
        code_action.handler(ctx, params, cb)
        return
    end

    if method == "textDocument/formatting"
    or method == "textDocument/rangeFormatting" then
        fmt.handler(ctx, params, cb)
        return
    end

    if method == "textDocument/documentSymbol" then
        doc_symbol.handler(ctx, params, cb)
        return
    end

    if method == "workspace/executeCommand" then
        -- insertTemplate is handled client-side via vim.lsp.commands; nothing to do.
        respond(id, vim.NIL)
        return
    end

    -- Unknown request: respond with method-not-found.
    if id ~= nil then
        respond_err(id, -32601, "method not found: " .. tostring(method))
    end
end

-- ── stdin reader ─────────────────────────────────────────────────────────────
local _buf = ""

stdin:read_start(function(err, data)
    if err or not data then
        -- Client closed the connection.
        uv.stop()
        return
    end
    _buf = _buf .. data
    while true do
        -- Find the end of the header block.
        local hdr_end = _buf:find("\r\n\r\n", 1, true)
        if not hdr_end then break end
        local hdr = _buf:sub(1, hdr_end - 1)
        local len = tonumber(hdr:match("Content%-Length:%s*(%d+)"))
        if not len then
            -- Malformed header; skip past it.
            _buf = _buf:sub(hdr_end + 4)
        else
            local body_start = hdr_end + 4
            local body_end   = body_start + len - 1
            if #_buf < body_end then break end   -- wait for more data
            local body = _buf:sub(body_start, body_end)
            _buf = _buf:sub(body_end + 1)
            -- Dispatch on the main Neovim scheduler so vim.* APIs are safe.
            vim.schedule(function()
                local ok, msg = pcall(vim.json.decode, body)
                if ok and type(msg) == "table" then
                    dispatch(msg)
                end
            end)
        end
    end
end)

-- Drive the libuv event loop. This call blocks until uv.stop() is called
-- (from the "exit" handler above) or stdin is closed by the client.
uv.run()
