-- Buffer-local setup for the tasks file (a TOML document under a dedicated
-- filetype). Mirrors the relevant bits of the standard `toml` ftplugin and
-- starts treesitter highlighting using the `easytasks` grammar alias.

vim.bo.commentstring = "# %s"
vim.bo.comments = ":#"

if require("easytasks.ts").ensure_parser() then
    pcall(vim.treesitter.start, 0, "easytasks")
end
