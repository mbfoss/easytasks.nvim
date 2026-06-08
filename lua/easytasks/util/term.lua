local M = {}

local ui = require("easytasks.util.ui_util")

---@class easytasks.SpawnHandle
---@field bufnr number
---@field stop    fun()                        stop the spawned command
---@field on_exit fun(cb: fun(code: integer))  register a callback invoked when the process exits

--- Spawn a command in a terminal buffer.
--- Returns immediately with a handle; call `handle.on_exit(cb)` to be notified when the process exits.
--- `bufnr` must already be visible in a window.
--- termopen handles all output rendering including ANSI colours.
---@param cmd  string|string[]
---@param opts {cwd?: string, env?: table<string,string>, on_stdout?: fun(id: integer, data: string[], name: string), on_stderr?: fun(id: integer, data: string[], name: string)}
---@param bufnr? integer buffer to own the ternimal (auto created if null)
---@return easytasks.SpawnHandle?
function M.spawn(cmd, opts, bufnr)
    -- A terminal buffer must be in a window for jobstart {term=true}.
    local own_buf
    if not bufnr then
        own_buf = true
        bufnr = vim.api.nvim_create_buf(true, true)
        vim.bo[bufnr].swapfile = false
    end

    local spawn_win = ui.create_window(bufnr, false, {
        relative  = "editor",
        row       = 0,
        col       = 0,
        width     = vim.o.columns,
        height    = vim.o.lines,
        style     = "minimal",
        hide      = true,
        focusable = false,
        zindex    = 1,
    }, function() end)

    local saved_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(spawn_win)

    local exit_cb
    local job_id
    job_id = vim.fn.jobstart(cmd, {
        term      = true,
        cwd       = opts.cwd,
        env       = opts.env,
        on_stdout = opts.on_stdout,
        on_stderr = opts.on_stderr,
        on_exit   = function(_, code)
            job_id = -1
            vim.schedule(function()
                if exit_cb then exit_cb(code) end
            end)
        end,
    })

    vim.api.nvim_set_current_win(saved_win)
    vim.api.nvim_win_close(spawn_win, true)

    if job_id <= 0 then
        if own_buf then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
        return nil
    end

    vim.api.nvim_create_autocmd("TermClose", {
        buffer   = bufnr,
        once     = true,
        callback = function()
            for _, key in ipairs({ 'i', 'a', 'o', 'I', 'A', 'O', 'c', 'cc', 'C', 's', 'S', 'R', '.' }) do
                vim.keymap.set("n", key, "<Nop>", { buffer = bufnr, nowait = true })
            end
        end,
    })

    return { ---@type easytasks.SpawnHandle
        bufnr = bufnr,
        stop = function()
            if job_id > 0 then
                vim.fn.jobstop(job_id)
            end
        end,
        on_exit = function(cb) exit_cb = cb end,
    }
end

return M
