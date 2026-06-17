# CLAUDE.md

## Overview

`easytasks.nvim` is a Neovim task runner. Tasks are declared in a per-project
Lua file (`tasks.lua` by default) and run from within Neovim via the `:Tasks`
command. The tasks file returns a map of name → task; each task is built with a
typed constructor from `easytasks.types`
(`easytasks.types.run/debug/composite{ … }`). The runner injects `easytasks`
as a global into the tasks file's environment (see
[runner/exec.lua](lua/easytasks/runner/exec.lua) `_load_tasks`), so authoring
needs no `require`; elsewhere `require("easytasks")` works the same way. Any
task field value may be a **function**, evaluated lazily at run time (this
replaces the old `${…}` macro system). The plugin ships several built-in task
types, task dependencies, pluggable pre-launch actions, value providers, and a
status-panel UI.

The public API splits across three modules:
- [lua/easytasks/init.lua](lua/easytasks/init.lua) — `setup`, `enable`/`disable`,
  `in_project`, the `providers` value providers, the extension points
  `register_task_type`/`register_action`/`register_qfmatcher`/`register_debug_backend`,
  plus `types`/`providers`/`actions` re-exports.
- [lua/easytasks/types/init.lua](lua/easytasks/types/init.lua) — the task-type
  registry *and* the authoring constructors (`run`, `composite`, `debug`, generic
  `task`, plus a metatable that yields a constructor for any registered custom
  type).
- [lua/easytasks/actions/init.lua](lua/easytasks/actions/init.lua) — the same
  registry/constructor/metatable pattern as `types`, but for `pre_launch_actions`
  entries (e.g. the built-in `save_buffers`); a resolved action is just a
  function `fun(action, ctx): boolean, string?`, not a table.

lua-language-server completion for `tasks.lua` comes from a curated library in
[meta/](meta/) — `meta/easytasks.lua` (`---@meta easytasks`) and
`meta/easytasks-types.lua` (`---@meta easytasks.types`). Consumers point
`Lua.workspace.library` at `meta/` (never at `lua/`, which would leak internal
`---@class` definitions); `:Tasks bootstrap` wires this up automatically.
[lua/easytasks/annotations.lua](lua/easytasks/annotations.lua) mirrors the spec
classes for in-repo development only and is excluded from consumers.

## Architecture

- [config.lua](lua/easytasks/config.lua) — runtime config table (command name,
  tasks filename, storage dir, debug backend). Mutated in place by `setup`.
- [annotations.lua](lua/easytasks/annotations.lua) — `---@meta` spec classes
  (`RunSpec`, `DebugSpec`, `CompositeSpec`, …) used for in-repo development.
  Mirrored by [meta/](meta/), which is the curated library shipped to consumers.
  No runtime code.
- [bootstrap.lua](lua/easytasks/bootstrap.lua) — `:Tasks bootstrap`: scaffolds a
  starter `tasks.lua` and creates/updates `.luarc.json` so lua_ls loads `meta/`.
- [project.lua](lua/easytasks/project.lua) — locates the project root by finding
  the tasks file in cwd.
- [commands.lua](lua/easytasks/commands.lua) — registers the user command.
- [runner/](lua/easytasks/runner/) — loads, resolves, and executes tasks. `exec`
  loads `tasks.lua` (via `loadfile`, fresh each run), drives dependency order and
  state; `resolver.resolve_values` replaces any function-valued field with its
  result (functions run in a coroutine, so they may yield, e.g. to prompt).
- [types/](lua/easytasks/types/) — task-type registry, the authoring
  constructors, and built-in types (`run`/process, `debug`, `composite`). Each
  type may contribute a `validate` hook (checked at run time) and `templates`
  (`{ label, spec }`, rendered to Lua snippets by `:Tasks template`). `types/run/`
  also exposes `quickfix_matchers`, a flat table of built-in plus
  `register_qfmatcher`-registered matcher functions, surfaced as the
  `easytasks.quickfix_matchers` tasks-file global; a `RunSpec.quickfix_matchers`
  field is an array of matcher function references (built-in or inline), tried
  in order, first match wins.
- [actions/](lua/easytasks/actions/) — pre-launch action registry and
  constructors (`save_buffers` built in); run, in order, via a task's
  `pre_launch_actions` after dependencies resolve and before it starts, any
  failure aborting the task.
- [providers.lua](lua/easytasks/providers.lua) — value providers (`file()`,
  `cwd()`, `env()`, `prompt()`, `select_pid()`, …); each returns a `fun(ctx)`
  for use as a task field value. Exposed as `require("easytasks").providers`.
- [ui/](lua/easytasks/ui/) — status panel and tree view.
- [util/](lua/easytasks/util/) — shared helpers (async, signals, tree, terminal,
  etc.).

The `debug` task type delegates to a pluggable backend
([types/debug/backends/](lua/easytasks/types/debug/backends/)): `nvim-dap` or
`easydap`.

## Testing

Tests use plenary and live in [tests/](tests/). Run them with:

```sh
make test
```

## Styling

Add Lua annotations (`---@param`, `---@return`, `---@class`, etc.) whenever possible.

Class-based modules are named in PascalCase; functional modules are named in snake_case.

Module-scope `local` variables are prefixed with `_`, except:
- a local name bound directly from `require()`
- the conventional `M` module table
- class type names like `MyType`

Inside a class, private members are prefixed with `_`.
</content>
</invoke>
