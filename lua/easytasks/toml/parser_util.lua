local M = {}

---@enum easytasks.toml.NodeKind
M.NodeKind = {
    Literal                     = 1,
    Array                       = 2,
    InlineTable                 = 3,
    KeyValuePair                = 4,
    TableSection                = 5,
    ArrayOfTablesSection        = 6,
    PartialTableSection         = 7,
    PartialArrayOfTablesSection = 8,
    Comment                     = 9,
}

local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local invalid_utf_seq_msg = "invalid UTF-8 sequence"

local function is_leap(y)
    return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

---@param y integer
---@param mo integer
---@param d integer
---@return string|nil
function M.validate_date(y, mo, d)
    if mo < 1 or mo > 12 then return "month out of range" end
    local max_d = days_in_month[mo]
    if mo == 2 and is_leap(y) then max_d = 29 end
    if d < 1 or d > max_d then return "day out of range" end
end

---@param h integer
---@param mi integer
---@param sec number
---@return string|nil
function M.validate_time(h, mi, sec)
    if h < 0 or h > 23 then return "hour out of range" end
    if mi < 0 or mi > 59 then return "minute out of range" end
    if sec < 0 or sec > 60 then return "second out of range" end
end

---@param h integer
---@param mi integer
---@return string|nil
function M.validate_offset(h, mi)
    if h < 0 or h > 23 then return "timezone hour out of range" end
    if mi < 0 or mi > 59 then return "timezone minute out of range" end
end

---@param s string
---@return boolean
function M.validate_utf8(s)
    local i = 1
    while i <= #s do
        local b = s:byte(i)
        if b < 0x80 then
            i = i + 1
        elseif b < 0xC2 then
            break
        elseif b < 0xE0 then
            if i + 1 > #s then break end
            local b2 = s:byte(i + 1)
            if b2 < 0x80 or b2 > 0xBF then break end
            i = i + 2
        elseif b < 0xF0 then
            if i + 2 > #s then break end
            local b2, b3 = s:byte(i + 1), s:byte(i + 2)
            if b2 < 0x80 or b2 > 0xBF then break end
            if b3 < 0x80 or b3 > 0xBF then break end
            if b == 0xE0 and b2 < 0xA0 then break end
            if b == 0xED and b2 >= 0xA0 then break end
            i = i + 3
        elseif b <= 0xF4 then
            if i + 3 > #s then break end
            local b2, b3, b4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
            if b2 < 0x80 or b2 > 0xBF then break end
            if b3 < 0x80 or b3 > 0xBF then break end
            if b4 < 0x80 or b4 > 0xBF then break end
            if b == 0xF0 and b2 < 0x90 then break end
            if b == 0xF4 and b2 > 0x8F then break end
            i = i + 4
        else
            break
        end
    end
    return i > #s
end

return M
