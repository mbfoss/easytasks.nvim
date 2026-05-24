-- easytasks/toml/DecodeTree.lua

local Tree         = require("easytasks.util.Tree")
local vu           = require("easytasks.toml.validatorutils")

---@class easytasks.toml.DecodeNodeData
---@field key    string        path segment (unescaped)
---@field range  integer[]?    {r1,c1,r2,c2} source range, nil if not in document
---@field schema table?        resolved schema fragment for this path

---@class easytasks.toml.DecodeTree
---@field _tree    easytasks.util.Tree
---@field _root_id integer
---@field _id_seq  integer
local DecodeTree   = {}
DecodeTree.__index = DecodeTree

---@return easytasks.toml.DecodeTree
function DecodeTree.new()
    local self    = setmetatable({}, DecodeTree)
    self._tree    = Tree.new()
    self._id_seq  = 0
    self._id_seq  = self._id_seq + 1
    self._root_id = self._id_seq
    self._tree:add_item(nil, self._id_seq, { key = "", range = nil, schema = nil })
    return self
end

---@private
---@return integer
function DecodeTree:_next_id()
    self._id_seq = self._id_seq + 1
    return self._id_seq
end

---@return integer
function DecodeTree:root_id()
    return self._root_id
end

-- Find an immediate child of parent_id whose key matches; returns nil if absent.
---@param parent_id integer?
---@param key string
---@return integer?
function DecodeTree:get_child_id(parent_id, key)
    if not parent_id then return nil end
    for child_id, data in self._tree:iter_children(parent_id) do
        if data.key == key then return child_id end
    end
    return nil
end

-- Add a new child node under parent_id; returns its id.
---@param parent_id integer
---@param key string
---@param range integer[]?
---@return integer
function DecodeTree:add_child(parent_id, key, range)
    local id = self:_next_id()
    self._tree:add_item(parent_id, id, { key = key, range = range, schema = nil })
    return id
end

-- Update the range of an existing node.
---@param id integer
---@param range integer[]?
function DecodeTree:set_range_by_id(id, range)
    self._tree:get_data(id).range = range
end

---@param path string
---@return integer[]?
function DecodeTree:range_of(path)
    local id = self:_find_id(path)
    return id and self._tree:get_data(id).range or nil
end

---@param handler fun(id:any, data:any, depth:number):boolean?
function DecodeTree:walk_tree(handler)
    return self._tree:walk_tree(handler)
end

---@param row integer  0-indexed
---@param col integer  0-indexed
---@return string?  JSON Pointer of the deepest node whose range contains (row, col)
function DecodeTree:pos_to_path(row, col)
    local function pos_in_range(r)
        if not r then return false end
        return (row > r[1] or (row == r[1] and col >= r[2]))
            and (row < r[3] or (row == r[3] and col <= r[4]))
    end

    -- Children are in document (range-start) order, so binary search is valid.
    local function bsearch_match(items)
        local lo, hi = 1, #items
        local found
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            local range = items[mid].data and items[mid].data.range
            if range then
                if range[1] < row or (range[1] == row and range[2] <= col) then
                    found = mid
                    lo = mid + 1
                else
                    hi = mid - 1
                end
            else
                lo = mid + 1
            end
        end
        if not found then return nil end
        local item = items[found]
        if not pos_in_range(item.data and item.data.range) then return nil end
        return item
    end

    local function descend(items)
        if not items or #items == 0 then return nil end
        local item = bsearch_match(items)
        if not item then return nil end
        if self._tree:have_children(item.id) then
            local deeper = descend(self._tree:get_children(item.id))
            if deeper then return deeper end
        end
        return item.id
    end

    -- Root always has range=nil; search its children directly.
    local id = descend(self._tree:get_children(self._root_id))
    return id and self:path_of(id) or nil
end

-- Reconstruct the JSON Pointer path for a node by walking up to root.
---@param id integer
---@return string
function DecodeTree:path_of(id)
    return self:_path_of(id)
end

---@private
---@param id integer
---@return string
function DecodeTree:_path_of(id)
    local parts   = {}
    local current = id
    while current ~= self._root_id do
        local data = self._tree:get_data(current)
        table.insert(parts, 1, data.key)
        current = self._tree:get_parent_id(current)
    end
    if #parts == 0 then return "" end
    return vu.join_path_parts(parts)
end

-- Descend the tree by path segments; returns nil if any segment is missing.
-- Used only by range_of for path-based external callers.
---@private
---@param path string
---@return integer?
function DecodeTree:_find_id(path)
    if path == "" then return self._root_id end
    local current_id = self._root_id
    for _, part in ipairs(vu.split_path(path)) do
        local children = self._tree:get_children(current_id)
        if not children then return nil end
        local found
        for _, child in ipairs(children) do
            if child.data.key == part then
                found = child.id
                break
            end
        end
        if not found then return nil end
        current_id = found
    end
    return current_id
end

return DecodeTree
