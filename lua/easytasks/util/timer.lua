local M = {}

---@param timer table?
---@return nil
function M.stop_and_close_timer(timer)
    if timer and not timer:is_closing() then
        timer:close()
    end
    return nil
end

---@param interval number Delay and repeat interval in milliseconds.
---@param fn function Callback to execute.
---@return function stop A function that stops and closes the timer.
function M.start_timer(interval, fn)
    local timer = vim.uv.new_timer()
    assert(timer, "Timer creation failed")
    timer:start(interval, interval, vim.schedule_wrap(fn))
    return function()
        M.stop_and_close_timer(timer)
        timer = nil
    end
end

return M
