local M = {}

--- @param buffer integer Buffer to display, or 0 for current buffer
--- @param enter boolean Enter the window (make it the current window)
--- @param config vim.api.keyset.win_config Map defining the window configuration
--- @param on_close function
--- @return integer winid, integer augroup
function M.create_window(buffer, enter, config, on_close)
    local win = vim.api.nvim_open_win(buffer, enter, config)
    local augroup = vim.api.nvim_create_augroup("keystone_window_#" .. win, { clear = true })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = augroup,
        callback = function(args)
            local closedwin = tonumber(args.match)
            if closedwin == win then
                vim.api.nvim_del_augroup_by_id(augroup)
                on_close()
            end
        end
    })
    return win, augroup
end

---@param listed boolean
---@param buffer_options vim.bo?
---@param on_delete function?
function M.create_sratch_buffer(listed, buffer_options, on_delete)
    local buf = vim.api.nvim_create_buf(listed, true)
    local bo = { ---@type vim.bo
        buftype = "nofile",
        swapfile = false,
        modeline = false,
    }
    if not listed then
        bo.bufhidden = 'wipe'
    end
    if buffer_options then
        for k, v in pairs(buffer_options) do
            bo[k] = v
        end
    end
    for k, v in pairs(bo) do
        vim.bo[buf][k] = v
    end
    if on_delete then
        vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
            buffer = buf,
            once = true,
            callback = function(ev)
                on_delete()
            end,
        })
    end
    return buf
end

return M
