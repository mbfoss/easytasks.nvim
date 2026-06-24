# Development

Developer notes for `easytasks.nvim`. For an architectural overview see
[CLAUDE.md](CLAUDE.md).

## Repository layout

```
lua/easytasks/            plugin source
  init.lua                public API (setup, enable/disable, register_* hooks)
  config.lua              runtime config
  commands.lua            :Tasks user command
  project.lua             project-root discovery
  runner/                 task resolution + execution
  types/                  task-type registry + built-ins + schema merge
  macros.lua              ${name} value substitutions
  lsp/                    in-process language server for the tasks file
  ui/                     status panel + tree view
  util/                   shared helpers
  tomltools/              VENDORED TOML engine (git subtree, see below)
tests/                    plenary specs
```

## Running tests

The suite uses [plenary](https://github.com/nvim-lua/plenary.nvim). Run it with:

```sh
make test          # alias for unit_test
make unit_test     # plenary specs under tests/
```

Run a single plenary spec while iterating:

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/completion_spec.lua"
```

## The vendored TOML engine (`tomltools`)

The TOML parser/decoder/encoder/validator/formatter and the schema
navigation used by the LSP all live in the separate
[`tomltools`](https://github.com/mbfoss/tomltools) repository. It is vendored
into this plugin as a **git subtree** (not a submodule), so a fresh clone has
everything it needs with no extra fetch step.

### Why it is namespaced under `easytasks.`

Upstream `tomltools` ships its library at `lua/tomltools/` and its modules
`require` each other by the absolute name `tomltools.*`. If we vendored it at
the runtimepath-visible path `lua/tomltools/`, the top-level module name
`tomltools` would be **global to Neovim**: any other installed plugin that also
vendored `tomltools` would collide, and whichever loaded first would silently
win for both.

To make collisions impossible, the engine is vendored under this plugin's own
namespace instead:

| | |
|---|---|
| Vendored at | `lua/easytasks/tomltools/` |
| Imported as | `require("easytasks.tomltools")` (and `.parser`, `.Cst`, …) |

**Invariant:** every internal `require("tomltools…")` inside the vendored files
is rewritten to `require("easytasks.tomltools…")`. This rewrite must be
re-applied after every update (step 4 below). LuaCATS type annotations
(`---@class tomltools.Cst`, etc.) are left as the upstream `tomltools.*` names —
they are documentation only and do not affect module resolution.

### Updating the vendored engine

The upstream remote (added once):

```sh
git remote add tomltools https://github.com/mbfoss/tomltools.git
```

`git subtree` cannot split a subdirectory straight out of a *remote* ref, and
upstream nests the library at `lua/tomltools/`. So the update extracts that
subdir onto a throwaway branch first, then merges it into the vendored prefix:

```sh
# 1. Fetch upstream.
git fetch tomltools

# 2. Extract just lua/tomltools/ into a split branch.
#    (no --squash on the temp add: `subtree split` needs real history to walk)
git switch -c _tt_tmp
git subtree add   --prefix=_ttsrc tomltools main
git subtree split --prefix=_ttsrc/lua/tomltools --branch _tt_split
git switch main
git branch -D _tt_tmp                 # drop the throwaway; _tt_split survives

# 3. Merge the new snapshot into the vendored prefix.
git subtree merge --prefix=lua/easytasks/tomltools _tt_split --squash

# 4. Re-apply the private-namespace rewrite (upstream uses bare `tomltools.*`).
perl -pi -e 's/(require\(\s*["\x27])tomltools/${1}easytasks.tomltools/g' \
  lua/easytasks/tomltools/*.lua

# 5. Verify nothing bare remains, then commit and clean up.
grep -rEn 'require\(\s*["'"'"']tomltools' lua/easytasks/tomltools \
  && echo "!! fix the lines above" || echo "ok: all requires namespaced"
git add lua/easytasks/tomltools
git commit -m "Update vendored tomltools"
git branch -D _tt_split
```

> If step 3 reports merge conflicts, they are almost always on a `require` line
> that upstream changed — resolve by taking upstream's line, then let step 4
> re-namespace it.

### After updating: check the consuming API

The plugin calls into the engine at a handful of sites; if the `tomltools`
public or submodule API changed, these must be updated to match:

- `runner/exec.lua`, `commands.lua` — `toml.parse`, `toml.find_path`,
  `toml.encode` (whole-document → `string`), `toml.encode_entry` (styled
  snippet → `string[]`).
- `lsp/server/*` — direct use of submodules `parser`, `decoder`, `formatter`,
  `validator`, `Cst`, `schema_nav`, `schema_util`.

A good smoke test is to open a `tasks.toml` (LSP completion/diagnostics/hover)
and run a task via `:Tasks`, in addition to `make test`.
