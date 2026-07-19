local M = {}

local _uv = vim.uv

local function _is_exiting()
    return vim.v.exiting ~= vim.NIL
end

---Create a throttled wrapper: leading run on the first call, calls during the
---cooldown window suppressed, and exactly one trailing run scheduled if any
---were suppressed.
---@param ms number Throttle interval in milliseconds.
---@param fn function Function to throttle.
---@return function wrapped Throttled wrapper function.
function M.throttle_wrap(ms, fn)
    local timer = nil
    local last_exec = 0

    return function()
        local now = _uv.now()

        local function run()
            last_exec = _uv.now()
            if not _is_exiting() then
                fn()
            end
        end
        if last_exec == 0 or now - last_exec >= ms then
            run()
            return
        end
        if timer then
            return
        end
        local delay = ms - (now - last_exec)
        timer = _uv.new_timer()
        assert(timer)
        timer:start(delay, 0, function()
            vim.schedule(function()
                if timer:is_active() then timer:stop() end
                if not timer:is_closing() then timer:close() end
                timer = nil
                run()
            end)
        end)
    end
end

---Create a leading-only throttle wrapper: runs immediately on the first call,
---then ignores every call until the cooldown elapses. Unlike `throttle_wrap`,
---no trailing execution is scheduled.
---@param ms number Throttle interval in milliseconds.
---@param fn function Function to throttle.
---@return function wrapped Throttled wrapper function.
function M.leading_throttle_wrap(ms, fn)
    local last_exec = 0
    return function(...)
        local now = _uv.now()
        if last_exec ~= 0 and (now - last_exec) < ms then
            return
        end
        last_exec = now
        if not _is_exiting() then
            fn(...)
        end
    end
end

---Create a fixed-delay trailing wrapper: runs once `ms` after the first call,
---ignoring calls made while pending. Unlike a debounce, repeated calls do not
---reset the timer and only one execution may be pending.
---@param ms number Wait duration in milliseconds.
---@param fn function Function to execute.
---@return function wrapped Wrapped function.
function M.trailing_fixed_wrap(ms, fn)
    local is_pending = false

    return function(...)
        if is_pending then
            return
        end

        is_pending = true
        local t = _uv.new_timer()
        assert(t)
        t:start(ms, 0, function()
            vim.schedule(function()
                if t then
                    if not t:is_closing() then t:close() end
                end
                is_pending = false
                if not _is_exiting() then
                    fn()
                end
            end)
        end)
    end
end

---Create a trailing debounce wrapper: runs once `ms` after the **last** call.
---Every new call resets the timer; there is no leading execution.
---@param ms number Wait duration in milliseconds.
---@param fn function Function to execute.
---@return function wrapped Wrapped function.
function M.debounce_wrap(ms, fn)
    local timer = nil

    return function()
        if timer then
            if not timer:is_closing() then timer:stop(); timer:close() end
            timer = nil
        end
        local t = _uv.new_timer()
        assert(t)
        timer = t
        t:start(ms, 0, function()
            vim.schedule(function()
                if not t:is_closing() then t:close() end
                timer = nil
                if not _is_exiting() then
                    fn()
                end
            end)
        end)
    end
end

return M
