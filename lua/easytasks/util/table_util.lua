local M = {}

--- Wrap a table so encoders emit its keys in the given order.
--- Keys not listed are appended afterwards, sorted.
---@param t    table
---@param keys string[]
---@return table
function M.ordered(t, keys)
    return setmetatable(t, { keys_order = keys })
end

--- Returns the key order list if t was created with M.ordered(), otherwise nil.
---@param t any
---@return string[]?
function M.ordered_keys_of(t)
    if type(t) ~= "table" then return nil end
    local mt = getmetatable(t)
    return mt and type(mt.keys_order) == "table" and mt.keys_order or nil
end

return M
