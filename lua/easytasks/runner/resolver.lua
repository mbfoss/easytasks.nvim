---@class easytasks.runner.resolver
local M = {}

local expressions = require("easytasks.expressions")

--- The escapable characters. A backslash before one of these makes it literal;
--- a backslash before anything else is itself a literal backslash. This single
--- rule is the *only* escaping mechanism in expression values — there is no
--- quoting and no `$$`. See `_unescape` for where the escapes are resolved.
---   * `$` — so `\${…}` (or a bare `\$`) is a literal `$`, not an expression start
---   * `,` — a literal comma inside an argument, not an argument separator
---   * `}` — a literal brace inside an argument, not the end of the `${…}` span
---   * `\` — a literal backslash (needed only right before another escapable char)
---@type table<string, boolean>
local _escapable = { ["$"] = true, [","] = true, ["}"] = true, ["\\"] = true }

--- Find the extent of a `${...}` span and return its inner text. `start_pos`
--- points at the opening `{`. Two things are skipped while looking for the
--- matching `}`, so they cannot end the span prematurely:
---   * an escaped character — a backslash shields the following character, so
---     `\}` never terminates the span, and
---   * a nested `${...}` (consumed recursively, as an opaque unit).
--- These rules mirror exactly what `_parse_body` applies when it later splits the
--- same body, so the span found here and the split agree. The returned content is
--- still *escaped*: escapes are resolved later, when the content is expanded.
---@param str       string
---@param start_pos integer  index of the opening `{`
---@return string|nil content, integer|nil end_pos, string|nil err
local function _parse_nested(str, start_pos)
    local n = #str
    local i = start_pos + 1  -- first char of the body
    while i <= n do
        local char = str:sub(i, i)
        if char == "\\" then
            i = i + 2  -- skip the escaped character, whatever it is
        elseif char == "$" and str:sub(i + 1, i + 1) == "{" then
            local _, close, err = _parse_nested(str, i + 1)
            if not close then return nil, nil, err end
            i = close + 1
        elseif char == "}" then
            return str:sub(start_pos + 1, i - 1), i
        else
            i = i + 1
        end
    end
    return nil, nil, "Unterminated expression"
end

--- Resolve backslash escapes in a fully-literal segment (one that contains no
--- unexpanded `${...}` span). `\` + an escapable char yields that char; `\`
--- before anything else is kept as a literal backslash. This is the sole place
--- escapes are consumed, so every escape is resolved exactly once.
---@param str string
---@return string
local function _unescape(str)
    if not str:find("\\", 1, true) then return str end
    local out = {}
    local i, n = 1, #str
    while i <= n do
        local char = str:sub(i, i)
        if char == "\\" and _escapable[str:sub(i + 1, i + 1)] then
            out[#out + 1] = str:sub(i + 1, i + 1)
            i = i + 2
        else
            out[#out + 1] = char
            i = i + 1
        end
    end
    return table.concat(out)
end

--- Split a raw expression body into a name and arguments. The first top-level `:`
--- ends the name and begins the argument list; subsequent top-level `:` are
--- literal, and top-level `,` separate arguments. To keep a comma, a closing
--- brace, or a literal `$` inside a single argument, escape it with a backslash
--- (`\,`, `\}`, `\$`); a literal backslash is `\\`. Because `shell`/`lua` re-join
--- their arguments on `,`, commands and snippets with commas need no escaping.
---
--- Splitting runs on the *unexpanded* template and copies `${...}` spans verbatim,
--- so separators produced by an expression's output can never be mistaken for
--- argument boundaries, and the escapes inside a span survive to be resolved when
--- it is expanded. This function only *splits*; the escapes in the name and each
--- argument are resolved later (by `_expand_recursive`), so each is returned still
--- escaped. An empty argument region (`${name:}`) yields no arguments, and
--- `${name:a,}` yields two (`"a"`, `""`).
---@param inner string
---@return string name, string[] args
local function _parse_body(inner)
    local name          ---@type string?
    local args    = {}  ---@type string[]
    local cur     = {}  ---@type string[]
    local in_args = false   -- have we passed the name and entered the arg list?
    local i, n = 1, #inner
    while i <= n do
        local char = inner:sub(i, i)
        if char == "\\" then
            -- Copy the backslash and the char it shields verbatim; the escape is
            -- resolved later, and an escaped `,`/`}` cannot act as a separator here.
            cur[#cur + 1] = inner:sub(i, i + 1)
            i = i + 2
        elseif char == "$" and inner:sub(i + 1, i + 1) == "{" then
            -- Copy a nested expression span verbatim so its own separators and
            -- escapes survive to be re-parsed when it is expanded.
            local _, end_pos = _parse_nested(inner, i + 1)
            if not end_pos then -- unterminated; copy the remainder verbatim
                cur[#cur + 1] = inner:sub(i)
                break
            end
            cur[#cur + 1] = inner:sub(i, end_pos)
            i = end_pos + 1
        elseif char == ":" and not in_args then
            name, cur, in_args = table.concat(cur), {}, true
            i = i + 1
        elseif char == "," and in_args then
            args[#args + 1] = table.concat(cur)
            cur = {}
            i = i + 1
        else
            cur[#cur + 1] = char
            i = i + 1
        end
    end
    if not in_args then return table.concat(cur), args end
    -- finalize the last argument unless the region was empty
    local last = table.concat(cur)
    if last ~= "" or #args > 0 then args[#args + 1] = last end
    return name --[[@as string]], args
end

local function _async_call(fn, args)
    local parent_co = coroutine.running()
    vim.schedule(function()
        coroutine.wrap(function()
            local ret = vim.F.pack_len(pcall(fn, unpack(args)))
            coroutine.resume(parent_co, vim.F.unpack_len(ret))
        end)()
    end)
    return coroutine.yield()
end

---@type fun(str: string, ctx: easytasks.ExpressionCtx): string?, string?
local _expand_recursive

---@type fun(str: string, ctx: easytasks.ExpressionCtx): any, string?
local _expand_value

--- Evaluate a single expression from its *raw* inner text — the part between `${` and
--- `}`, with nested expressions still unexpanded. The body is split into name + args
--- on the raw template (so a nested expression's output can never be mistaken for an
--- argument boundary), then the name and each argument are expanded
--- individually before the expression is called. Returns the expression's *raw* value;
--- callers decide whether to stringify it (string interpolation) or preserve its
--- type (a sole-expression value; see `_expand_value`).
---
--- A name that matches no built-in or registered expression is looked up in the
--- inline `[expressions]` table (`ctx.expressions`). Its template is resolved
--- type-preservingly (via `_expand_value`), so an inline definition may reference
--- other expressions; a cycle guard (`ctx._resolving`) turns runaway recursion
--- into an error. An inline expression may take positional arguments: they are
--- evaluated in the caller's scope and exposed inside the template as `${1}`,
--- `${2}`, … via a per-call argument frame pushed onto `ctx._args`. A wholly
--- numeric name is always such a positional reference, never a lookup.
---@param inner string
---@param ctx   easytasks.ExpressionCtx
---@return any value, string? err
local function _eval_expression(inner, ctx)
    local name_raw, args_raw = _parse_body(inner)
    local name, err = _expand_recursive(name_raw, ctx)
    if err then return nil, err end
    if not name then return nil, "Expression expansion returned nil" end
    name = vim.trim(name)
    if name == "" then return nil, "Unknown expression: ''" end

    -- Positional argument reference (`${1}`, `${2}`, …) inside an inline template.
    if name:match("^%d+$") then
        local frame = ctx._args and ctx._args[#ctx._args]
        if not frame then
            return nil, "positional argument ${" .. name .. "} used outside an inline expression"
        end
        local idx = tonumber(name)
        if idx < 1 or idx > frame.n then
            return nil, ("no argument ${%s} (inline expression received %d)"):format(name, frame.n)
        end
        return frame[idx]
    end

    local fn = expressions.get(name)
    if not fn then
        local template = ctx.expressions and ctx.expressions[name]
        if template == nil then return nil, "Unknown expression: '" .. name .. "'" end
        -- Evaluate the call arguments in the caller's scope, type-preservingly, so
        -- a sole `${1}` in the template keeps a number/boolean argument intact.
        local frame = { n = #args_raw }
        for i, raw in ipairs(args_raw) do
            local aval, aerr = _expand_value(raw, ctx)
            if aerr then
                return nil, ("in inline expression `%s` argument %d: %s"):format(name, i, aerr)
            end
            frame[i] = aval
        end
        local resolving = ctx._resolving or {}
        ctx._resolving = resolving
        if resolving[name] then return nil, "Expression cycle detected: '" .. name .. "'" end
        resolving[name] = true
        local args_stack = ctx._args or {}
        ctx._args = args_stack
        args_stack[#args_stack + 1] = frame
        local val, expand_err = _expand_value(template, ctx)
        args_stack[#args_stack] = nil
        resolving[name] = nil
        if expand_err then
            return nil, ("in inline expression `%s`: %s"):format(name, expand_err)
        end
        return val
    end

    local expression_args = { ctx } ---@type any[]
    for _, raw in ipairs(args_raw) do
        local arg, arg_err = _expand_recursive(raw, ctx)
        if arg_err then return nil, arg_err end
        expression_args[#expression_args + 1] = arg
    end

    local status, val, expression_err = _async_call(fn, expression_args)
    if not status then
        return nil, "[" .. name .. "] Expression crashed: " .. tostring(val)
    end
    if val == nil and expression_err then
        return nil, "[" .. name .. "] " .. tostring(expression_err)
    end
    local valtype = type(val)
    if valtype ~= "nil" and valtype ~= "boolean" and valtype ~= "number" and valtype ~= "string" then
        return nil, "[" .. name .. "] Invalid return type: " .. valtype
    end
    return val
end

---@param str string
---@param ctx easytasks.ExpressionCtx
---@return string|nil result, string|nil err
_expand_recursive = function(str, ctx)
    local res = {}   ---@type string[]
    local lit = {}   ---@type string[] pending literal run, flushed (unescaped) at each span
    local i, n = 1, #str
    while i <= n do
        local char = str:sub(i, i)
        if char == "\\" then
            -- Keep the escape intact for `_unescape`; an escaped `$` therefore
            -- cannot start an expression.
            lit[#lit + 1] = str:sub(i, i + 1)
            i = i + 2
        elseif char == "$" and str:sub(i + 1, i + 1) == "{" then
            local content, end_pos, parse_err = _parse_nested(str, i + 1)
            if parse_err then return nil, parse_err end
            if not content then return nil, "Failed to parse expression content" end

            local val, eval_err = _eval_expression(content, ctx)
            if eval_err then return nil, eval_err end

            res[#res + 1] = _unescape(table.concat(lit))
            lit = {}
            res[#res + 1] = tostring(val or "")
            i = end_pos + 1
        else
            lit[#lit + 1] = char
            i = i + 1
        end
    end
    res[#res + 1] = _unescape(table.concat(lit))
    return table.concat(res)
end

--- Expand a single (string) value. When the *entire* trimmed value is one expression
--- (`"${name:args}"`), the expression's raw value is returned, so non-string types
--- (numbers, booleans, …) survive intact. Otherwise the value is treated as
--- string interpolation and every expression result is stringified into place.
---@param str string
---@param ctx easytasks.ExpressionCtx
---@return any value, string? err
_expand_value = function(str, ctx)
    local trimmed = vim.trim(str)
    if trimmed:sub(1, 2) == "${" then
        local content, end_pos, parse_err = _parse_nested(trimmed, 2)
        if not parse_err and content and end_pos == #trimmed then
            return _eval_expression(content, ctx)
        end
    end
    return _expand_recursive(str, ctx)
end

--- Human-readable path to a nested key, for error messages: array indices use
--- `[i]`, map keys are dotted (`env.PATH`).
---@param path string?
---@param key any
---@return string
local function _keylabel(path, key)
    if type(key) == "number" then return (path or "") .. "[" .. key .. "]" end
    return path and (path .. "." .. tostring(key)) or tostring(key)
end

---@param tbl  table
---@param seen table
---@param ctx  easytasks.ExpressionCtx
---@param path string?  dotted key path to `tbl`, prefixed onto error messages
---@return boolean ok, string? err
local function _expand_table(tbl, seen, ctx, path)
    seen = seen or {}
    if seen[tbl] then return true end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        local keypath = _keylabel(path, k)
        if type(v) == "table" then
            local ok, err = _expand_table(v, seen, ctx, keypath)
            if not ok then return false, err end
        elseif type(v) == "string" then
            local res, err = _expand_value(v, ctx)
            if err then return false, ("in `%s`: %s"):format(keypath, err) end
            tbl[k] = res
        end
    end
    return true
end

---@param val      any                    string or table to expand
---@param ctx      easytasks.ExpressionCtx
---@param callback fun(ok: boolean, result: any, err: string?)
function M.resolve_expressions(val, ctx, callback)
    coroutine.wrap(function()
        local call_ok, call_ret = xpcall(function()
            if type(val) == "table" then
                local tbl = vim.deepcopy(val)
                local ok, err = _expand_table(tbl, {}, ctx)
                if not ok then error(err) end
                return tbl
            elseif type(val) == "string" then
                local res, err = _expand_value(val, ctx)
                if err then error(err) end
                return res
            else
                return val
            end
        end, debug.traceback)

        local ok, result, err
        if call_ok then
            ok     = true
            result = call_ret
        else
            ok  = false
            err = call_ret
            if type(err) == "string" then
                local clean = err:match(":%d+: (.*)\nstack traceback:")
                if clean then err = clean end
            end
        end

        vim.schedule(function() callback(ok, result, err) end)
    end)()
end

return M
