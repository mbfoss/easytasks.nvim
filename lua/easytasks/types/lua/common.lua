--- Restricted-environment machinery for the `lua_file` task type: building the
--- curated globals table and running a compiled chunk in it. See the
--- module-level comment in the task type for the security caveats of this
--- "restriction".
local M = {}

-- Names exposed to a lua task: Lua's own standard library plus Neovim's `vim`
-- table. Globals added by plugins/extensions are not exposed, and the obvious
-- escape hatches (`load`, `loadstring`, `require`, `dofile`, `loadfile`,
-- `getfenv`, `setfenv`, `debug`, `package`, `ffi`, `jit`, `_G`) are left out.
--
-- This is NOT a security sandbox. The exposed stdlib tables (`string`, `os`,
-- `io`, `vim`, ...) are the real shared instances, so a task can mutate them
-- process-wide, and `vim` alone is a full escape hatch -- `vim.cmd("lua ...")`,
-- `vim.fn`, `vim.uv`, `os.execute`, etc. all reach the real global environment
-- and the system. The allow-list only keeps honest tasks from *accidentally*
-- leaking globals; treat task code as trusted (same as a Makefile or
-- `.nvim.lua`), not as a confined guest.
M.ALLOWED = {
    -- base library
    "assert", "collectgarbage", "error", "ipairs", "next", "pairs",
    "pcall", "xpcall", "select", "tonumber", "tostring", "type", "unpack",
    "rawequal", "rawget", "rawset", "rawlen", "getmetatable", "setmetatable",
    "_VERSION",
    -- standard library tables
    "string", "table", "math", "coroutine", "os", "io", "bit", "utf8",
    -- neovim
    "vim",
}

--- Build the curated environment table for a chunk: the allow-listed
--- builtins plus the task-specific helpers (`report`, `print`, `task`).
---@param ctx  table run context (must provide `report`)
---@param task table task definition
---@return table
function M.build_env(ctx, task)
    local env = {
        report = ctx.report,
        task   = vim.deepcopy(task or {}),
        print  = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[i] = tostring((select(i, ...)))
            end
            ctx.report(table.concat(parts, "\t"))
        end,
    }
    for _, name in ipairs(M.ALLOWED) do
        if env[name] == nil then env[name] = _G[name] end
    end
    return env
end

--- Run a compiled chunk in the restricted environment built from `task`/`ctx`,
--- then report the outcome via `on_done`. The chunk succeeds unless it raises
--- an error or explicitly returns `false`.
---@param chunk function
---@param ctx table
---@param task table
---@param on_done fun(ok: boolean)
function M.run_chunk(chunk, ctx, task, on_done)
    -- LuaJIT (Neovim's runtime) has no env parameter on load(); use setfenv
    -- to point the chunk's free variables at `env`. This redirects accidental
    -- global writes away from `_G` -- it does not sandbox a determined task.
    if setfenv then setfenv(chunk, M.build_env(ctx, task)) end

    local ok, result = pcall(chunk, ctx)
    if not ok then
        ctx.report("error: " .. tostring(result))
        on_done(false)
        return
    end

    -- A chunk may explicitly `return false` to signal failure.
    on_done(result ~= false)
end

return M
