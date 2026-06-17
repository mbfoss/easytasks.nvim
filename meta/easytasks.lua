---@meta easytasks

--- These classes/aliases intentionally mirror lua/easytasks/annotations.lua
--- (see CLAUDE.md). `Lua.workspace.ignoreDir` excludes meta/ from this repo's
--- own workspace scan, but opening a meta/ file directly still loads it
--- alongside annotations.lua, so lua_ls flags the mirrored fields/aliases as
--- duplicates. Suppressed since the duplication itself is by design.
---@diagnostic disable: duplicate-doc-field, duplicate-doc-alias

--- Public type definitions for authoring `tasks.lua` and configuring
--- easytasks.nvim, packaged as a curated lua-language-server library.
---
--- Point lua_ls at *this directory* — never at the plugin's `lua/` — so the
--- typed task constructors and `require("easytasks")` get completion and
--- diagnostics WITHOUT the plugin's internal `---@class` definitions leaking
--- into your `tasks.lua` completion. In a project's `.luarc.json`:
---
---     "workspace.library": [ "/path/to/easytasks.nvim/meta" ]
---
--- Every task field below may also be a function
--- `fun(ctx: easytasks.ValueCtx): any` evaluated lazily at run time (this
--- replaces the old `${…}` macros); see the `easytasks.providers` helpers.

-- ─── Task specs ────────────────────────────────────────────────────────────────

--- Context passed to any function-valued task field when it is resolved.
---@class easytasks.ValueCtx
---@field task  table                 the task being resolved (pre-resolution)
---@field tasks table<string, table>  all tasks declared in the file, by name

--- Fields shared by every task type.
---@class easytasks.BaseSpec
---@field name?               string  Defaults to the map key used in `tasks.lua`
---@field type?                string  Set by the constructor; not normally written by hand
---@field if_running?          "wait"|"restart"|"refuse"|"parallel"  What to do when an instance is already running
---@field depends_on?          string[]  Tasks that must complete successfully first
---@field depends_order?       "sequence"|"parallel"  How `depends_on` tasks are run
---@field pre_launch_actions?  table[]  Actions run, in order, after dependencies resolve and before the task starts; any failure aborts the task

--- A `run` (process) task.
---@class easytasks.RunSpec : easytasks.BaseSpec
---@field command           string|string[]|fun(ctx: easytasks.ValueCtx): string|string[]  Command to execute
---@field shell?            boolean  Pass the command string to the shell instead of executing it directly
---@field cwd?              string|fun(ctx: easytasks.ValueCtx): string  Working directory
---@field env?              table<string, string>  Environment variables
---@field quickfix_matchers? easytasks.QfMatcher[]  Matchers used to parse output into the quickfix list, tried in order; see `easytasks.quickfix_matchers`

--- A `composite` task: behaviour is entirely its `depends_on` resolution.
---@class easytasks.CompositeSpec : easytasks.BaseSpec

--- The value a `tasks.lua` file returns: a map of task name → task spec.
--- Annotate the returned table with `---@type easytasks.Tasks` for completion.
---@alias easytasks.Tasks table<string, easytasks.BaseSpec>

--- A `debug` task, run through a DAP backend (`config.debug_backend`).
---@class easytasks.DebugSpec : easytasks.BaseSpec
---@field adapter          string  Name of the DAP adapter (e.g. codelldb, delve, debugpy)
---@field request?         "launch"|"attach"
---@field host?            string  DAP server host (attach)
---@field port?            integer  DAP server port (attach)
---@field command?         string|string[]  Program to debug
---@field cwd?             string  Working directory for the debugged program
---@field env?             table<string, string>
---@field clear_env?       boolean
---@field run_in_terminal? boolean
---@field stop_on_entry?   boolean
---@field request_args?    table  Arguments sent verbatim in the DAP request
---@field raw_messages?    boolean

-- ─── providers: dynamic value providers ──────────────────────────────────────

--- Convenience builders for dynamic task field values (`require("easytasks").providers`).
--- Each returns a `fun(ctx): any, string?` to use directly as a field value.
---@class easytasks.providers
local providers = {}

--- Absolute path of the current buffer (`%:p`).
---@param filetype string?  if given, error unless the current file has this filetype
---@return fun(): string?, string?
function providers.file(filetype) end

--- Tail of the current buffer's name (`%:t`).
---@param filetype string?
---@return fun(): string?, string?
function providers.filename(filetype) end

--- Current buffer path without extension (`%:p:r`).
---@param filetype string?
---@return fun(): string?, string?
function providers.fileroot(filetype) end

--- Directory of the current buffer (`%:p:h`).
---@return fun(): string?, string?
function providers.filedir() end

