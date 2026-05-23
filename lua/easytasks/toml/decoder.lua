-- easytasks/toml/decoder.lua
local parser     = require("easytasks.toml.parser")
local DecodeTree = require("easytasks.toml.DecodeTree")
local vu         = require("easytasks.toml.validatorutils")
local NodeKind   = require("easytasks.toml.NodeKind")

local M = {}

local function date_toml_type(d)
    if d.year and d.hour ~= nil then
        return d.zone ~= nil and "datetime" or "datetime-local"
    elseif d.year then
        return "date-local"
    else
        return "time-local"
    end
end

---@param ast easytasks.toml.Ast
---@return any                       data
---@return easytasks.toml.DecodeTree decode_tree
---@return table[]                   errors
---@return table<string,string>      value_types  path → TOML type
local function evaluate(ast)
    local root    = vim.empty_dict()
    local dt      = DecodeTree.new()
    local errors  = {}
    local path_kinds  = {}
    local value_types = {}

    local dead_end_table = vim.empty_dict()
    local current_table  = root
    local current_path   = ""

    dt:set_range("/", { 0, 0, 0, 0 })
    path_kinds["/"]  = "Table"
    value_types["/"] = "table"

    local eval_value
    eval_value = function(node, path)
        if not node then return nil end

        if node.kind == NodeKind.Literal then
            path_kinds[path] = "Literal"
            local v = node.token.value
            local vt = type(v)
            if vt == "string" then
                value_types[path] = "string"
            elseif vt == "boolean" then
                value_types[path] = "bool"
            elseif vt == "number" then
                value_types[path] = (node.token.numkind == "float") and "float" or "integer"
            elseif vt == "table" and parser.is_date(v) then
                value_types[path] = date_toml_type(v)
            end
            return v
        elseif node.kind == NodeKind.Array then
            path_kinds[path]  = "Array"
            value_types[path] = "array"
            local result = {}
            for index, item_node in ipairs(node.items) do
                local item_path = vu.join_path(path, tostring(index))
                local val = eval_value(item_node, item_path)
                table.insert(result, val)
                dt:set_range(item_path, item_node.range)
            end
            return result
        elseif node.kind == NodeKind.InlineTable then
            path_kinds[path]  = "Table"
            value_types[path] = "table"
            local result = vim.empty_dict()
            for _, pair in ipairs(node.pairs) do
                local key      = pair.key.value
                local pair_path = vu.join_path(path, key)
                if result[key] ~= nil then
                    table.insert(errors, {
                        message = "Duplicate key in inline table: " .. key,
                        range   = pair.key.range or pair.value.range,
                    })
                else
                    local val = eval_value(pair.value, pair_path)
                    result[key] = val
                    dt:set_range(pair_path, {
                        pair.key.range[1], pair.key.range[2],
                        pair.value.range[3], pair.value.range[4],
                    })
                end
            end
            return result
        end

        return nil
    end

    local function process_kvp(node)
        if not node.key or not node.value then return end
        local key           = node.key.value
        local path          = vu.join_path(current_path, key)
        local existing_kind = path_kinds[path]
        if existing_kind then
            local msg = "Duplicate key: " .. key
            if existing_kind == "Table" then
                msg = "Cannot overwrite table structure with key: " .. key
            elseif existing_kind == "ArrayOfTables" then
                msg = "Cannot overwrite array of tables structure with key: " .. key
            end
            table.insert(errors, { message = msg, range = node.key.range or node.range })
        else
            current_table[key] = eval_value(node.value, path)
            dt:set_range(path, node.range)
        end
    end

    for _, root_item in ipairs(ast:get_roots()) do
        local id   = root_item.id
        local node = root_item.data

        if node.kind == NodeKind.TableSection then
            current_table = root
            current_path  = ""
            local invalid = false

            for _, key_token in ipairs(node.keys) do
                local key       = key_token.value
                local next_path = vu.join_path(current_path, key)
                local kind      = path_kinds[next_path]

                if kind and kind ~= "Table" then
                    table.insert(errors, {
                        message = "Cannot redefine non-table target: " .. key,
                        range   = key_token.range or node.range,
                    })
                    invalid = true
                    break
                end

                if current_table[key] == nil then
                    current_table[key] = vim.empty_dict()
                    path_kinds[next_path] = "Table"
                end
                value_types[next_path] = "table"

                current_table = current_table[key]
                current_path  = next_path
                dt:set_range(next_path, key_token.range or node.range)
            end

            if invalid then
                current_table = dead_end_table
                current_path  = "/_error_sink"
            end

            for _, child in ipairs(ast:get_children(id)) do
                if child.data.kind == NodeKind.KeyValuePair then
                    process_kvp(child.data)
                end
            end

        elseif node.kind == NodeKind.ArrayOfTablesSection then
            current_table = root
            current_path  = ""
            local invalid  = false
            local num_keys = #node.keys

            for i, key_token in ipairs(node.keys) do
                local key       = key_token.value
                local next_path = vu.join_path(current_path, key)
                local is_last   = (i == num_keys)

                if is_last then
                    local kind = path_kinds[next_path]
                    if kind and kind ~= "ArrayOfTables" then
                        table.insert(errors, {
                            message = "Cannot redefine non-array target as array of tables: " .. key,
                            range   = key_token.range or node.range,
                        })
                        invalid = true
                        break
                    end

                    if current_table[key] == nil then
                        current_table[key] = {}
                        path_kinds[next_path] = "ArrayOfTables"
                    end
                    value_types[next_path] = "array"

                    local tbl_arr    = current_table[key]
                    local next_tbl   = vim.empty_dict()
                    table.insert(tbl_arr, next_tbl)

                    local arr_idx_path       = vu.join_path(next_path, tostring(#tbl_arr))
                    path_kinds[arr_idx_path] = "Table"
                    value_types[arr_idx_path] = "table"
                    dt:set_range(arr_idx_path, key_token.range or node.range)

                    current_table = next_tbl
                    current_path  = arr_idx_path
                else
                    local kind = path_kinds[next_path]
                    if kind and kind ~= "Table" then
                        table.insert(errors, {
                            message = "Cannot redefine non-table structural ancestor: " .. key,
                            range   = key_token.range or node.range,
                        })
                        invalid = true
                        break
                    end

                    if current_table[key] == nil then
                        current_table[key] = vim.empty_dict()
                        path_kinds[next_path] = "Table"
                    end
                    value_types[next_path] = "table"

                    current_table = current_table[key]
                    current_path  = next_path
                end

                dt:set_range(next_path, key_token.range or node.range)
            end

            if invalid then
                current_table = dead_end_table
                current_path  = "/_error_sink"
            end

            for _, child in ipairs(ast:get_children(id)) do
                if child.data.kind == NodeKind.KeyValuePair then
                    process_kvp(child.data)
                end
            end

        elseif node.kind == NodeKind.KeyValuePair then
            process_kvp(node)
        end
    end

    return root, dt, errors, value_types
end

---@param input string|easytasks.toml.Ast
---@param opts {type_map?: boolean}?
function M.decode(input, opts)
    local ast

    if type(input) == "string" then
        local parsed = parser.parse(input)

        if not parsed.ok then
            return {
                ok          = false,
                data        = nil,
                errors      = parsed.errors,
                decode_tree = DecodeTree.new(),
            }
        end

        ast = parsed.ast
    else
        ast = input
    end

    local data, dt, errors, value_types = evaluate(ast)

    if #errors > 0 then
        return {
            ok          = false,
            data        = nil,
            errors      = errors,
            decode_tree = dt,
        }
    end

    return {
        ok          = true,
        data        = data,
        errors      = {},
        decode_tree = dt,
        type_map    = (opts and opts.type_map) and value_types or nil,
    }
end

return M
