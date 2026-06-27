local lua_type = require("easytasks.types.lua")

--- Run a `lua` task synchronously and collect its reported output + result.
---@param task table
---@return boolean ok
---@return string[] reported
local function run(task)
    local reported = {}
    local result
    local ctx = {
        tasks  = {},
        report = function(msg) table.insert(reported, msg) end,
    }
    lua_type.start(task, ctx, function(ok) result = ok end)
    return result, reported
end

describe("lua task", function()
    local prev_notify
    local notifications

    before_each(function()
        -- Capture notifications instead of letting ERROR-level ones write to
        -- stderr (which the headless harness reports as a spurious error).
        notifications = {}
        prev_notify = vim.notify
        vim.notify = function(msg) table.insert(notifications, msg) end
    end)

    after_each(function()
        vim.notify = prev_notify
    end)

    it("runs an inline script and reports its output", function()
        local ok, out = run({
            name = "hello",
            type = "lua",
            script = "print('hello from script')\nreturn true",
        })
        assert.is_true(ok)
        assert.are.same({ "hello from script" }, out)
    end)

    it("runs in a restricted environment", function()
        local ok, out = run({
            name = "envtask",
            type = "lua",
            script = "print('vim=' .. tostring(vim ~= nil))\n"
                .. "print('require=' .. tostring(require ~= nil))",
        })
        assert.is_true(ok)
        assert.are.same({ "vim=true", "require=false" }, out)
    end)

    it("fails when the chunk returns false", function()
        local ok = run({ name = "t", type = "lua", script = "return false" })
        assert.is_false(ok)
    end)

    it("fails when the chunk raises an error", function()
        local ok, out = run({ name = "t", type = "lua", script = "error('boom')" })
        assert.is_false(ok)
        assert.is_true(#out >= 1 and out[#out]:match("boom") ~= nil)
    end)

    it("fails cleanly when the script does not compile", function()
        local ok, out = run({ name = "t", type = "lua", script = "this is not lua" })
        assert.is_false(ok)
        assert.is_true(out[#out]:match("cannot compile lua script") ~= nil)
    end)

    it("fails when no script is given", function()
        local ok = run({ name = "t", type = "lua" })
        assert.is_false(ok)
        assert.is_true(#notifications >= 1)
        assert.is_true(notifications[#notifications]:match("has no script") ~= nil)
    end)
end)
