local ordered = require("easytasks.util.table_util").ordered
local notify  = require("easytasks.ui")
local common  = require("easytasks.types.lua.common")

-- A `lua` task runs an inline Lua snippet given directly in the tasks file.
-- The chunk receives the run context as its sole vararg (`local ctx = ...`)
-- and runs in a restricted environment: only Lua's standard library, `vim`,
-- and the predefined `report`, `print`, `task`, are visible (see
-- common.ALLOWED). The chunk succeeds unless it raises an error or
-- explicitly returns `false`.
---@type easytasks.TaskTypeDef
local M = {
    ---@return fun()
    start = function(task, ctx, on_done)
        local script = task.script
        if type(script) ~= "string" or script == "" then
            notify.notify_error("lua task '" .. task.name .. "' has no script")
            on_done(false)
            return function() end
        end

        -- load reads, compiles, and reports a syntax error in one step; the
        -- chunk name uses the task name for readable error messages.
        local chunk, compile_err = load(script, "=" .. task.name)
        if not chunk then
            ctx.report("cannot load lua script: " .. tostring(compile_err))
            on_done(false)
            return function() end
        end

        common.run_chunk(chunk, ctx, task, on_done)
        return function() end
    end,

    schema = {
        description = "Definition of a `lua` task",
        ["x-order"] = { "type", "if_running", "depends_on", "depends_order", "save_buffers", "script" },
        required    = { "script" },
        properties  = {
            script = {
                type        = "string",
                minLength   = 1,
                description =
                "Inline Lua source executed in a restricted environment: Lua's standard library and `vim` are available, but plugin/extension globals and the `load`/`require`/`debug` escape hatches are not. The chunk receives the run context as its sole vararg (`local ctx = ...`); `report`, `print`, `task`, are predefined. The task fails if the chunk errors or returns `false`.",
            },
        },
    },

    templates = {
        {
            label = "Lua script",
            task  = ordered({ name = "lua", type = "lua", script = "" },
                { "name", "type", "script" }),
        },
    },
}

return M
