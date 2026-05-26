---@class easytasks.util.Signal
---@field _listeners function[]
local Signal = {}
Signal.__index = Signal

---@return easytasks.util.Signal
function Signal.new()
    return setmetatable({ _listeners = {} }, Signal)
end

---@param fn function
function Signal:subscribe(fn)
    table.insert(self._listeners, fn)
end

---@param fn function
function Signal:unsubscribe(fn)
    for i, l in ipairs(self._listeners) do
        if l == fn then
            table.remove(self._listeners, i)
            return
        end
    end
end

function Signal:emit(...)
    for _, fn in ipairs(self._listeners) do
        local ok, err = xpcall(fn, debug.traceback, ...)
        if not ok then
            vim.api.nvim_echo({ { tostring(err), "ErrorMsg" } },
                true, { err = true })
        end
    end
end

return Signal
