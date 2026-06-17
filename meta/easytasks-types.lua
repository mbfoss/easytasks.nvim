---@meta easytasks.types

--- Task constructors for authoring `tasks.lua`:
---
---     local types = require("easytasks.types")
---
---     ---@type easytasks.Tasks
---     return {
---       build = types.run { command = "make" },
---       test  = types.run { command = "make test", depends_on = { "build" } },
---     }
---
--- Each constructor tags the spec with its `type` and returns it. A custom task
--- type registered via `require("easytasks").register_task_type(name, …)` is
--- also callable as `types.<name> { … }`.
---@class easytasks.types
local types = {}

--- Construct a `run` (process) task.
---@param spec easytasks.RunSpec
---@return easytasks.RunSpec
function types.run(spec) end

--- Construct a `composite` task (behaviour is its `depends_on` resolution).
---@param spec easytasks.CompositeSpec
---@return easytasks.CompositeSpec
function types.composite(spec) end

--- Construct a `debug` task, run through a DAP backend.
---@param spec easytasks.DebugSpec
---@return easytasks.DebugSpec
function types.debug(spec) end

--- Generic constructor for a task of any registered `type` (escape hatch for
--- custom types without a dedicated builder).
---@param type string
---@param spec table?
---@return table
function types.task(type, spec) end

--- Register a custom task type, afterwards callable as `types.<name> { … }`.
---@param name   string
---@param loader easytasks.TypeLoader
function types.register(name, loader) end

return types
