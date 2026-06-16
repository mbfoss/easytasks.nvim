local M = {}

---@param path string
function M.file_exists(path)
    local stat = vim.loop.fs_stat(path)
    return stat and stat.type == "file"
end

---@param path string
---@return boolean
function M.dir_exists(path)
    local stat = vim.loop.fs_stat(path)
    return stat and stat.type == "directory" or false
end

---@param path string
---@return boolean
---@return string|nil
function M.make_dir(path)
    vim.fn.mkdir(path, "p")
    if not vim.fn.isdirectory(path) then
        local errmsg = vim.v.errmsg or ""
        return false, "Failed to create directory: " .. errmsg
    end
    return true
end

---@param path string
---@return boolean
---@return string? -- error msg
function M.create_file(path)
    local fd, err, err_name = vim.uv.fs_open(path, "wx", 420)
    if not fd then
        if err_name == "EEXIST" then
            return false, "File already exists"
        end
        return false, "Failed to create file: " .. tostring(err)
    end
    vim.uv.fs_close(fd)
    return true
end

---@param path string
---@param base string?
function M.get_relative_path(path, base)
    base = base or vim.fn.getcwd()

    local full_path = vim.fn.fnamemodify(path, ":p")
    base = vim.fn.fnamemodify(base, ":p")

    -- ensure trailing slash for proper prefix match
    if base:sub(-1) ~= "/" then
        base = base .. "/"
    end

    if full_path:find(base, 1, true) == 1 then
        return full_path:sub(#base + 1)
    end

    return nil -- not relative to base
end

---@param filepath string
---@param data string
---@return boolean
---@return string | nil
function M.write_content(filepath, data)
    local fd = io.open(filepath, "w")
    if not fd then
        return false, "Cannot open file for write '" .. filepath or "" .. "'"
    end
    local ok, ret_or_err = pcall(function() fd:write(data) end)
    fd:close()
    return ok, ret_or_err
end

---@param filepath  string
---@return boolean success
---@return string content or error
function M.read_content(filepath)
    local fd = io.open(filepath, "r")
    if not fd then
        return false, "Cannot open file for read '" .. (filepath or "") .. "'"
    end
    local read_ok, content_or_err = pcall(function() return fd:read("*a") end)
    fd:close()
    if not content_or_err then
        return false, "failed to read from file '" .. (filepath or "") .. "'"
    end
    return read_ok, content_or_err
end

---@param path string
---@param opts { max_size: number?, timeout: number? }?
---@param callback fun(err:string|nil, data:string|nil,cropped:boolean?)
---@return fun() abort
function M.async_load_text_file(path, opts, callback)
    opts = opts or {}

    local max_size = opts.max_size
    local timeout_ms = opts.timeout
    local uv = vim.uv or vim.loop

    local t = uv.new_timer()
    local fd = nil
    local chunks = {}
    local total_read = 0
    local offset = 0

    local finished = false
    local aborted = false

    ---@param err string|nil
    ---@param cropped boolean?
    local function finish(err, cropped)
        if finished then return end
        finished = true
        if t then
            if not t:is_closing() then
                t:stop()
                t:close()
            end
            t = nil
        end
        if fd then
            uv.fs_close(fd)
            fd = nil
        end
        if err then chunks = {} end
        vim.schedule(function()
            if not aborted then
                local final_data = table.concat(chunks)
                callback(err, final_data)
                chunks = {}
            end
        end)
    end
    local timeout_timer
    if timeout_ms then
        timeout_timer = vim.defer_fn(function()
            finish("Timeout", nil)
        end, timeout_ms)
    end
    uv.fs_open(path, "r", 438, function(open_err, opened_fd)
        if open_err or finished or aborted then
            if opened_fd then uv.fs_close(opened_fd) end
            if open_err and not (finished or aborted) then
                return finish("Could not open file: " .. open_err)
            end
            return
        end

        fd = opened_fd
        local function read_next()
            if not fd or finished or aborted then return end

            uv.fs_read(fd, 8192, offset, function(read_err, data)
                if finished or aborted then return end

                if read_err then
                    return finish("Read error: " .. read_err)
                end
                if not data or #data == 0 then
                    return finish()
                end
                if data:find("\0", 1, true) then
                    return finish("Binary file")
                end

                total_read = total_read + #data
                if max_size and total_read > max_size then
                    table.insert(chunks, data:sub(1, total_read - max_size))
                    return finish(nil, true)
                end

                table.insert(chunks, data)
                offset = offset + #data

                read_next()
            end)
        end

        read_next()
    end)
    return function()
        if finished or aborted then return end
        aborted = true
        if timeout_timer and not timeout_timer:is_closing() then
            timeout_timer:close()
        end
        finish("Aborted")
    end
end

return M
