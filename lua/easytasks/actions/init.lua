--- A pre-launch action: a named, registrable behavior run (in order) after a
--- task's dependencies resolve and before it starts, via `pre_launch_actions`.
--- Unlike a task type, an action has no `validate`/`templates`/`dispose`, so a
--- resolved entry is just a function rather than a wrapping table.
---@alias easytasks.ActionFn fun(action: table, ctx: easytasks.RunCtx): boolean, string?

---@alias easytasks.ActionLoader string|easytasks.ActionFn

---@class easytasks.Actions
local M = {}

---@type table<string, easytasks.ActionLoader>
local _loaders = {}

---@type table<string, easytasks.ActionFn>
local _cache = {}

---@param name string
---@return easytasks.ActionFn?
local function _resolve(name)
    if _cache[name] then return _cache[name] end
    local loader = _loaders[name]
    if loader == nil then return nil end
    local fn ---@type easytasks.ActionFn
    if type(loader) == "string" then
        fn = require(loader)
    else
        fn = loader
    end
    _cache[name] = fn
    return fn
end

--- Register a pre-launch action.
--- `loader` may be a module path string or the action function itself.
---@param name   string
---@param loader easytasks.ActionLoader
function M.register(name, loader)
    _loaders[name] = loader
    _cache[name]   = nil
end

--- Return the resolved action function for `name`, or nil if unknown.
---@param name string
---@return easytasks.ActionFn?
function M.get(name)
    return _resolve(name)
end

--- Return all registered action names without resolving any loaders.
---@return string[]
function M.get_names()
    return vim.tbl_keys(_loaders)
end

-- Built-in actions (loaded lazily on first use)
M.register("save_buffers", "easytasks.actions.save_buffers")

-- ─── Action constructors ─────────────────────────────────────────────────────
-- Authoring API used in `tasks.lua` (`easytasks.actions.save_buffers { … }`).
-- Each constructor tags the spec with its `type` and returns it. The
-- metatable below produces a constructor for any other *registered* action
-- on demand (`actions.myaction { … }`).

---@param spec easytasks.SaveBuffersSpec?
---@return easytasks.SaveBuffersSpec
function M.save_buffers(spec)
    spec      = spec or {}
    spec.type = "save_buffers"
    return spec
end

setmetatable(M, {
    __index = function(_, key)
        if type(key) ~= "string" or _loaders[key] == nil then return nil end
        return function(spec)
            spec      = spec or {}
            spec.type = key
            return spec
        end
    end,
})

return M
