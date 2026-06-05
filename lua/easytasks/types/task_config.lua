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

---@class easytasks.BaseTaskConfig
---@field name         string                   Unique task name
---@field type         string                   Task type: "process" | "composite"
---@field depends_on?  string[]                 Tasks that must complete before this one runs
---@field depends_order? easytasks.DependsOrder How dependencies are executed (default: "sequence")
---@field if_running?  easytasks.IfRunning      Behaviour when this task is already active (default: "refuse")

---@class easytasks.ProcessTaskConfig : easytasks.BaseTaskConfig
---@field type         "process"
---@field command      string                   Shell command to execute
---@field cwd?         string                   Working directory (default: project root)
---@field env?         table<string,string>      Extra environment variables
---@field quickfix_matcher? easytasks.QfMatcherName|string  Parse stdout/stderr into the quickfix list

---@class easytasks.CompositeTaskConfig : easytasks.BaseTaskConfig
---@field type "composite"

---@alias easytasks.TaskConfig easytasks.ProcessTaskConfig|easytasks.CompositeTaskConfig
