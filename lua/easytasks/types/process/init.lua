local term       = require("easytasks.types.process.term")
local spawn      = require("easytasks.types.process.spawn").spawn
local _notify    = require("easytasks.ui")
local qfmatchers = require("easytasks.types.process.qfmatchers")

---@type table<string, easytasks.QfMatcher>
local _user_matchers = {}

---@param s string
---@return string
local function strip_ansi(s)
    return (s:gsub("\27%[[%d;]*[A-Za-z]", ""))
end

---@param name string?
---@return (fun(line: string): easytasks.QfItem?)?, string?
local function make_qf_parser(name)
    if not name or name == "" then return nil end
    local fn = _user_matchers[name] or qfmatchers[name]
    if not fn then return nil, "unknown quickfix matcher: " .. name end
    local ctx = {}
    return function(line) return fn(strip_ansi(line), ctx) end
end

--- Register a custom quickfix matcher for process tasks.
---@param name string
---@param fn   easytasks.QfMatcher
local function register_qfmatcher(name, fn)
    _user_matchers[name] = fn
end

---@type easytasks.TaskTypeDef & { register_qfmatcher: fun(name: string, fn: easytasks.QfMatcher) }
local M = {
    register_qfmatcher = register_qfmatcher,

    run = function(task, ctx, on_done)
        if not task.command then
            _notify.notify_error("process task '" .. task.name .. "' has no command")
            on_done(false)
            return
        end

        local qf_parse, qf_err = make_qf_parser(task.quickfix_matcher)
        if qf_err then
            _notify.notify_error(qf_err)
            on_done(false)
            return
        end

        if qf_parse then
            vim.fn.setqflist({}, "r")
        end

        local bufnr = term.open(task.name)
        ctx.add_bufnr(bufnr)

        local on_data
        if qf_parse then
            on_data = function(_, data)
                vim.schedule(function()
                    if not data then return end
                    local items = {}
                    for _, line in ipairs(data) do
                        if line ~= "" then
                            local qf_item = qf_parse(line)
                            if qf_item then items[#items + 1] = qf_item end
                        end
                    end
                    if #items > 0 then vim.fn.setqflist(items, "a") end
                end)
            end
        end

        local handle = spawn(task.command, { cwd = task.cwd, env = task.env, on_stdout = on_data, on_stderr = on_data },
            bufnr)
        ctx.set_cancel(function() handle.stop() end)
        handle.on_exit(function(code) on_done(code == 0) end)
    end,
}

return M
