local ordered  = require("easytasks.util.table_util").ordered
local notify   = require("easytasks.ui")
local project  = require("easytasks.project")
local common   = require("easytasks.types.lua.common")

--- Resolve a (possibly relative) task file path against the project root.
---@param path string
---@return string
local function _resolve(path)
    path = vim.fs.normalize(path)
    if vim.fn.fnamemodify(path, ":p") == path then
        return path -- already absolute
    end
    local root = project.find_root()
    return root and vim.fs.normalize(vim.fs.joinpath(root, path)) or path
end

-- A `lua_file` task runs a Lua script file referenced from the tasks file.
-- The chunk receives the run context as its sole vararg (`local ctx = ...`)
-- and runs in a restricted environment: only Lua's standard library, `vim`,
-- and the predefined `report`, `print`, `task`, are visible (see
-- common.ALLOWED). The chunk succeeds unless it raises an error or
-- explicitly returns `false`.
---@type easytasks.TaskTypeDef
local M = {
    ---@return fun()
    start = function(task, ctx, on_done)
        local file = task.file
        if type(file) ~= "string" or file == "" then
            notify.notify_error("lua_file task '" .. task.name .. "' has no file")
            on_done(false)
            return function() end
        end

        local path = _resolve(file)
        -- loadfile reads, compiles, and reports a missing/unreadable file in one
        -- step; the chunk name defaults to the path for readable error messages.
        local chunk, compile_err = loadfile(path)
        if not chunk then
            ctx.report("cannot load lua file: " .. tostring(compile_err))
            on_done(false)
            return function() end
        end

        common.run_chunk(chunk, ctx, task, on_done)
        return function() end
    end,

    schema = {
        description = "Definition of a `lua_file` task",
        ["x-order"] = { "type", "if_running", "depends_on", "depends_order", "save_buffers", "file" },
        required    = { "file" },
        properties  = {
            file = {
                type        = "string",
                minLength   = 1,
                description =
                "Path to a Lua script file to execute in a restricted environment: Lua's standard library and `vim` are available, but plugin/extension globals and the `load`/`require`/`debug` escape hatches are not. Relative paths are resolved against the project root (the directory containing the tasks file). The chunk receives the run context as its sole vararg (`local ctx = ...`); `report`, `print`, `task`, are predefined. The task fails if the chunk errors or returns `false`.",
            },
        },
    },

    templates = {
        {
            label = "Lua script file",
            task  = ordered({ name = "lua_file", type = "lua_file", file = "" },
                { "name", "type", "file" }),
        },
    },
}

return M
