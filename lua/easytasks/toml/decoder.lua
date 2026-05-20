-- easytasks/toml/decoder.lua
local parser = require("easytasks.toml.parser")

local M = {}

local function escape(token)
    token = token:gsub("~", "~0")
    token = token:gsub("/", "~1")
    return token
end

local function join(base, key)
    key = escape(key)

    if base == "" then
        return "/" .. key
    end

    return base .. "/" .. key
end

local function evaluate(ast)
    local root = {}
    local pointer_map = {}
    local errors = {}
    local path_kinds = {}

    -- Fallback dummy context to catch orphaned properties during invalid sections
    local dead_end_table = {}
    local current_table = root
    local current_path = ""

    pointer_map["/"] = { 0, 0, 0, 0 }

    local function register(path, range)
        pointer_map[path] = range
    end

    -- Forward declaration to allow mutually recursive evaluation of arrays and inline tables
    local eval_value

    eval_value = function(node, path)
        if not node then return nil end

        if node.kind == "Literal" then
            path_kinds[path] = "Literal"
            return node.token.value
        elseif node.kind == "Array" then
            path_kinds[path] = "Array"
            local result = {}
            for index, item_node in ipairs(node.items) do
                -- JSON pointers for array indices use 0-based indexing per specification standards
                local item_path = join(path, tostring(index - 1))
                local val = eval_value(item_node, item_path)
                table.insert(result, val)
                register(item_path, item_node.range)
            end
            return result
        elseif node.kind == "InlineTable" then
            path_kinds[path] = "Table"
            local result = {}
            for _, pair in ipairs(node.pairs) do
                local key = pair.key.value
                local pair_path = join(path, key)

                if result[key] ~= nil then
                    table.insert(errors, {
                        message = "Duplicate key in inline table: " .. key,
                        range = pair.key.range or pair.value.range,
                    })
                else
                    local val = eval_value(pair.value, pair_path)
                    result[key] = val
                    register(pair_path, {
                        pair.key.range[1],
                        pair.key.range[2],
                        pair.value.range[3],
                        pair.value.range[4],
                    })
                end
            end
            return result
        end

        return nil
    end

    for _, node in ipairs(ast.body) do
        -- [table]
        if node.kind == "TableSection" then
            current_table = root
            current_path = ""

            local invalid = false

            for _, key_token in ipairs(node.keys) do
                local key = key_token.value
                local next_path = join(current_path, key)
                local kind = path_kinds[next_path]

                if kind and kind ~= "Table" then
                    table.insert(errors, {
                        message = "Cannot redefine non-table target: " .. key,
                        range = key_token.range or node.range,
                    })
                    invalid = true
                    break
                end

                if current_table[key] == nil then
                    current_table[key] = {}
                    path_kinds[next_path] = "Table"
                end

                current_table = current_table[key]
                current_path = next_path

                register(next_path, key_token.range or node.range)
            end

            if invalid then
                current_table = dead_end_table
                current_path = "/_error_sink"
            end

            -- key = value
        elseif node.kind == "KeyValuePair" then
            local key = node.key.value
            local path = join(current_path, key)
            local existing_kind = path_kinds[path]

            if existing_kind then
                local msg = "Duplicate key: " .. key
                if existing_kind == "Table" then
                    msg = "Cannot overwrite table structure with key: " .. key
                end

                table.insert(errors, {
                    message = msg,
                    range = node.key.range or node.range,
                })
            else
                local value = eval_value(node.value, path)
                current_table[key] = value
                register(path, node.range)
            end
        end
    end

    return root, pointer_map, errors
end

---@param input string|table
function M.decode(input)
    local ast

    if type(input) == "string" then
        local parsed = parser.parse(input)

        if not parsed.ok then
            return {
                ok = false,
                data = nil,
                errors = parsed.errors,
                pointer_map = {},
            }
        end

        ast = parsed.ast
    else
        ast = input
    end

    local data, pointer_map, errors = evaluate(ast)

    if #errors > 0 then
        return {
            ok = false,
            data = nil,
            errors = errors,
            pointer_map = pointer_map,
        }
    end

    return {
        ok = true,
        data = data,
        errors = {},
        pointer_map = pointer_map,
    }
end

return M
