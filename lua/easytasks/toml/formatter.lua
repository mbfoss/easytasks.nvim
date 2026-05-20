-- easytasks/toml/formatter.lua
local M = {}

---@class easytasks.FormatOptions
---@field indent string|nil
---@field newline string|nil
---@field trailing_newline boolean|nil

local DEFAULTS = {
    indent = "    ",
    newline = "\n",
    trailing_newline = true,
}

local function merge_options(opts)
    opts = opts or {}

    return {
        indent = opts.indent or DEFAULTS.indent,
        newline = opts.newline or DEFAULTS.newline,
        trailing_newline = opts.trailing_newline ~= false,
    }
end

local function write(buf, str)
    table.insert(buf, str)
end

local function format_literal(node)
    local t = node.token

    if t.type == "STRING" then
        return string.format("%q", t.value)
    elseif t.type == "BOOLEAN" then
        return t.value and "true" or "false"
    else
        return tostring(t.value)
    end
end

local function format_key(token)
    if not token then return "" end
    if token.type == "STRING" then
        return string.format("%q", token.value)
    end

    return tostring(token.value)
end

local format_value

local function format_array(node)
    local out = {}
    write(out, "[")

    for i, item in ipairs(node.items) do
        if i > 1 then
            write(out, ", ")
        end
        write(out, format_value(item))
    end

    write(out, "]")
    return table.concat(out)
end

local function format_inline_table(node)
    local out = {}
    write(out, "{")

    for i, pair in ipairs(node.pairs) do
        if i > 1 then
            write(out, ", ")
        end
        write(out, format_key(pair.key))
        write(out, " = ")
        write(out, format_value(pair.value))
    end

    write(out, "}")
    return table.concat(out)
end

format_value = function(node)
    if not node then return "" end
    if node.kind == "Literal" then
        return format_literal(node)
    elseif node.kind == "Array" then
        return format_array(node)
    elseif node.kind == "InlineTable" then
        return format_inline_table(node)
    end

    error("Unsupported value node: " .. tostring(node.kind))
end

local function format_table_section_keys(keys)
    local out = {}
    for i, key in ipairs(keys) do
        if i > 1 then
            write(out, ".")
        end
        write(out, format_key(key))
    end
    return table.concat(out)
end

---@param ast table
---@param opts easytasks.FormatOptions|nil
---@return string
function M.format(ast, opts)
    opts = merge_options(opts)

    local nl = opts.newline
    local out = {}
    local previous_was_table = false

    -- Adapt to the new Tree walking API design
    ast:walk_tree(function(_, node, _)
        if node.kind == "TableSection" then
            if #out > 0 then
                write(out, nl)
                if previous_was_table then
                    write(out, nl)
                end
            end

            write(out, "[" .. format_table_section_keys(node.keys) .. "]")
            previous_was_table = true
        elseif node.kind == "PartialTableSection" then
            if #out > 0 then
                write(out, nl)
            end
            -- Output whatever section text has been typed so far
            write(out, "[" .. format_table_section_keys(node.keys))
            previous_was_table = false
        elseif node.kind == "KeyValuePair" then
            if #out > 0 then
                write(out, nl)
            end

            if node.value then
                write(out, format_key(node.key) .. " = " .. format_value(node.value))
            else
                -- Incomplete value assignments like `key = `
                write(out, format_key(node.key) .. " = ")
            end
            previous_was_table = false
        elseif node.kind == "PartialKeyValuePair" then
            if #out > 0 then
                write(out, nl)
            end
            -- Dangling keywords/prefixes that don't have an equal sign assignment yet
            write(out, format_key(node.key))
            previous_was_table = false
        elseif node.kind == "Comment" or (node.token and node.token.type == "COMMENT") then
            if #out > 0 then
                write(out, nl)
            end

            local comment_text = node.token and node.token.value or node.value or ""
            write(out, comment_text)
            previous_was_table = false
        end

        return true -- Always continue traversing structural siblings
    end)

    if #out > 0 and opts.trailing_newline then
        write(out, nl)
    end

    return table.concat(out)
end

return M
