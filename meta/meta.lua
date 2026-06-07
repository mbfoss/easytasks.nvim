-- User-facing type definitions for tasks.lua files.
-- This file exists purely for its EmmyLua annotations.
-- lazydev.nvim / neodev.nvim automatically add plugin lua/ dirs to the
-- lua-language-server library, making these types available in any Lua file.
--
-- Usage in your tasks.lua:
--   ---@type easytasks.TaskConfig[]
--   return {
--     { name = "build", type = "process", command = "make" },
--   }
--
-- Extension authors: re-declare easytasks.TaskType and easytasks.TaskConfig
-- in your own meta file to register new type values and fields.
-- lua-ls merges class re-declarations; alias re-declarations require a
-- diagnostic suppression comment.
--
--   ---@diagnostic disable: duplicate-doc-alias
--   ---@alias easytasks.TaskType
--   ---| "docker"
--
--   ---@class easytasks.TaskConfig
--   ---@field docker_image? string Docker image to run in

---@alias easytasks.IfRunning
---| "refuse"   # Warn and do nothing (default)
---| "parallel" # Launch a new parallel instance
---| "wait"     # Queue this run until the current one finishes
---| "restart"  # Stop the current run, then re-launch

---@alias easytasks.DependsOrder
---| "sequence" # Run dependencies one after another (default)
---| "parallel" # Run all dependencies concurrently

---@alias easytasks.QfMatcherName
---| "gcc"     # GCC / Clang: file:line:col: severity: message
---| "tsc"     # TypeScript compiler: file(line,col): message
---| "python"  # Python traceback: File "file", line N
---| "go"      # Go compiler: file:line:col: message
---| "pytest"  # pytest / unittest: file.py:line: message
---| "cargo"   # Rust / Cargo: --> file:line:col
---| "gotest"  # Go test output: file_test.go:line: message
---| "msvc"    # MSVC: file(line): error/warning CXXX: message
---| "linter"  # Generic linter (Pylint, ESLint, Flake8, Mypy)
---| "unix"    # Generic Unix: file:line:col: message

-- Extensible task type enum. Re-declare this alias in your meta file to add
-- new values without breaking validation on existing ones.
---@alias easytasks.TaskType
---| "process"
---| "composite"

-- User-facing config type. Re-declare this class in your meta file to add
-- fields for your custom task type.
---@class (exact) easytasks.TaskConfig
---@field name           string                          Unique task name
---@field type           easytasks.TaskType              Task type
---@field depends_on?    string[]                        Tasks that must complete before this one runs
---@field depends_order? easytasks.DependsOrder          How dependencies are executed (default: "sequence")
---@field if_running?    easytasks.IfRunning             Behaviour when this task is already active (default: "refuse")
---@field command?       string                          (process) Shell command to execute
---@field cwd?           string                          (process) Working directory (default: project root)
---@field env?           table<string,string>            (process) Extra environment variables
---@field quickfix_matcher? easytasks.QfMatcherName|string  (process) Parse stdout/stderr into the quickfix list

-- Internal concrete types — used for narrowing inside the plugin after
-- checking task.type. Not intended for direct use in tasks.lua files.

---@class easytasks.ProcessTaskConfig : easytasks.TaskConfig
---@field type    "process"
---@field command string

---@class easytasks.CompositeTaskConfig : easytasks.TaskConfig
---@field type "composite"
