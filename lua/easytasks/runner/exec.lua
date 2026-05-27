--- Task execution engine.
--- Handles TOML loading, dependency resolution, coroutine scheduling,
--- and task state tracking.
local async        = require("easytasks.util.async")
local Signal       = require("easytasks.util.Signal")
local parser       = require("easytasks.toml.parser")
local decoder      = require("easytasks.toml.decoder")
local task_types   = require("easytasks.types")
local notify       = require("easytasks.ui")

---@class easytasks.TaskTemplate
---@field label string  shown in vim.ui.select
---@field task  table   the template data to encode and insert

---@class easytasks.TaskTypeDef
---@field run       fun(task: table, ctx: easytasks.RunCtx): boolean
---@field schema    table?
---@field templates (easytasks.TaskTemplate[]|(fun(): easytasks.TaskTemplate[]))?

---@class easytasks.BufEntry
---@field bufnr integer
---@field label string

---@class easytasks.ProgressEvent
---@field time    integer  unix timestamp
---@field message string

---@class easytasks.RunProgress
---@field start_time integer              unix timestamp set when the run begins
---@field stop_time  integer?             unix timestamp set when the run reaches a terminal state
---@field events     easytasks.ProgressEvent[]

---@class easytasks.RunCtx
---@field tasks      table<string,table>
---@field add_bufnr  fun(bufnr: integer, label?: string)
---@field set_cancel fun(fn: fun())
---@field report     fun(message: string)

---@alias easytasks.TaskState "idle"|"running"|"waiting"|"ok"|"failed"|"stopped"

---@class easytasks.RunEntry
---@field task_name      string
---@field state          easytasks.TaskState
---@field waiting_for    string[]?
---@field progress       easytasks.RunProgress
---@field bufnrs         easytasks.BufEntry[]
---@field cancel         fun()?
---@field stop_requested boolean?
---@field done           easytasks.util.Signal<fun()>

---@class easytasks.exec
local M            = {}

---@type table<string, easytasks.RunEntry>
local _running     = {}
local _run_counter = 0

local function gen_run_id(task_name)
    _run_counter = _run_counter + 1
    return task_name .. "#" .. _run_counter
end

---@type easytasks.util.Signal<fun(run_id: string, entry: easytasks.RunEntry)>
local _on_state_change = Signal.new()

---@param fn fun(run_id: string, entry: easytasks.RunEntry)
function M.subscribe(fn) _on_state_change:subscribe(fn) end

---@param fn fun(run_id: string, entry: easytasks.RunEntry)
function M.unsubscribe(fn) _on_state_change:unsubscribe(fn) end

local function notify_change(run_id)
    local entry = _running[run_id]
    if entry then _on_state_change:emit(run_id, entry) end
end

---@return table<string, easytasks.RunEntry>
function M.get_all()
    return vim.tbl_extend("force", {}, _running)
end

-- ─── TOML loading ────────────────────────────────────────────────────────────

---@param toml_path string
---@return table<string,table>?, string?
local function load_tasks(toml_path)
    local lines = vim.fn.readfile(toml_path)
    if not lines then return nil, "cannot read " .. toml_path end
    local text    = table.concat(lines, "\n") .. "\n"
    local parsed  = parser.parse(text)
    local decoded = decoder.decode(parsed.cst)
    if not decoded.data or not decoded.data.tasks then
        return nil, "no tasks table in " .. toml_path
    end
    local by_name = {}
    for _, task in ipairs(decoded.data.tasks) do
        if task.name then by_name[task.name] = task end
    end
    return by_name, nil
end

-- ─── Cycle detection ─────────────────────────────────────────────────────────

---@param name    string
---@param tasks   table<string,table>
---@param visited table<string,boolean>
---@param stack   table<string,boolean>
---@return string?
local function find_cycle(name, tasks, visited, stack)
    if stack[name] then return name end
    if visited[name] then return nil end
    visited[name] = true
    stack[name]   = true
    local task    = tasks[name]
    if task and type(task.depends_on) == "table" then
        for _, dep in ipairs(task.depends_on) do
            local cycle = find_cycle(dep, tasks, visited, stack)
            if cycle then return name .. " → " .. cycle end
        end
    end
    stack[name] = false
    return nil
