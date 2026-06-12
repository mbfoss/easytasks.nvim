local M = {}

---@class easytasks.Config
---@field enabled boolean
---@field command string
---@field tasks_filename string
---@field storage_dir string
---@field save_buffers easytasks.SaveBuffersConfig

---@return easytasks.Config
function M.default()
    return {
        enabled        = true,
        command        = "Tasks",
        tasks_filename = "tasks.toml",
        storage_dir    = ".easytasks",
        save_buffers     = {
            include_globs = {},
            exclude_globs = {},
        },
    }
end

---@type easytasks.Config
M.current = M.default()

return M
