local M = {}

---@param t     table
---@param keys  string[]
---@return string
local function serialize(t, keys)
    local seen = {}
    local parts = {}
    for _, k in ipairs(keys) do
        if t[k] ~= nil then
            seen[k] = true
            parts[#parts + 1] = k .. " = " .. tostring(t[k])
        end
    end
    local rest = {}
    for k in pairs(t) do
        if not seen[k] then rest[#rest + 1] = k end
    end
    table.sort(rest)
    for _, k in ipairs(rest) do
        parts[#parts + 1] = k .. " = " .. tostring(t[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

--- Wrap a table with a __tostring that emits keys in the given order.
--- Remaining keys are appended sorted. Subtables with __tostring are
--- serialized recursively via tostring().
---@param t    table
---@param keys string[]
---@return table
function M.ordered(t, keys)
    return setmetatable(t, {
        __tostring = function(self)
            return serialize(self, keys)
        end,
    })
end

return M