--- Extension of the current buffer (`%:e`), or nil if none.
---@return fun(): string?, string?
function providers.fileext() end

--- The task's own `cwd` if it set one, else the resolved current working dir.
---@return fun(ctx: easytasks.ValueCtx): string
function providers.cwd() end

--- The project root (the cwd, asserting the tasks file lives there).
---@return fun(): string?, string?
function providers.projectdir() end

--- Value of environment variable `varname`, or nil if unset.
---@param varname string
---@return fun(): string?, string?
function providers.env(varname) end

--- Prompt the user for a value via `vim.ui.input`.
---@param prompt_text string
---@param default string?
---@param completion string?  e.g. "file" or "dir" (resolves relative paths)
---@return fun(): string?, string?
function providers.prompt(prompt_text, default, completion) end

--- Let the user pick a running process; resolves to its PID.
---@return fun(): string?, string?
function providers.select_pid() end

-- ─── actions: pre-launch action constructors ─────────────────────────────────

--- Constructors for `pre_launch_actions` entries (`require("easytasks").actions`).
--- Each constructor tags the spec with its `type` and returns it. A custom
--- action registered via `require("easytasks").register_action(name, …)` is
--- also callable as `actions.<name> { … }`.
---@class easytasks.actions
local actions = {}

--- Save modified project buffers before the task starts.
---@param spec { include?: string[], exclude?: string[], include_hidden?: boolean }?
---@return table
function actions.save_buffers(spec) end

-- ─── quickfix matchers ────────────────────────────────────────────────────────

---@class easytasks.QfItem
---@field filename string
---@field lnum     integer
---@field col      integer
---@field text     string?
---@field type     string?

---@alias easytasks.QfMatcher fun(line: string, context: table): easytasks.QfItem?

--- Built-in matchers plus any registered via `register_qfmatcher`
--- (`require("easytasks").quickfix_matchers` inside a `tasks.lua`, or
--- `easytasks.quickfix_matchers` as the injected global). Reference entries
--- directly in `RunSpec.quickfix_matchers`, e.g. `easytasks.quickfix_matchers.gcc`.
---@class easytasks.QfMatchers
---@field gcc     easytasks.QfMatcher  GCC / Clang
---@field tsc     easytasks.QfMatcher  TypeScript compiler
---@field python  easytasks.QfMatcher  Python tracebacks
---@field go      easytasks.QfMatcher  Go compiler
---@field pytest  easytasks.QfMatcher  pytest
---@field cargo   easytasks.QfMatcher  Rust / Cargo
---@field gotest  easytasks.QfMatcher  go test
---@field msvc    easytasks.QfMatcher  MSVC
---@field linter  easytasks.QfMatcher  generic `file:line:col: message` linters
---@field unix    easytasks.QfMatcher  generic `file:line: message`

-- ─── Extension-point aliases ─────────────────────────────────────────────────────
-- Loosely typed on purpose: the precise internal classes are intentionally not
-- exposed through this public library.

---@alias easytasks.TypeLoader string|table|fun(): table
---@alias easytasks.ActionLoader string|fun(action: table, ctx: table): boolean, string?
---@alias easytasks.debug.BackendDef table|fun(): table?

---@class easytasks.Config
---@field enabled?        boolean
---@field command?        string   User command name (default "Tasks")
---@field tasks_filename? string   Per-project Lua task file (default "tasks.lua")
---@field storage_dir?    string
---@field debug_backend?  string   Name of the debug backend (default "easydap")

-- ─── tasks.lua global ────────────────────────────────────────────────────────
-- Injected into a `tasks.lua` file's environment when it is run via `:Tasks`
-- (see runner/exec.lua), so authoring needs no `require("easytasks")`:
--
--     return {
--       build = easytasks.types.run { command = "make" },
--     }
--
-- Only available inside `tasks.lua` itself, not in modules it `require`s.
-- Deliberately just the authoring surface, not the full `easytasks` module:
-- lifecycle/extension methods (`setup`, `enable`, `register_task_type`, …)
-- belong in your init.lua via `require("easytasks")`, not in a task file.

---@class easytasks.TasksFileGlobal
---@field types             easytasks.types      Task constructors (`easytasks.types.run { … }`)
---@field providers         easytasks.providers  Dynamic value providers for task field values
---@field actions           easytasks.actions    Pre-launch action constructors (`easytasks.actions.save_buffers { … }`)
---@field quickfix_matchers easytasks.QfMatchers Built-in + registered quickfix matchers (`easytasks.quickfix_matchers.gcc`)
---@type easytasks.TasksFileGlobal
easytasks = nil


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

