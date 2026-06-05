# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make test   # run all tests (requires plenary.nvim)
```

Tests live in `tests/` and are discovered automatically by Plenary/Busted. `tests/init.lua` clones plenary to `/tmp/plenary.nvim` if not present (override with `NVIM_PLENARY_DIR`).

## Task file format

Tasks are defined in a `tasks.lua` file at the project root (configurable via `tasks_filename`). The file must return a list of task tables:

```lua
return {
    { name = "build", type = "process", command = "make" },
    { name = "test",  type = "process", command = "make test", depends_on = { "build" } },
    { name = "all",   type = "composite", depends_on = { "build", "test" }, depends_order = "sequence" },
}
```

Fields shared by every task type: `name`, `type`, `if_running`, `depends_on`, `depends_order`.

User-facing types are defined in `lua/easytasks/types/task_config.lua`. With `lazydev.nvim` (or `neodev.nvim`) these are automatically in the lua-ls workspace library, so adding `---@type easytasks.TaskConfig[]` above the `return` in a `tasks.lua` gives full LSP autocomplete:

```lua
---@type easytasks.TaskConfig[]
return {
    { name = "build", type = "process", command = "make" },
}
```

## Architecture

**easytasks.nvim** is a Neovim plugin with a **task runner** that loads and executes Lua task-config files. `lua/easytasks/init.lua` is the public API — `setup()` wires everything together and registers the `:Easytasks` command.

### Runner subsystem (`runner/`)

`runner/exec.lua` is the execution engine. `exec.run(task_name, lua_path)`:
1. Loads the tasks file with `loadfile` to get task configs indexed by name
2. Validates missing dependencies (`find_missing_dep`) and detects cycles (`find_cycle`)
3. Launches the task (and its dependencies, serially or in parallel via `depends_order`) as a coroutine via `util/async.lua`

`util/async.lua` implements a minimal coroutine scheduler on top of `vim.fn.jobstart`. `async.go` drives a coroutine; `async.spawn` starts a process in a terminal buffer and `coroutine.yield()`s until it exits (resumed by the `on_exit` callback). `async.wait_all` fans out parallel dependencies and yields until all complete.

`types/process/term.lua` manages named terminal buffers (one per task name); `term.open` creates or reuses a buffer, `term.show` opens it in a split.

### Type registry (`types/`)

`types/init.lua` holds a registry of task types. Each type module exports `{ run }`. Built-in types: `process`, `composite`.

New task types are registered with `easytasks.register_task_type(name, type_def)` before or after `setup()`.

### Styling

Add Lua annotations (`---@param`, `---@return`, `---@class`, etc.) whenever possible.

Class-based modules are named in PascalCase and functional modules are named in snake_case.
