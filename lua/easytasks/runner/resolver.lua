---@class easytasks.runner.resolver
local M = {}

local expressions = require("easytasks.expressions")

--- Expression syntax
--- ─────────────────
--- A task string is literal text with `{{ … }}` *holes*. Nothing outside a hole
--- is special, so the top level never needs escaping: a bare `$`, `\`, or single
--- `}` is literal, and DAP-style `${var}` passes through untouched. Only the
--- two-character sequence `{{` begins a hole; a bare `}}` outside a hole is
--- already literal. The one escape is `{{!`, which emits a literal `{{`.
---
--- Inside a hole the body is a shell-style word list: whitespace separates the
--- expression *name* (first word) from its *arguments*. An argument may be
--- quoted to include whitespace or a literal `{{`/`}}`:
---   * `'…'` — a literal segment; nothing inside is interpreted (`''` → a `'`).
---   * `"…"` — like `'…'`, but nested `{{ … }}` holes inside it are expanded
---     (`""` → a `"`).
--- There is no backslash escaping and no `,`/`:` separators, so backslashes in a
--- value never collide with TOML's own string escapes.
---
--- The `shell` and `lua` built-ins are *raw-body* expressions (see
--- `expressions.is_raw`): everything after the name is passed to them verbatim —
--- quotes and all — so those sublanguages keep their own quoting. Only nested
--- `{{ … }}` holes are expanded first.
---
--- To emit a literal `{{` in output, write `{{!`. A literal `}}` needs nothing —
--- it is only special *inside* a hole (where it closes one); everywhere else it
--- passes through unchanged. The escape is a top-level construct because holes
--- are located by brace nesting alone (quotes are ignored, so a raw shell body
--- may carry unbalanced quotes); that means a `{{` can never be hidden from the
--- hole finder from *inside* a hole, only escaped before one begins.
---
--- Known limitation: a literal `}}` inside a quoted argument is not supported (it
--- closes the hole early); put such text in ordinary literal output instead.

---@type fun(str: string, open_at: integer): string?, integer?, string?
local _find_span

--- Find the extent of a `{{ … }}` hole. `open_at` is the index of the opening
--- `{{`'s first `{`. Only brace nesting is tracked — a nested `{{ … }}` is
--- consumed recursively so its `}}` cannot close the outer hole. Quotes are
--- irrelevant here (so a raw shell body may contain any quotes); they only
--- matter later, to `_next_token`. Returns the inner text (between the braces)
--- and the index of the closing `}}`'s second `}`.
---@param str     string
---@param open_at integer
---@return string? inner, integer? close_at, string? err
_find_span = function(str, open_at)
    local n = #str
    local i = open_at + 2
    while i <= n do
        local char = str:sub(i, i)
        if char == "{" and str:sub(i + 1, i + 1) == "{" then
            local _, close, err = _find_span(str, i)
            if not close then return nil, nil, err end
            i = close + 1
        elseif char == "}" and str:sub(i + 1, i + 1) == "}" then
            return str:sub(open_at + 2, i - 1), i + 1
        else
            i = i + 1
        end
    end
    return nil, nil, "Unterminated expression"
end

--- Skip a single-quoted literal region. `i` is the opening quote; a doubled
--- quote (`''`) is an escaped literal quote and does not close the region.
---@param str string
---@param i   integer  index of the opening `'`
---@return integer? close_at  index of the closing quote, or nil if unterminated
local function _skip_squote(str, i)
    local n = #str
    local j = i + 1
    while j <= n do
        if str:sub(j, j) == "'" then
            if str:sub(j + 1, j + 1) == "'" then j = j + 2 else return j end
        else
            j = j + 1
        end
    end
    return nil
end

--- Parse a double-quoted region into segments. Literal runs become `{lit=…}`
--- and nested `{{ … }}` holes become `{span=…}`; a doubled quote (`""`) is a
--- literal `"`. Returns the segment list and the index just past the closing
--- quote.
---@param str  string
---@param open integer  index of the opening `"`
---@return {lit?:string, span?:string}[]? segments, integer? next_i, string? err
local function _dquote_segments(str, open)
    local n = #str
    local segs, buf = {}, {}
    local function flush() if #buf > 0 then segs[#segs + 1] = { lit = table.concat(buf) }; buf = {} end end
    local j = open + 1
    while j <= n do
        local char = str:sub(j, j)
        if char == '"' then
            if str:sub(j + 1, j + 1) == '"' then buf[#buf + 1] = '"'; j = j + 2
            else flush(); return segs, j + 1 end
        elseif char == "{" and str:sub(j + 1, j + 1) == "{" then
            local content, close, err = _find_span(str, j)
            if not close then return nil, nil, err end
            flush(); segs[#segs + 1] = { span = content }; j = close + 1
        else
            buf[#buf + 1] = char; j = j + 1
        end
    end
    return nil, nil, "Unterminated quote"
end

--- Parse one whitespace-delimited token from `str` beginning at or after `i`.
--- Bare characters, single-quoted literals, double-quoted regions, and nested
--- `{{ … }}` holes concatenate (like the shell) into a single token as long as
--- no unquoted whitespace separates them. Returns the token as a segment list
--- (`{lit=…}` / `{span=…}`) and the index just past it. When only whitespace or
--- end-of-string remains, the segment list is nil.
---@param str string
---@param i   integer
---@return {lit?:string, span?:string}[]? segments, integer? next_i, string? err
local function _next_token(str, i)
    local n = #str
    while i <= n and str:sub(i, i):match("%s") do i = i + 1 end
    if i > n then return nil, i end
    local segs, buf = {}, {}
    local function flush() if #buf > 0 then segs[#segs + 1] = { lit = table.concat(buf) }; buf = {} end end
    while i <= n do
        local char = str:sub(i, i)
        if char:match("%s") then
            break
        elseif char == "'" then
            local close = _skip_squote(str, i)
            if not close then return nil, nil, "Unterminated quote" end
            buf[#buf + 1] = (str:sub(i + 1, close - 1):gsub("''", "'"))
            i = close + 1
        elseif char == '"' then
            local dsegs, nexti, err = _dquote_segments(str, i)
            if not dsegs then return nil, nil, err end
            flush()
            for _, s in ipairs(dsegs) do segs[#segs + 1] = s end
            i = nexti
        elseif char == "{" and str:sub(i + 1, i + 1) == "{" then
            local content, close, err = _find_span(str, i)
            if not close then return nil, nil, err end
            flush()
            segs[#segs + 1] = { span = content }
            i = close + 1
        else
            buf[#buf + 1] = char
            i = i + 1
        end
    end
    flush()
    return segs, i
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

---@type fun(inner: string, ctx: easytasks.ExpressionCtx): any, string?
local _eval_expression

--- Evaluate one parsed token to a value. A token that is a *sole* nested hole is
--- evaluated type-preservingly (its number/boolean/… survives); any other token
--- is stringified segment by segment into a single string.
---@param token {lit?:string, span?:string}[]
---@param ctx   easytasks.ExpressionCtx
---@return any value, string? err
local function _eval_token(token, ctx)
    if #token == 1 and token[1].span then
        return _eval_expression(token[1].span, ctx)
    end
    local parts = {} ---@type string[]
    for _, seg in ipairs(token) do
        if seg.lit then
            parts[#parts + 1] = seg.lit
        else
            local val, err = _eval_expression(seg.span, ctx)
            if err then return nil, err end
            parts[#parts + 1] = val == nil and "" or tostring(val)
        end
    end
    return table.concat(parts)
end

--- Evaluate a single expression from its *inner* text — the part between `{{` and
--- `}}`. The first whitespace-delimited token is the expression name; the rest
--- are arguments (each parsed by `_next_token` and evaluated by `_eval_token`).
--- Returns the expression's *raw* value; callers decide whether to stringify it
--- (string interpolation) or preserve its type (a sole-expression value; see
--- `_expand_value`).
---
--- A *raw-body* expression (`expressions.is_raw`, e.g. `shell`/`lua`) instead
--- receives everything after its name verbatim — quotes and separators intact,
--- with only nested `{{ … }}` holes expanded — so its sublanguage keeps its own
--- quoting.
---
--- A name that matches no built-in or registered expression is looked up in the
--- inline `[expressions]` table (`ctx.expressions`). Its template is resolved
--- type-preservingly (via `_expand_value`), so an inline definition may reference
--- other expressions; a cycle guard (`ctx._resolving`) turns runaway recursion
--- into an error. An inline expression may take positional arguments: they are
--- evaluated in the caller's scope and exposed inside the template as `{{1}}`,
--- `{{2}}`, … via a per-call argument frame pushed onto `ctx._args`. A wholly
--- numeric name is always such a positional reference, never a lookup.
---@param inner string
---@param ctx   easytasks.ExpressionCtx
---@return any value, string? err
_eval_expression = function(inner, ctx)
    local name_seg, name_end_opt, terr = _next_token(inner, 1)
    if terr then return nil, terr end
    if not name_seg then return nil, "Unknown expression: ''" end
    local name_end = name_end_opt --[[@as integer]]

    local name, nerr = _eval_token(name_seg, ctx)
    if nerr then return nil, nerr end
    name = vim.trim(tostring(name == nil and "" or name))
    if name == "" then return nil, "Unknown expression: ''" end

    -- Positional argument reference (`{{1}}`, `{{2}}`, …) inside an inline template.
    if name:match("^%d+$") then
        local frame = ctx._args and ctx._args[#ctx._args]
        if not frame then
            return nil, "positional argument {{" .. name .. "}} used outside an inline expression"
        end
        local idx = tonumber(name)
        if idx < 1 or idx > frame.n then
            return nil, ("no argument {{%s}} (inline expression received %d)"):format(name, frame.n)
        end
        return frame[idx]
    end

    -- Collect the remaining tokens as arguments.
    ---@type {lit?:string, span?:string}[][]
    local arg_tokens = {}
    local i = name_end
    while true do
        local seg, nexti, err = _next_token(inner, i)
        if err then return nil, err end
        if not seg then break end
        arg_tokens[#arg_tokens + 1] = seg
        i = nexti
    end

    local fn = expressions.get(name)
    if not fn then
        local template = ctx.expressions and ctx.expressions[name]
        if template == nil then return nil, "Unknown expression: '" .. name .. "'" end
        -- Evaluate the call arguments in the caller's scope, type-preservingly, so
        -- a sole `{{1}}` in the template keeps a number/boolean argument intact.
        local frame = { n = #arg_tokens }
        for k, token in ipairs(arg_tokens) do
            local aval, aerr = _eval_token(token, ctx)
            if aerr then
                return nil, ("in inline expression `%s` argument %d: %s"):format(name, k, aerr)
            end
            frame[k] = aval
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
    if expressions.is_raw(name) then
        -- Everything after the name, verbatim (nested holes expanded).
        local raw = vim.trim(inner:sub(name_end))
        local body, berr = _expand_recursive(raw, ctx)
        if berr then return nil, berr end
        expression_args[2] = body
    else
        for _, token in ipairs(arg_tokens) do
            local arg, arg_err = _eval_token(token, ctx)
            if arg_err then return nil, arg_err end
            expression_args[#expression_args + 1] = arg
        end
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

--- Expand a string value as interpolation: literal text is copied through and
--- every `{{ … }}` hole is stringified into place. The top level has no escaping,
--- so backslashes and lone braces are literal.
---@param str string
---@param ctx easytasks.ExpressionCtx
---@return string|nil result, string|nil err
_expand_recursive = function(str, ctx)
    local res = {}   ---@type string[]
    local n, i = #str, 1
    while i <= n do
        local open = str:find("{{", i, true)
        if not open then
            res[#res + 1] = str:sub(i)
            break
        end
        if open > i then res[#res + 1] = str:sub(i, open - 1) end
        if str:sub(open + 2, open + 2) == "!" then
            -- `{{!` is the escape for a literal `{{` (the only sequence special
            -- at the top level; a bare `}}` is already literal).
            res[#res + 1] = "{{"
            i = open + 3
        else
            local content, close, err = _find_span(str, open)
            if not close then return nil, err end
            local val, eval_err = _eval_expression(content --[[@as string]], ctx)
            if eval_err then return nil, eval_err end
            res[#res + 1] = val == nil and "" or tostring(val)
            i = close + 1
        end
    end
    return table.concat(res)
end

--- Expand a single (string) value. When the *entire* trimmed value is one hole
--- (`"{{ name args }}"`), the expression's raw value is returned, so non-string
--- types (numbers, booleans, …) survive intact. Otherwise the value is treated
--- as string interpolation and every hole's result is stringified into place.
---@param str string
---@param ctx easytasks.ExpressionCtx
---@return any value, string? err
_expand_value = function(str, ctx)
    local trimmed = vim.trim(str)
    if trimmed:sub(1, 2) == "{{" and trimmed:sub(3, 3) ~= "!" then
        local content, close = _find_span(trimmed, 1)
        if content ~= nil and close == #trimmed then
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
