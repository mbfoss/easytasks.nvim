local M   = {}
local Cst = require("easytasks.toml.Cst")
local K   = Cst.Kind

local function needs_quotes(key)
    return not key:match("^[A-Za-z0-9_%-]+$")
end

local function quote_key(key)
    if needs_quotes(key) then
        return '"' .. key:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
    end
    return key
end

local function format_string(s)
    if not s:find("'") and not s:find("[\n\r\t\\]") then
        return "'" .. s .. "'"
    end
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
        :gsub("\b", "\\b"):gsub("\t", "\\t"):gsub("\n", "\\n")
        :gsub("\f", "\\f"):gsub("\r", "\\r")
    return '"' .. s .. '"'
end

---@param cst easytasks.toml.Cst
---@return string
function M.format(cst)
    local format_value  -- forward decl

    local function format_array(arr_id, arr_range, indent)
        local items = {}
        for vid, vd in cst:iter_values(arr_id) do
            table.insert(items, format_value(vid, vd, indent + 1))
        end
        if #items == 0 then return "[]" end
        local multiline = arr_range[1] ~= arr_range[3]
        if not multiline then
            return "[ " .. table.concat(items, ", ") .. " ]"
        end
        local pad   = string.rep("  ", indent + 1)
        local close = string.rep("  ", indent)
        local lines = { "[" }
        for i, item in ipairs(items) do
            lines[#lines + 1] = pad .. item .. (i < #items and "," or "")
        end
        lines[#lines + 1] = close .. "]"
        return table.concat(lines, "\n")
    end

    local function format_inline_table(tbl_id, tbl_range, indent)
        local parts     = {}
        local multiline = tbl_range[1] ~= tbl_range[3]
        for kvp_id, d in cst:iter_semantic(tbl_id) do
            if d.kind == K.KeyValuePair then
                local keys    = cst:get_keys(kvp_id)
                local vi, vd  = cst:get_value(kvp_id)
                if #keys > 0 then
                    local key_parts = {}
                    for _, kd in ipairs(keys) do key_parts[#key_parts + 1] = quote_key(kd.value) end
                    local key_str = table.concat(key_parts, ".")
                    local val_str = (vd and vd.kind ~= K.MissingValue) and format_value(vi, vd, indent + 1) or '""'
                    parts[#parts + 1] = key_str .. " = " .. val_str
                end
            end
        end
        if #parts == 0 then return "{}" end
        if not multiline then
            return "{ " .. table.concat(parts, ", ") .. " }"
        end
        local pad   = string.rep("  ", indent + 1)
        local close = string.rep("  ", indent)
        local lines = { "{" }
        for i, p in ipairs(parts) do
            lines[#lines + 1] = pad .. p .. (i < #parts and "," or "")
        end
        lines[#lines + 1] = close .. "}"
        return table.concat(lines, "\n")
    end

    format_value = function(val_id, val_data, indent)
        indent = indent or 0
        if not val_data then return '""' end
        local k = val_data.kind
        if k == K.String then
            return format_string(val_data.value)
        elseif k == K.Bool then
            return tostring(val_data.value)
        elseif k == K.Float then
            local v = val_data.value
            if v ~= v then return "nan"
            elseif v == math.huge then return "inf"
            elseif v == -math.huge then return "-inf" end
            return tostring(v)
        elseif k == K.Integer then
            return tostring(math.floor(val_data.value))
        elseif k == K.Datetime or k == K.DatetimeLocal or k == K.DateLocal or k == K.TimeLocal then
            return val_data.value  -- already a formatted string
        elseif k == K.Array then
            return format_array(val_id, val_data.range, indent)
        elseif k == K.InlineTable then
            return format_inline_table(val_id, val_data.range, indent)
        end
        return '""'
    end

    local function format_kvp(kvp_id)
        local keys = cst:get_keys(kvp_id)
        if #keys == 0 then return nil end
        local key_parts = {}
        for _, kd in ipairs(keys) do key_parts[#key_parts + 1] = quote_key(kd.value) end
        local vi, vd = cst:get_value(kvp_id)
        local val_str = (vd and vd.kind ~= K.MissingValue) and format_value(vi, vd) or '""'
        local line = table.concat(key_parts, ".") .. " = " .. val_str
        -- append trailing comment if present
        for _, cd in cst:iter_semantic(kvp_id) do
            if cd.kind == K.Comment then line = line .. " " .. cd.text; break end
        end
        return line
    end

    local out   = {}
    local first = true

    for sec_id, d in cst:iter_semantic(cst:root_id()) do
        if d.kind == K.TableSection or d.kind == K.AotSection then
            if not first then out[#out + 1] = "" end
            first = false

            -- find header child
            local hdr_kind = d.kind == K.TableSection and K.TableHeader or K.AotHeader
            local hdr_id
            for cid, cd in cst:iter_semantic(sec_id) do
                if cd.kind == hdr_kind then hdr_id = cid; break end
            end

            local keys = hdr_id and cst:get_keys(hdr_id) or {}
            local key_parts = {}
            for _, kd in ipairs(keys) do key_parts[#key_parts + 1] = quote_key(kd.value) end
            local header = (d.kind == K.AotSection and "[[" or "[")
                        .. table.concat(key_parts, ".")
                        .. (d.kind == K.AotSection and "]]" or "]")

            -- trailing comment from header
            if hdr_id then
                for _, cd in cst:iter_semantic(hdr_id) do
                    if cd.kind == K.Comment then header = header .. " " .. cd.text; break end
                end
            end
            out[#out + 1] = header

            for kvp_id, cd in cst:iter_semantic(sec_id) do
                if cd.kind == K.KeyValuePair then
                    local line = format_kvp(kvp_id)
                    if line then out[#out + 1] = line end
                end
            end

        elseif d.kind == K.KeyValuePair then
            local line = format_kvp(sec_id)
            if line then out[#out + 1] = line; first = false end

        elseif d.kind == K.Comment then
            out[#out + 1] = d.text; first = false
        end
    end

    return table.concat(out, "\n")
end

return M
