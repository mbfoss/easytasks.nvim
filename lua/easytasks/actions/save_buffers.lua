local project      = require("easytasks.project")
local save_buffers  = require("easytasks.util.save_buffers")

--- Spec for the built-in `save_buffers` action: saves modified project
--- buffers before the task starts.
---@class easytasks.SaveBuffersSpec
---@field type?           string  Set by the constructor; not normally written by hand
---@field include?        string[]
---@field exclude?        string[]
---@field include_hidden? boolean

--- Normalize a `save_buffers` action spec into a SaveBuffersConfig.
---@param action easytasks.SaveBuffersSpec
---@return easytasks.SaveBuffersConfig
local function _config(action)
    return {
        include_globs  = action.include or {},
        exclude_globs  = action.exclude or {},
        include_hidden = action.include_hidden or false,
    }
end

--- Save modified project buffers, reporting which files were saved. No-op
--- when not in a project or nothing matched.
---@type easytasks.ActionFn
return function(action, ctx)
    local root = project.find_root()
    if not root then return true end
    local n, paths = save_buffers.save(root, _config(action))
    if n == 0 then return true end
    local lines = { ("saved %d file%s:"):format(n, n == 1 and "" or "s") }
    for i = 1, math.min(n, 5) do lines[#lines + 1] = "  " .. paths[i] end
    if n > 5 then lines[#lines + 1] = ("  … and %d more"):format(n - 5) end
    ctx.report(table.concat(lines, "\n"))
    return true
end
