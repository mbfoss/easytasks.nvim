# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make test                                        # run all tests (requires plenary.nvim)
nvim -l tests/run_decoder.lua < file.toml        # run TOML decoder against toml-test suite input
nvim -l tests/run_encoder.lua < file.toml        # run TOML encoder against toml-test suite input
```

Tests live in `tests/` and are discovered automatically by Plenary/Busted. `tests/init.lua` clones plenary to `/tmp/plenary.nvim` if not present (override with `NVIM_PLENARY_DIR`).

## Architecture

**easytasks.nvim** is a Neovim plugin for running TOML-defined tasks. It has three concerns: schema/LSP (delegated to `tomltools.nvim`), a task runner, and per-project persistent storage.

`lua/easytasks/init.lua` is the public API — `setup()` initialises the project tracker and registers a FileType autocmd that attaches the tomltools LSP to any buffer whose filename matches `tasks_filename`. The schema passed to the LSP is built lazily from the type registry. Public extension points: `register_task_type`, `register_macro`, `register_qfmatcher`.

### Type registry and schema (`types/`)

`types/init.lua` is a lazy registry: loaders (module path string, factory function, or bare table) are stored in `_loaders`; `_cache` holds resolved `TaskTypeDef` tables. `types/schema.lua` builds the full JSON Schema from all registered types using `if/then` conditionals keyed on `type`, so each type value produces a different set of allowed fields without duplication.

`schema.base_properties` holds fields shared by every task (`name`, `if_running`, `depends_on`, `depends_order`). Type-specific properties are merged in during `build()`. Schema fields whose value is a function (`enum = function() ... end`) are evaluated by `build_resolved_schema()` before the schema is JSON-encoded for the LSP — this is the mechanism for dynamic enum lists (e.g. quickfix matcher names).

Built-in types:
- **`run`** (`types/run/init.lua`) — executes a command in a terminal buffer. Supports `shell` (bool), `command` (string or array), `cwd`, `env`, `quickfix_matcher`, and `save_buffers`. When `save_buffers = true`, calls `types/run/save_buffers.lua:save()` before launching the command and reports the saved file list via `ctx.report`. Quickfix matchers live in `types/run/qfmatchers.lua` and can be extended with `register_qfmatcher`.
- **`composite`** (`types/composite.lua`) — no command; exists purely so `depends_on` can group other tasks.

### Runner (`runner/`)

`runner/exec.lua` is the execution engine. It manages `_running`, a table of `RunEntry` objects keyed by `run_id` (auto-incrementing string). Each `run()` call launches an `async.go` coroutine that:
1. Checks `if_running` policy against any existing run for the same task name.
2. Resolves dependency tasks (serially or in parallel via `depends_order`), waiting on their `done` Signal.
3. Calls `resolver.resolve_macros` to expand `${...}` placeholders in the decoded task table.
4. Looks up the `TaskTypeDef` and calls `td.start(task, ctx, on_done)`.

State transitions and progress messages are broadcast via two `Signal`s: `_on_state_change` and `_on_report`. The status panel subscribes to both. `ctx.report(msg)` appends a timestamped `ProgressEvent` and fires `_on_report`.

`runner/resolver.lua` walks string/table values recursively, expanding `${name}` and `${name:arg1,arg2,...}`. Expansion runs inside the coroutine; yielding macros (like `prompt`) are called via `_async_call` which suspends the coroutine and resumes it from `vim.schedule`.

### Macro system (`macros.lua`)

A plain table of `fun(ctx: easytasks.MacroCtx, ...): any, string?` functions. Built-ins: `file`, `filename`, `fileroot`, `filedir`, `fileext`, `cwd`, `projectdir`, `env`, `prompt`, `select-pid`. `ctx` carries `task` (decoded task data) and `tasks` (all tasks). Register custom macros with `easytasks.register_macro(name, fn)`. Macro syntax in TOML values: `${name}` or `${name:arg1,arg2}`.

### Project detection and storage (`project.lua`, `datastore.lua`)

`project.find_root()` checks whether `cfg.current.tasks_filename` exists in the current working directory — no upward search. Storage is initialised in `project.init()` via three autocmds: `DirChangedPre` flushes pending writes and emits `on_project_leave_pre`; `DirChanged` re-detects the root and emits `on_project_enter` or `on_project_leave`; `VimLeavePre` flushes and emits `on_project_leave_pre`.

`datastore.lua` is the merge-write layer. Data lives in `<storage_dir>/<namespace>.json`. `add`/`remove` stage individual key mutations; `set` stages a full replacement. `save()` flushes all pending namespaces atomically (write to `.tmp`, then `os.rename`). `load()` merges in-memory pending changes with the on-disk snapshot without flushing.

### UI (`ui/`)

`ui/status_panel.lua` opens a floating/split window showing all active and recent runs, driven by subscriptions to exec's `_on_state_change` and `_on_report` signals. `ui/StatusTree.lua` is the renderer that builds the buffer lines from the run entries.

## Styling

Add Lua annotations (`---@param`, `---@return`, `---@class`, etc.) whenever possible.

Class-based modules are named in PascalCase; functional modules are named in snake_case.

Module-scope `local` variables are prefixed with `_`, except:
- a local name bound directly from `require()`
- the conventional `M` module table
- class type names like `MyType`

Inside a class, private members are prefixed with `_`.