end

-- ─── Core execution ──────────────────────────────────────────────────────────

--- Run a single task (and its dependencies) as a coroutine.
--- Always creates and fully owns its RunEntry — entry is created synchronously
--- before the first yield, so it is visible to callers immediately.
--- Must be called from within a coroutine (via async.go).
---@param name     string
---@param tasks    table<string,table>
---@param run_id?  string  pre-existing run_id to reuse (e.g. a waiting entry)
---@return boolean ok
local function run_task_coro(name, tasks, run_id)
    local task = tasks[name]
    if not task then
        notify.notify_error("unknown task: " .. name)
        return false
    end

    ---@type easytasks.RunEntry
    local entry
    if run_id then
        entry                     = _running[run_id]
        entry.state               = "running"
        entry.waiting_for         = nil
        entry.progress.start_time = os.time()
    else
        run_id = gen_run_id(name)
        entry = {
            task_name = name,
            state     = "running",
            bufnrs    = {},
            done      = Signal.new(),
            progress  = { start_time = os.time(), events = {} },
        }
        _running[run_id] = entry
    end
    notify_change(run_id)

    local function event(msg)
        table.insert(entry.progress.events, { time = os.time(), message = msg })
        notify_change(run_id)
    end

    local function finish(state)
        entry.state              = state
        entry.progress.stop_time = os.time()
        entry.done:emit()
        notify_change(run_id)
        return state == "ok"
    end

    -- ── depends_on ──────────────────────────────────────────────────────────
    local deps = type(task.depends_on) == "table" and task.depends_on or {}
    if #deps > 0 then
        entry.state       = "waiting"
        entry.waiting_for = deps
        notify_change(run_id)

        local deps_ok
        if task.depends_order == "parallel" then
            local fns = vim.tbl_map(function(dep_name)
                return function() return run_task_coro(dep_name, tasks) end
            end, deps)
            local results = async.wait_all(fns)
            deps_ok = true
            for i, r in ipairs(results) do
                if not r.ok or not r.result then
                    deps_ok = false
                    event("dependency '" .. deps[i] .. "' failed")
                end
            end
        else
            deps_ok = true
            for _, dep_name in ipairs(deps) do
                local r = async.wait_one(function() return run_task_coro(dep_name, tasks) end)
                if not r.ok or not r.result then
                    deps_ok = false
                    event("dependency '" .. dep_name .. "' failed")
                    break
                end
            end
        end

        if not deps_ok then return finish("failed") end

        entry.state       = "running"
        entry.waiting_for = nil
        notify_change(run_id)
    end

    -- ── stop check (may have been requested while waiting for deps) ──────────
    if entry.stop_requested then return finish("stopped") end

    -- ── type-specific run ────────────────────────────────────────────────────
    local type_def = task_types.get_all()[task.type]
    if not type_def then
        event("unknown task type: " .. tostring(task.type))
        return finish("failed")
    end

    ---@type easytasks.RunCtx
    local ctx = {
        tasks      = tasks,
        set_cancel = function(fn) entry.cancel = fn end,
        report     = function(message) event(message) end,
        add_bufnr  = function(bufnr, label)
            table.insert(entry.bufnrs, { bufnr = bufnr, label = label or "output" })
            notify_change(run_id)
            vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
                buffer   = bufnr,
                once     = true,
                callback = function()
                    for i, be in ipairs(entry.bufnrs) do
                        if be.bufnr == bufnr then
                            table.remove(entry.bufnrs, i)
                            break
                        end
                    end
                    notify_change(run_id)
                end,
            })
        end,
    }

    local ok = type_def.run(task, ctx)

    if entry.stop_requested then return finish("stopped") end
    return finish(ok and "ok" or "failed")
end

