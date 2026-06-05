local M            = {}

local cfg          = require("easytasks.config")
local project      = require("easytasks.project")
local task_types   = require("easytasks.types")
local status_panel = require("easytasks.ui.status_panel")
local ui           = require("easytasks.ui")

-- Captured at load time: the lua/ directory of this plugin.
-- Used to inject type definitions into lua-ls when a tasks file is opened.
local _plugin_lua_dir = vim.fn.fnamemodify(
    debug.getinfo(1, "S").source:sub(2), -- strip leading "@" from chunk source
    ":h:h"                               -- up from lua/easytasks/init.lua → lua/
)

local _lsp_aug = vim.api.nvim_create_augroup("EasytasksLsp", { clear = false })

M.runner           = require("easytasks.runner")

--- Register a task type. Can be called before or after setup().
--- `loader` may be a module path string, a zero-arg factory function, or a
--- fully-resolved TaskTypeDef table.
---@param name   string
---@param loader easytasks.TypeLoader
function M.register_task_type(name, loader)
    task_types.register(name, loader)
end

--- Register a custom quickfix matcher for use in process tasks.
---@param name string
---@param fn   easytasks.QfMatcher
function M.register_qfmatcher(name, fn)
    require("easytasks.types.process").register_qfmatcher(name, fn)
end

---@type easytasks.Config
M.config = cfg.current

local enabled = false

---@type { name: string, path: string }?
local _last_task = nil

local function run_command()
    local cwd, err = project.find_root()
    if not cwd then
        ui.notify_error(err or "not in a project root")
        return
    end

    local path = vim.fs.normalize(cwd .. "/" .. cfg.current.tasks_filename)
    local names, list_err = M.runner.list_tasks(path)
    if not names then
        ui.notify_error(list_err or "failed to load tasks")
        return
    end

    vim.ui.select(names, {
        prompt = "Run task:",
    }, function(choice)
        if not choice then return end
        _last_task = { name = choice, path = path }
        require("easytasks.save_buffers").save(cwd, cfg.current.save_buffers)
        status_panel.open()
        M.runner.run(choice, path)
    end)
end

local function restart_command()
    if not _last_task then
        ui.notify_warning("no task has been run yet")
        return
    end
    local cwd, err = project.find_root()
    if not cwd then
        ui.notify_error(err or "not in a project root")
        return
    end
    local path = vim.fs.normalize(cwd .. "/" .. cfg.current.tasks_filename)
    if path ~= _last_task.path then
        ui.notify_warning("project changed since last run")
        return
    end
    require("easytasks.save_buffers").save(cwd, cfg.current.save_buffers)
    status_panel.open()
    M.runner.run(_last_task.name, _last_task.path)
end

---@param client any  vim.lsp.Client
local function _inject_lua_ls_library(client)
    local settings = vim.deepcopy(client.config.settings or {})
    local lib = vim.tbl_get(settings, "Lua", "workspace", "library") or {}
    if type(lib) ~= "table" then lib = {} end

    local norm = vim.fn.fnamemodify(_plugin_lua_dir, ":p")
    for _, p in ipairs(lib) do
        if vim.fn.fnamemodify(p, ":p") == norm then return end
    end

    table.insert(lib, _plugin_lua_dir)
    settings.Lua                       = settings.Lua or {}
    settings.Lua.workspace             = settings.Lua.workspace or {}
    settings.Lua.workspace.library     = lib
    client.config.settings             = settings
    client.notify("workspace/didChangeConfiguration", { settings = settings })
end

function M.enable()
    if enabled then return end
    enabled = true

    vim.api.nvim_create_autocmd("LspAttach", {
        group    = _lsp_aug,
        callback = function(args)
            local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":t")
            if fname ~= cfg.current.tasks_filename then return end
            local client = vim.lsp.get_client_by_id(args.data.client_id) ---@type any
            if not client then return end
            if client.name ~= "lua_ls" and client.name ~= "sumneko_lua" then return end
            _inject_lua_ls_library(client)
        end,
    })

    if cfg.current.log.enabled then
        require("easytasks.util.log").enable(cfg.current.log.path, cfg.current.log.level)
    end

    require("easytasks.util.usercmd").register_user_cmd("Easytasks",
        function(cmd, args, cmd_opts)
            local action = args[1]
            table.remove(args, 1)
            if action == nil or action == "" or action == "run" then
                run_command()
            elseif action == "restart" then
                restart_command()
            elseif action == "toggle" then
                require("easytasks.ui.status_panel").toggle()
            elseif action == "jump" then
                require("easytasks.ui.status_panel").jump()
            else
                ui.notify_warning("Invalid action: " .. tostring(action))
            end
        end,
        {
            desc = "Easytasks",
            subcommand_fn = function(cmd, rest)
                if cmd == "Easytasks" and #rest == 0 then
                    return { "toggle", "run", "restart", "jump" }
                end
                return {}
            end
        })
end

function M.disable()
    if not enabled then return end
    enabled = false
end

---@param opts easytasks.Config?
function M.setup(opts)
    cfg.current = vim.tbl_deep_extend("force", cfg.default(), opts or {})
    M.config = cfg.current

    project.init()

    if cfg.current.enabled then
        M.enable()
    else
        M.disable()
    end
end

---@return boolean
function M.in_project()
    return project.in_project()
end

--- Emitted (with root path) just before the cwd leaves a project root,
--- and also on VimLeavePre.
M.on_project_leave_pre = project.on_project_leave_pre ---@type easytasks.util.Signal<fun(root: string)>

--- Emitted (with root path) after the cwd enters a project root.
M.on_project_enter = project.on_project_enter ---@type easytasks.util.Signal<fun(root: string)>

--- Emitted after a cwd change lands outside any project root.
M.on_project_leave = project.on_project_leave ---@type easytasks.util.Signal<fun()>

--- Store data under a namespace key in the project storage file.
---@param namespace string
---@param data table
---@return boolean,string?
function M.store_data(namespace, data)
    return project.store_data(namespace, data)
end

--- Load data for a namespace key from the project storage file.
---@param namespace string
---@return table|nil,string?
function M.load_data(namespace)
    return project.load_data(namespace)
end

return M
