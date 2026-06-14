---@brief Debug task type for easytasks.nvim.
---Delegates execution to a configurable backend plugin (default: easytasks-debug.nvim).
---Other backends (e.g. nvim-dap) can be added by extending `_providers` and setting
---`cfg.debug_backend` in the user's easytasks setup().

local cfg = require("easytasks.config")

---@class easytasks.debug.Backend
---@field run       fun(task: table, ctx: easytasks.RunCtx, on_done: fun(ok: boolean)): fun()
---@field adapters? fun(): string[]
---@field templates? table[]

---@type table<string, fun(): easytasks.debug.Backend?>
local _providers = {
    ["easytasks-debug"] = function()
        local ok, m      = pcall(require, "easytasks-debug")
        local ok2, adaps = pcall(require, "easytasks-debug.adapters")
        if not ok then return nil end
        return {
            run      = m.run,
            adapters = ok2 and function()
                local names = vim.tbl_keys(adaps)
                table.sort(names)
                return names
            end or nil,
            templates = ok2 and require("easytasks-debug.task").templates or nil,
        }
    end,
}

---@return easytasks.debug.Backend?
local function _get_backend()
    local name     = cfg.current.debug_backend or "easytasks-debug"
    local provider = _providers[name]
    return provider and provider() or nil
end

local M = {}

---@param task    table
---@param ctx     easytasks.RunCtx
---@param on_done fun(ok: boolean)
---@return fun()
function M.start(task, ctx, on_done)
    local backend = _get_backend()
    if not backend then
        local name = cfg.current.debug_backend or "easytasks-debug"
        ctx.report("no debug backend available (backend: " .. name .. ")")
        on_done(false)
        return function() end
    end
    return backend.run(task, ctx, on_done)
end

M.schema = {
    description = "Definition of a `debug` task (runs via a DAP adapter)",
    ["x-order"] = {
        "name", "type", "if_running", "depends_on", "depends_order",
        "adapter", "request", "host", "port",
        "command", "args", "cwd", "env", "clear_env", "run_in_terminal", "stop_on_entry",
        "request_args", "raw_messages",
    },
    required   = { "adapter" },
    properties = {
        adapter         = {
            type        = "string",
            minLength   = 1,
            description = "Name of the DAP adapter to use (e.g. codelldb, delve, debugpy)",
            enum        = function()
                local b = _get_backend()
                return b and b.adapters and b.adapters() or {}
            end,
        },
        host            = {
            type        = { "string", "null" },
            minLength   = 1,
            description = "Hostname or IP address of the DAP server to connect to (attach only; overrides the adapter default)",
        },
        port            = {
            type        = { "integer", "null" },
            minimum     = 1,
            maximum     = 65535,
            description = "TCP port of the DAP server to connect to (attach only; required for `remote` adapter)",
        },
        request         = {
            description = "Whether to launch a new process or attach to a running one",
            oneOf       = {
                { type = "string", const = "launch", description = "Start the program under the debugger" },
                { type = "string", const = "attach", description = "Attach to an already-running process" },
            },
        },
        command         = {
            description = "Program to debug. A string is a plain path; an array is [program, arg1, …] shorthand (args are merged with `args` if also set)",
            oneOf       = {
                { type = "string", minLength = 1,               description = "Path to the executable" },
                { type = "array",  items = { type = "string" }, minItems = 1, description = "Executable followed by arguments" },
            },
        },
        cwd             = {
            type        = { "string", "null" },
            minLength   = 1,
            description = "Working directory for the debugged program",
        },
        env             = {
            type                 = { "object", "null" },
            description          = "Environment variables for the debugged program",
            additionalProperties = { type = "string" },
        },
        clear_env       = {
            type        = { "boolean", "null" },
            description = "Pass `env` verbatim without merging with the current process environment",
        },
        run_in_terminal = {
            type        = { "boolean", "null" },
            description = "Ask the DAP client to spawn an integrated terminal for the program's stdio",
        },
        stop_on_entry   = {
            type        = { "boolean", "null" },
            description = "Pause execution at the program's entry point before running any user code",
        },
        request_args    = {
            type                 = { "object", "null" },
            description          = "Arguments sent verbatim in the DAP launch or attach request (takes precedence over all generic fields above)",
            additionalProperties = true,
        },
        raw_messages    = {
            type        = { "boolean", "null" },
            description = "Capture all raw DAP protocol messages in a dedicated buffer attached to the task",
        },
    },
}

M.templates = function()
    local b = _get_backend()
    return b and b.templates or {}
end

return M --[[@as easytasks.TaskTypeDef]]
