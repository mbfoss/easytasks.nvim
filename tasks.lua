-- easytasks.nvim task file. Returns a map of task name → task spec, each built
-- with a typed constructor from `require("easytasks.types")`. Field values may
-- be plain data or a function evaluated lazily at run time.
local types = require("easytasks.types")

--- The value a `tasks.lua` file returns: a map of task name → task spec.
--- Annotate the returned table with `---@type easytasks.Tasks` for completion.
---@alias easytasks.Tasks table<string, easytasks.BaseSpec>

---@type easytasks.Tasks
return {
    -- Run the plenary test suite.
    test = types.run {
        command = { "make", "test" },
    },

    -- Demonstrates a function-valued field (replaces the old `${file}` macro):
    -- echoes the absolute path of the current buffer when run.
    ["echo-file"] = types.run {
        command = function() return { "echo", vim.fn.expand("%:p") } end,
    },
}
