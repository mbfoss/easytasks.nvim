-- easytasks/toml/decoder.lua

---@class easytasks.Range4
---@field [1] integer
---@field [2] integer
---@field [3] integer
---@field [4] integer

---@class easytasks.TomlSyntaxError
---@field message string
---@field range easytasks.Range4

---@class easytasks.DecoderResult
---@field ok boolean
---@field data table|nil
---@field errors easytasks.TomlSyntaxError[]
---@field pointer_map table<string, easytasks.Range4>

local M = {}

local pointer_map = {}

---@param token string
---@return string
local function escape(token)
    token = token:gsub("~", "~0")
    token = token:gsub("/", "~1")
    return token
end

---@param base string
---@param key string
---@return string
local function join(base, key)
    key = escape(key)
    if base == "" then
        return "/" .. key
    end
    return base .. "/" .. key
end

---@param s string
---@return string
local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

---@param text string
---@return string[]
local function split_lines(text)
    local lines = {}
    text = text:gsub("\r\n", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end

---@param row integer
---@param start_col integer
---@param end_col integer
---@return easytasks.Range4
local function range(row, start_col, end_col)
    return { row, start_col, row, end_col }
end

---@param row integer
---@param line string
---@return easytasks.Range4
local function line_range(row, line)
    return { row, 0, row, #line }
end

---@param path string
---@param r easytasks.Range4
local function register(path, r)
    if not pointer_map[path] then
        pointer_map[path] = r
    end
end

---@param raw string
---@return boolean, any
local function parse_value(raw)
    raw = trim(raw)

    do
        local s = raw:match('^"(.*)"$')
        if s then
            return true, (s:gsub('\\"', '"'))
        end
    end

    if raw == "true" then return true, true end
    if raw == "false" then return true, false end

    if raw:match("^%[.*%]$") then
        local inner = raw:sub(2, -2)
        local arr = {}

        if trim(inner) == "" then
            return true, arr
        end

        local current = ""
        local in_string = false

        local function push()
            local ok, v = parse_value(current)
            if not ok then return false, v end
            table.insert(arr, v)
            current = ""
            return true
        end

        for i = 1, #inner do
            local c = inner:sub(i, i)

            if c == '"' then
                in_string = not in_string
                current = current .. c
            elseif c == "," and not in_string then
                local ok, err = push()
                if not ok then return false, err end
            else
                current = current .. c
            end
        end

        if current ~= "" then
            local ok, err = push()
            if not ok then return false, err end
        end

        return true, arr
    end

    local n = tonumber(raw)
    if n ~= nil then return true, n end

    return false, "unsupported value: " .. raw
end

---@param text string
---@return easytasks.DecoderResult
function M.decode(text)
    local root = {}
    local errors = {}

    pointer_map = {}
    register("/", { 0, 0, 0, 0 })

    local current = root
    local current_path = ""

    local lines = split_lines(text)

    local function add_error(msg, r)
        table.insert(errors, { message = msg, range = r })
    end

    for line_no, raw_line in ipairs(lines) do
        local row = line_no - 1

        local line = raw_line
        line = line:gsub("%s+#.*$", "")
        line = trim(line)

        if line ~= "" then
            local table_name = line:match("^%[(.+)%]$")

            if table_name then
                current = root
                current_path = ""

                for part in table_name:gmatch("[^%.]+") do
                    part = trim(part)

                    if part == "" then
                        add_error("empty table segment", line_range(row, raw_line))
                        goto continue
                    end

                    if current[part] == nil then
                        current[part] = {}
                    end

                    current = current[part]
                    current_path = join(current_path, part)

                    register(current_path, line_range(row, raw_line))
                end
            else
                local eq = raw_line:find("=", 1, true)

                if not eq then
                    add_error("expected '='", line_range(row, raw_line))
                    goto continue
                end

                local key = trim(raw_line:sub(1, eq - 1))
                local raw_value = trim(raw_line:sub(eq + 1))

                if key == "" then
                    add_error("missing key", line_range(row, raw_line))
                    goto continue
                end

                if raw_value == "" then
                    add_error("missing value", line_range(row, raw_line))
                    goto continue
                end

                local ok, value = parse_value(raw_value)

                if not ok then
                    add_error(value, range(row, eq, #raw_line))
                    goto continue
                end

                current[key] = value

                local path = join(current_path, key)
                register(path, range(row, eq, #raw_line))

                if type(value) == "table" then
                    for i = 1, #value do
                        register(join(path, tostring(i - 1)), range(row, eq, #raw_line))
                    end
                end
            end
        end

        ::continue::
    end

    return {
        ok = #errors == 0,
        data = (#errors == 0) and root or nil,
        errors = errors,
        pointer_map = pointer_map,
    }
end

return M
