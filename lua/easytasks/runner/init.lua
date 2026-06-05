local exec = require("easytasks.runner.exec")

---@class easytasks.Runner
local M = {}

--- Run a named task from a Lua config file.
--- Non-blocking: execution is driven by coroutines and libuv callbacks.
---@param task_name string
---@param lua_path  string
function M.run(task_name, lua_path)
    exec.run(task_name, lua_path)
end

--- Stop a running task.
---@param task_name string
function M.stop(task_name)
    exec.stop(task_name)
end

--- Return the current execution state of a task.
---@param task_name string
---@return easytasks.TaskState
function M.state(task_name)
    return exec.state(task_name)
end

--- Return the ordered list of task names from a Lua tasks file, or nil + error string.
---@param lua_path string
---@return string[]?, string?
function M.list_tasks(lua_path)
    return exec.list(lua_path)
end

return M