-- ─── Internal launch ─────────────────────────────────────────────────────────

--- `run_task_coro` creates its entry synchronously before its first yield,
--- so the entry is live before launch returns.
---@param task_name string
---@param tasks     table<string,table>
---@param run_id?   string  pre-existing run_id to reuse (e.g. a waiting entry)
local function launch(task_name, tasks, run_id)
    async.go(function()
        return run_task_coro(task_name, tasks, run_id)
    end, function(co_ok, result)
        if co_ok then return end
        -- coroutine itself threw — mark any orphaned running entry as failed
        for rid, entry in pairs(_running) do
            if entry.task_name == task_name
                and (entry.state == "running" or entry.state == "waiting") then
                entry.state              = "failed"
                entry.progress.stop_time = os.time()
                entry.done:emit()
                notify_change(rid)
            end
        end
        notify.notify_error("task error: " .. task_name .. ": " .. tostring(result))
    end)
end

-- ─── Public ──────────────────────────────────────────────────────────────────

---@param task_name string
---@param toml_path string
function M.run(task_name, toml_path)
    local tasks, err = load_tasks(toml_path)
    if not tasks then
        notify.notify_error(err or "load error")
        return
    end

    local task = tasks[task_name]
    if not task then
        notify.notify_error("task not found: " .. task_name)
        return
    end

    local cycle = find_cycle(task_name, tasks, {}, {})
    if cycle then
        notify.notify_error("dependency cycle: " .. cycle)
        return
    end

    -- Collect any currently-active runs for this task
    local active_signals = {}
    for _, e in pairs(_running) do
        if e.task_name == task_name and (e.state == "running" or e.state == "waiting") then
            table.insert(active_signals, e.done)
        end
    end
    local is_running = #active_signals > 0

    if not is_running then
        launch(task_name, tasks)
        return
    end

    local policy = task.if_running or "refuse"

    if policy == "refuse" then
        notify.notify_warning("task already running: " .. task_name)
    elseif policy == "parallel" then
        launch(task_name, tasks)
    elseif policy == "wait" then
        local run_id = gen_run_id(task_name)
        _running[run_id] = {
            task_name = task_name,
            state     = "waiting",
            bufnrs    = {},
            done      = Signal.new(),
            progress  = { start_time = os.time(), events = {} },
        }
        notify_change(run_id)

        local fns = vim.tbl_map(function(sig)
            return function() async.wait_signal(sig) end
        end, active_signals)

        async.go(function() async.wait_all(fns) end, function()
            launch(task_name, tasks, run_id)
        end)
    elseif policy == "restart" then
        M.stop(task_name)

        local fns = vim.tbl_map(function(sig)
            return function() async.wait_signal(sig) end
        end, active_signals)

        async.go(function()
            if #fns > 0 then async.wait_all(fns) end
        end, function()
            launch(task_name, tasks)
        end)
    end
end

---@param toml_path string
---@return string[]?, string?
function M.list(toml_path)
    local tasks, err = load_tasks(toml_path)
    if not tasks then return nil, err end
    local names = vim.tbl_keys(tasks)
    table.sort(names)
    return names
end

--- Stop all active instances of a task.
---@param task_name string
function M.stop(task_name)
    for _, entry in pairs(_running) do
        if entry.task_name == task_name
            and (entry.state == "running" or entry.state == "waiting") then
            entry.stop_requested = true
            if entry.cancel then entry.cancel() end
        end
    end
end

--- Return the state of the most recent run for a task, or "idle" if none.
---@param task_name string
---@return easytasks.TaskState
function M.state(task_name)
    local best_n = -1
    local result = "idle" ---@type easytasks.TaskState
    for id, entry in pairs(_running) do
        if entry.task_name == task_name then
            if entry.state == "running" or entry.state == "waiting" then
                return "running"
            end
            local n = tonumber(id:match("#(%d+)$")) or 0
            if n > best_n then
                best_n = n
                result = entry.state
            end
        end
    end
    return result
end

return M
