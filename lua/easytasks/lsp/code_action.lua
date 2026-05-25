local M      = {}

local Cst    = require("easytasks.toml.Cst")
local K      = Cst.Kind

local kind_names = {}
for name, v in pairs(K) do kind_names[v] = name end

--------------------------------------------------------------------------------
-- Dump helpers
--------------------------------------------------------------------------------

local function dump_cst_to_string(cst)
    local lines = { "# --- Easytasks TOML CST Dump ---", "#" }
    if not cst or type(cst.walk) ~= "function" then
        table.insert(lines, "# No valid CST instance found.")
    else
        cst:walk(function(id, data, depth)
            local indent = string.rep("  ", depth or 0)
            local kind   = kind_names[data.kind] or ("Kind#" .. tostring(data.kind))
            local info   = string.format("# %s* [%s] id:%s", indent, kind, id)
            if data.range then
                info = info .. string.format(" (%d,%d)->(%d,%d)",
                    data.range[1], data.range[2], data.range[3], data.range[4])
            end
            if data.text  then info = info .. string.format(" text:%q", data.text) end
            if data.value ~= nil then info = info .. string.format(" val:%s", tostring(data.value)) end
            table.insert(lines, info)
            return true
        end)
    end
    return table.concat(lines, "\n") .. "\n"
end

local function serialize_val(val, depth)
    depth = depth or 0
    local indent = string.rep("  ", depth)
    if type(val) == "table" then
        local parts = { "{\n" }
        for k, v in pairs(val) do
            local ks = type(k) == "string" and string.format("[%q]", k) or string.format("[%s]", tostring(k))
            table.insert(parts, string.format("%s  %s = %s,\n", indent, ks, serialize_val(v, depth + 1)))
        end
        table.insert(parts, indent .. "}")
        return table.concat(parts)
    elseif type(val) == "string" then
        return string.format("%q", val)
    else
        return tostring(val)
    end
end

local function dump_decoder_to_string(data)
    local lines = { "# --- Easytasks TOML Decoded Data Dump ---", "#" }
    if not data then
        table.insert(lines, "# No decoded data available.")
    else
        for line in serialize_val(data):gmatch("[^\r\n]+") do
            table.insert(lines, "# " .. line)
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

local function dump_decode_tree_to_string(decode_tree)
    local lines = { "# --- Easytasks TOML DecodeTree Dump ---", "#" }
    if not decode_tree or type(decode_tree._tree) ~= "table"
            or type(decode_tree._tree.walk_tree) ~= "function" then
        table.insert(lines, "# No valid DecodeTree instance found.")
    else
        decode_tree:walk_tree(function(id, data, depth)
            local indent = string.rep("  ", depth or 0)
            local info   = string.format("# %s* [id:%s] key:%q", indent, tostring(id), tostring(data.key))
            if data.ranges and #data.ranges > 0 then
                local parts = {}
                for _, r in ipairs(data.ranges) do
                    parts[#parts + 1] = string.format("(%d,%d)->(%d,%d)", r[1], r[2], r[3], r[4])
                end
                info = info .. " ranges:[" .. table.concat(parts, ", ") .. "]"
            else
                info = info .. " ranges:[]"
            end
            if data.schema then
                info = info .. string.format(" schema:{type=%s}", tostring(data.schema.type or "?"))
            end
            if data.errors and #data.errors > 0 then
                info = info .. string.format(" errors:[%s]", table.concat(data.errors, "; "))
            end
            table.insert(lines, info)
            return true
        end)
    end
    return table.concat(lines, "\n") .. "\n"
end

local function dump_errors_to_string(parse_results)
    local lines  = { "# --- Easytasks Active Diagnostics Error Dump ---", "#" }
    local errors = parse_results and parse_results.errors or {}
    if #errors == 0 then
        table.insert(lines, "# No active parsing, semantic, or validation errors found.")
    else
        for i, err in ipairs(errors) do
            local range_str = ""
            if err.range then
                range_str = string.format(" (%d,%d)->(%d,%d)",
                    err.range[1], err.range[2], err.range[3], err.range[4])
            end
            table.insert(lines, string.format("# [%d] Error%s: %s",
                i, range_str, err.message or err.err_msg or tostring(err)))
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

--------------------------------------------------------------------------------
-- Handler
--------------------------------------------------------------------------------

---@param context easytasks.LspBufferContext
---@param params lsp.CodeActionParams
---@param callback fun(err?: lsp.ResponseError, result?: lsp.CodeAction[])
function M.handler(context, params, callback)
    local actions = {}
    local row     = params.range.start.line

    if not context.cst then callback(nil, actions); return end

    local function insert_action(title, text_content)
        table.insert(actions, {
            title = title,
            kind  = vim.lsp.protocol.CodeActionKind.RefactorExtract,
            edit  = {
                changes = {
                    [params.textDocument.uri] = {
                        {
                            range   = { start = { line = row + 1, character = 0 },
                                        ["end"] = { line = row + 1, character = 0 } },
                            newText = text_content,
                        }
                    }
                }
            }
        })
    end

    insert_action("Dump Easytasks TOML CST", dump_cst_to_string(context.cst))
    insert_action("Dump Easytasks DecodeTree", dump_decode_tree_to_string(context.decode_tree))
    insert_action("Dump Easytasks Decoded Data", dump_decoder_to_string(
        context.parse_results and context.parse_results.data))
    insert_action("Dump Active Diagnostics Errors", dump_errors_to_string(context.parse_results))

    callback(nil, actions)
end

return M
