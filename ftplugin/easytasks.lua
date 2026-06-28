-- ftplugin for the easytasks tasks file. The file is TOML on disk, so reuse the
-- TOML comment settings and highlighting under our dedicated filetype.
if vim.b.did_ftplugin then return end
vim.b.did_ftplugin = true

vim.bo.commentstring = "# %s"
vim.bo.comments = ":#"

-- Prefer treesitter (the toml grammar is registered for this filetype in
-- easytasks.filetype); fall back to legacy TOML syntax when no parser exists.
if not pcall(vim.treesitter.start) then
    vim.bo.syntax = "toml"
end
