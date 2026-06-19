local M = {}

-- Tracks whether the `easytasks` treesitter language has been registered.
local _added = false

--- Register a treesitter language named `easytasks` backed by the bundled TOML
--- grammar. This lets the tasks file use scoped queries under
--- `queries/easytasks/` (base TOML highlights plus the `lua` script injection)
--- without registering anything under `queries/toml/`, so other `.toml` files
--- are left untouched.
---@return boolean ok `true` if the language is available afterwards.
function M.ensure_parser()
    if _added then return true end

    -- Reuse the compiled `toml` parser. Parser libraries use a platform-specific
    -- extension (`.dll` on Windows, `.so` elsewhere); locate it on the runtimepath.
    local ext = vim.fn.has("win32") == 1 and "dll" or "so"
    local path = vim.api.nvim_get_runtime_file("parser/toml." .. ext, false)[1]
    if not path then
        return false
    end

    _added = pcall(vim.treesitter.language.add, "easytasks",
        { path = path, symbol_name = "toml" })
    return _added
end

return M
