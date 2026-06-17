local term       = require("easytasks.util.term")
local notify     = require("easytasks.ui")
local qfmatchers = require("easytasks.types.run.qfmatchers")
local str_util   = require("easytasks.util.str_util")

--- Built-in matchers plus any registered via `register_qfmatcher`, exposed as
--- the `easytasks.quickfix_matchers` tasks-file global (e.g.
--- `easytasks.quickfix_matchers.gcc`). Registering under an existing name
--- overrides the built-in.
---@type table<string, easytasks.QfMatcher>
local _matchers = vim.tbl_extend("force", {}, qfmatchers)

---@param s string
---@return string
local function _strip_ansi(s)
    return (s:gsub("\27%[[%d;]*[A-Za-z]", ""))
end

--- Combine a task's `quickfix_matchers` (a list of matcher functions) into a
--- single per-line parser: each matcher gets its own state `ctx`, tried in
--- declared order, first non-nil result wins.
---@param qf_matchers easytasks.QfMatcher[]?
---@return (fun(line: string): easytasks.QfItem?)?
local function _make_qf_parser(qf_matchers)
    if type(qf_matchers) ~= "table" or #qf_matchers == 0 then return nil end
    local wrapped = {}
    for _, fn in ipairs(qf_matchers) do
        local ctx = {}
        wrapped[#wrapped + 1] = function(line) return fn(line, ctx) end
    end
    return function(line)
        line = _strip_ansi(line)
        for _, fn in ipairs(wrapped) do
            local item = fn(line)
            if item then return item end
        end
        return nil
    end
end

--- Register a custom quickfix matcher for run tasks.
---@param name string
---@param fn   easytasks.QfMatcher
local function _register_qfmatcher(name, fn)
    _matchers[name] = fn
end

---@type easytasks.TaskTypeDef & { register_qfmatcher: fun(name: string, fn: easytasks.QfMatcher), matchers: table<string, easytasks.QfMatcher> }
local M = {
    register_qfmatcher = _register_qfmatcher,
    matchers = _matchers,

    dispose = function(bufnrs)
        for _, be in ipairs(bufnrs) do
            if vim.api.nvim_buf_is_valid(be.bufnr) then
                pcall(vim.api.nvim_buf_delete, be.bufnr, { force = true })
            end
        end
    end,

    ---@return fun()
    start = function(task, ctx, on_done)
        if not task.command then
            notify.notify_error("run task '" .. task.name .. "' has no command")
            on_done(false)
            return function() end
        end

        local qf_parse = _make_qf_parser(task.quickfix_matchers)

        if qf_parse then
            vim.fn.setqflist({}, "r")
        end

        -- Resolve command into the form vim.fn.jobstart expects.
        local cmd
        if task.shell then
            if type(task.command) ~= "string" then
                notify.notify_error("run task '" .. task.name .. "': shell mode requires a string command")
                on_done(false)
                return function() end
            end
            cmd = task.command
        else
            if type(task.command) == "string" then
                cmd = str_util.split_shell_args(task.command)
                if #cmd == 0 then
                    notify.notify_error("run task '" .. task.name .. "': command string is empty")
                    on_done(false)
                    return function() end
                end
            else
                cmd = task.command
            end
        end

        local cmd_exe = type(cmd) == "string" and cmd:match("^%S+") or cmd[1] or nil
        local label = cmd_exe and vim.fn.fnamemodify(cmd_exe, ":t") or nil

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

        local handle, spawn_err = term.spawn(cmd, {
            cwd       = task.cwd,
            env       = task.env,
            on_stdout = on_data,
            on_stderr = on_data,
            on_exit   = function(code) on_done(code == 0) end,
        })

        if not handle then
            vim.schedule(function()
                ctx.report("job start failed: " .. tostring(spawn_err))
                on_done(false)
            end)
            return function() end
        end
        ctx.add_bufnr(handle.bufnr, label)
        return function() handle.stop() end
    end,

    ---@param task table
    ---@return boolean ok, string? err
    validate = function(task)
        local c = task.command
        if c == nil then
            return false, "run task '" .. tostring(task.name) .. "' has no `command`"
        end
        if type(c) ~= "string" and type(c) ~= "table" then
            return false, "run task '" .. tostring(task.name) .. "': `command` must be a string or array"
        end
        if task.quickfix_matchers ~= nil then
            if type(task.quickfix_matchers) ~= "table" then
                return false, "run task '" .. tostring(task.name) .. "': `quickfix_matchers` must be an array"
            end
            for i, m in ipairs(task.quickfix_matchers) do
                if type(m) ~= "function" then
                    return false, ("run task '%s': quickfix_matchers[%d] is not a function"):format(
                        tostring(task.name), i)
                end
            end
        end
        return true
    end,

    templates = {
        {
            label = "Process",
            spec  = { name = "run", type = "run", command = "" },
        },
        {
            label = "Shell command",
            spec  = { name = "command", type = "run", shell = true, command = "" },
        },
    },
}

return M
