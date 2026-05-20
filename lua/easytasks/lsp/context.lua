---@meta

---@class easytasks.LspBufferContext
---@field ast easytasks.util.Tree
---@field schema table|nil The JSON schema assigned to this buffer
---@field parse_results table|nil Last known output from parser.parse(bufnr) (data, pointer_map, errors)
---@field last_updated integer|nil Timestamp or btick when the cache was updated
---@field config table|nil Optional buffer-local custom configuration overrides

