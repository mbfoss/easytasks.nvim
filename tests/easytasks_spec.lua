local runner   = require("easytasks.runner")
local resolver = require("easytasks.runner.resolver")
local et       = require("easytasks")
local types    = require("easytasks.types")

--- Write `contents` to a temp file and return its path.
---@param contents string
---@return string
local function _tmp_tasks(contents)
    local path = vim.fn.tempname() .. "_tasks.lua"
    vim.fn.writefile(vim.split(contents, "\n", { plain = true }), path)
    return path
end

describe("constructors", function()
    it("tag the spec with its type", function()
        assert.are.same("run", types.run({ command = "x" }).type)
        assert.are.same("composite", types.composite({}).type)
        assert.are.same("debug", types.debug({ adapter = "a" }).type)
        assert.are.same("run", types.task("run", {}).type)
    end)

    it("expose constructors for registered types via metatable", function()
        -- unknown type names do not produce a constructor
        assert.is_nil(types.definitely_not_a_type)
        -- a registered custom type gets an auto-generated constructor
        et.register_task_type("smoketype", { start = function(_, _, d) d(true) end })
        assert.is_function(types.smoketype)
        assert.are.same("smoketype", types.smoketype({}).type)
    end)
end)

describe("loading tasks.lua", function()
    it("lists tasks from a map", function()
        local path = _tmp_tasks([[
local t = require("easytasks.types")
return {
  build = t.run { command = "make" },
  test  = t.run { command = "make test", depends_on = { "build" } },
}
]])
        local names, by_name, err = runner.list_tasks(path)
        assert.is_nil(err)
        assert.are.same({ "build", "test" }, names)
        assert.are.same("make", by_name.build.command)
        assert.are.same("run", by_name.test.type)
    end)

    it("accepts an array with explicit names", function()
        local path = _tmp_tasks([[
local t = require("easytasks.types")
return {
  t.run { name = "a", command = "x" },
  t.run { name = "b", command = "y" },
}
]])
        local names, _, err = runner.list_tasks(path)
        assert.is_nil(err)
        assert.are.same({ "a", "b" }, names)
    end)

    it("reports a syntax error", function()
        local path = _tmp_tasks("return {{{")
        local names, _, err = runner.list_tasks(path)
        assert.is_nil(names)
        assert.is_not_nil(err)
    end)
end)

describe("resolve_values", function()
    it("replaces function-valued fields with their result", function()
        local task = {
            type    = "run",
            command = function() return "computed" end,
            args    = { "static", function() return "dynamic" end },
        }
        local done, result, ok
        resolver.resolve_values(task, { task = task, tasks = {} }, function(o, r)
            ok, result, done = o, r, true
        end)
        vim.wait(1000, function() return done end)
        assert.is_true(ok)
        assert.are.same("computed", result.command)
        assert.are.same({ "static", "dynamic" }, result.args)
        -- the original table is not mutated
        assert.is_function(task.command)
    end)

    it("aborts when a function returns (nil, err)", function()
        local task = { command = function() return nil, "boom" end }
        local done, err, ok
        resolver.resolve_values(task, { task = task, tasks = {} }, function(o, _, e)
            ok, err, done = o, e, true
        end)
        vim.wait(1000, function() return done end)
        assert.is_false(ok)
        assert.is_not_nil(err and err:match("boom"))
    end)
end)

describe("bootstrap", function()
    local bootstrap = require("easytasks.bootstrap")

    ---@return string dir
    local function _tmp_dir()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        return dir
    end

    ---@param luarc string  path to a .luarc.json
    ---@return integer  number of library entries ending in /meta
    local function _meta_count(luarc)
        local cfg = vim.json.decode(table.concat(vim.fn.readfile(luarc), "\n"))
        local n = 0
        for _, entry in ipairs(cfg["Lua.workspace.library"] or {}) do
            if entry:match("[/\\]meta$") then n = n + 1 end
        end
        return n
    end

    it("scaffolds a loadable tasks file and a valid .luarc.json", function()
        local dir = _tmp_dir()
        bootstrap.run(dir)

        local tasks = vim.fs.joinpath(dir, "tasks.lua")
        local luarc = vim.fs.joinpath(dir, ".luarc.json")
        assert.are.same(1, vim.fn.filereadable(tasks))
        assert.are.same(1, vim.fn.filereadable(luarc))

        local names, _, err = runner.list_tasks(tasks)
        assert.is_nil(err)
        assert.is_true(vim.tbl_contains(names, "hello"))

        assert.are.same(1, _meta_count(luarc))
    end)

    it("is idempotent (meta added once, tasks file untouched)", function()
        local dir = _tmp_dir()
        bootstrap.run(dir)
        local tasks = vim.fs.joinpath(dir, "tasks.lua")
        vim.fn.writefile({ "-- edited by hand", "return {}" }, tasks)

        bootstrap.run(dir)

        assert.are.same(1, _meta_count(vim.fs.joinpath(dir, ".luarc.json")))
        assert.are.same("-- edited by hand", vim.fn.readfile(tasks)[1])
    end)

    it("merges into an existing .luarc.json, preserving keys", function()
        local dir = _tmp_dir()
        local luarc = vim.fs.joinpath(dir, ".luarc.json")
        vim.fn.writefile({ vim.json.encode({
            ["Lua.runtime.version"]     = "Lua 5.1",
            ["Lua.workspace.library"]   = { "/some/existing/lib" },
        }) }, luarc)

        bootstrap.run(dir)

        local cfg = vim.json.decode(table.concat(vim.fn.readfile(luarc), "\n"))
        assert.are.same("Lua 5.1", cfg["Lua.runtime.version"])
        assert.is_true(vim.tbl_contains(cfg["Lua.workspace.library"], "/some/existing/lib"))
        assert.are.same(1, _meta_count(luarc))
    end)
end)
