local M = {}

local config = require("easytasks.config")

--- Filetype assigned to the project tasks file. The tasks file is TOML on disk,
--- but it gets a dedicated filetype so the tasks-file LSP (and our ftplugin)
--- only ever apply to it, never to ordinary `.toml` buffers.
M.NAME = "easytasks"

local _ts_registered = false

--- Register filetype detection for the configured tasks filename, and map the
--- `toml` treesitter grammar onto our filetype so highlighting keeps working.
--- Idempotent; safe to call again after `tasks_filename` changes via `setup`.
function M.register()
    -- (Re)register the filename rule so a changed `tasks_filename` takes effect.
    -- `vim.filetype.add` merges rules, so earlier names simply stop matching once
    -- nothing is named after them.
    vim.filetype.add({
        filename = {
            [config.tasks_filename] = M.NAME,
        },
    })

    if _ts_registered then return end
    _ts_registered = true

    -- Reuse the toml grammar for treesitter-based highlighting (no-op if the
    -- treesitter API or the toml parser is unavailable).
    pcall(vim.treesitter.language.register, "toml", M.NAME)
end

return M
