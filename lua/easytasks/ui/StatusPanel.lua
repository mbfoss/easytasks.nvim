local ListBuffer = require('easytasks.ui.ListBuffer')
local exec       = require('easytasks.runner.exec')

---@class easytasks.ui.StatusPanel
local M = {}

---@type easytasks.ui.ListBuffer?
local _lb = nil

---@type integer?
local _win = nil

local _state_badge = {
    running = { "● ", "DiagnosticWarn" },
    ok      = { "● ", "DiagnosticOk" },
    failed  = { "● ", "DiagnosticError" },
    idle    = { "● ", "Comment" },
}

---@param name string
---@param entry easytasks.RunEntry
---@return string[][], string[][]
local function formatter(name, entry)
    local badge = _state_badge[entry.state] or _state_badge.idle
    return {
        { badge[1], badge[2] },
        { name,     nil },
    }, {}
end

local function on_state_change(name, entry)
    if not _lb then return end
    _lb:add_item(name, entry)
end

local function on_close()
    exec.unsubscribe(on_state_change)
    _lb  = nil
    _win = nil
end

function M.open()
    if _win and vim.api.nvim_win_is_valid(_win) then
        vim.api.nvim_set_current_win(_win)
        return
    end

    _lb = ListBuffer.new({
        formatter           = formatter,
        current_item_prefix = "",
        on_selection        = function(name, entry)
            if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
                vim.cmd("botright split")
                vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), entry.bufnr)
            end
        end,
    })

    local buf = _lb:buf()
    vim.bo[buf].filetype = "easytasks-status"

    vim.cmd("botright split")
    _win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(_win, buf)
    vim.wo[_win].number         = false
    vim.wo[_win].relativenumber = false
    vim.wo[_win].wrap           = false
    vim.wo[_win].winfixheight   = true
    vim.api.nvim_win_set_height(_win, 8)

    vim.api.nvim_create_autocmd("WinClosed", {
        pattern  = tostring(_win),
        once     = true,
        callback = on_close,
    })

    -- Populate with current state then subscribe for live updates
    for name, entry in pairs(exec.get_all()) do
        _lb:add_item(name, entry)
    end

    exec.subscribe(on_state_change)
end

function M.toggle()
    if _win and vim.api.nvim_win_is_valid(_win) then
        vim.api.nvim_win_close(_win, false)
    else
        M.open()
    end
end

return M
