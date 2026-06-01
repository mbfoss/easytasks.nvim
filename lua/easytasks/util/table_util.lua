local M = {}

--- Wrap a table with a __tostring that emits keys in the given order.
--- Remaining keys are appended sorted. Subtables with __tostring are
--- serialized recursively via tostring().
---@param t    table
---@param keys string[]
---@return table
function M.ordered(t, keys)
    return setmetatable(t, {
        keys_order = keys
    })
end

return M
