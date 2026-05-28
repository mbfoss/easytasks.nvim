local M = {}

local ui = require("easytasks.ui")

local _spawn_win

---@class easytasks.SpawnHandle
---@field stop fun() stop the spawned command
---@field wait   fun(): integer  yields the calling coroutine until the process exits

--- Spawn a command in a terminal buffer.
--- Must be called from within a coroutine (started with async.go).
--- Returns immediately with a handle; call `handle.wait()` to yield until exit.
--- `bufnr` must already be visible in a window.
--- termopen handles all output rendering including ANSI colours.
---@param cmd  string|string[]
---@param opts {cwd?: string, env?: table<string,string>}
---@param bufnr integer  terminal buffer (must be visible in a window)
---@return easytasks.SpawnHandle
function M.spawn(cmd, opts, bufnr)
    -- A terminal buffer must be in a window for jobstart {term=true}.
    if not _spawn_win then
        _spawn_win = ui.create_window(bufnr, false, {
            relative  = "editor",
            row       = 0,
            col       = 0,
            width     = vim.o.columns,
            height    = vim.o.lines,
            style     = "minimal",
            hide      = true,
            focusable = false,
            zindex    = 1,
        }, function()
            _spawn_win = nil
        end)
    else
        vim.api.nvim_win_set_buf(_spawn_win, bufnr)
    end

    local saved_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(_spawn_win)

    local waker
    local job_id
    job_id = vim.fn.jobstart(cmd, {
        term    = true,
        cwd     = opts.cwd,
        env     = opts.env,
        on_exit = function(_, code)
            job_id = -1
            vim.schedule(function()
                if waker then waker(code) end
            end)
        end,
    })

    vim.api.nvim_set_current_win(saved_win)

    if job_id <= 0 then
        return { job_id = -1, wait = function() return -1 end }
    end

    return {
        stop = function()
            if job_id > 0 then
                vim.fn.jobstop(job_id)
            end
        end,
        wait = function()
            return coroutine.yield(function(w) waker = w end)
        end,
    }
end

return M
