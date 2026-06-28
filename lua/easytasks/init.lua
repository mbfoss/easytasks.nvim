local M      = {}

local config = require("easytasks.config")

--- Register a task type. Can be called at any time before setup() to have the
--- type included in the schema, or after setup() for runtime-only use.
--- `loader` may be a module path string, a zero-arg factory function, or a
--- fully-resolved TaskTypeDef table.
---@param name   string
---@param loader easytasks.TypeLoader
function M.register_task_type(name, loader)
    require("easytasks.types").register(name, loader)
end

--- Register a custom quickfix matcher for use in process tasks.
---@param name string
---@param fn   easytasks.QfMatcher
function M.register_qfmatcher(name, fn)
    require("easytasks.types.process").register_qfmatcher(name, fn)
end

--- Register a custom macro for use in task config values.
--- Macro syntax in TOML: `${name}` or `${name:arg1,arg2}`.
--- Built-in macros cannot be overridden (raises an error).
---@param name string
---@param fn   easytasks.MacroFn
function M.register_macro(name, fn)
    require("easytasks.macros").register(name, fn)
end

local _enabled = false

--- True if `buf`'s file is the project tasks file, matched by filename. The
--- tasks file gets its own `easytasks` filetype (see easytasks.filetype), so the
--- LSP attaches to it alone and never touches ordinary `.toml` buffers.
---@param buf integer
---@return boolean
local function _is_tasks_buf(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    return name ~= "" and vim.fs.basename(name) == config.tasks_filename
end

function M.enable()
    if _enabled then return end
    _enabled = true

    local ft = require("easytasks.filetype")
    ft.register()

    -- Start the tasks-file LSP for our dedicated filetype only.
    local augroup = vim.api.nvim_create_augroup("easytasks_tasks_lsp", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
        pattern  = { ft.NAME },
        group    = augroup,
        callback = function(ev)
            if not _is_tasks_buf(ev.buf) then return end
            require("easytasks.lsp").start(ev.buf, {
                schema = function() return require("easytasks.types").build_resolved_schema() end,
            })
        end,
    })

    -- Filetype detection only fires on future loads, so convert any tasks buffer
    -- that is already open; setting the filetype also attaches the LSP via the
    -- autocmd above.
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf)
            and _is_tasks_buf(buf)
            and vim.bo[buf].filetype ~= ft.NAME then
            vim.bo[buf].filetype = ft.NAME
        end
    end

    require("easytasks.commands").register(config.command)
end

function M.disable()
    if not _enabled then return end
    _enabled = false
    vim.api.nvim_del_augroup_by_name("easytasks_tasks_lsp")
    local lsp = require("easytasks.lsp")
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if _is_tasks_buf(buf) then
            lsp.stop(buf)
        end
    end
end

---@param opts easytasks.Config?
function M.setup(opts)
    local tmp = vim.tbl_deep_extend("force", config or {}, opts or {})
    for k, v in pairs(tmp) do
        config[k] = v
    end
    if config.enabled then
        M.enable()
    else
        M.disable()
    end
end

---@return boolean
function M.in_project()
    return require("easytasks.project").find_root() ~= nil
end

return M
