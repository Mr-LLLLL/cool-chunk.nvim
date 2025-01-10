local ft = require("cool-chunk.utils.ts_node_type")
local api = vim.api
local fn = vim.fn
local treesitter = vim.treesitter

local function is_suit_type(node_type)
    local suit_types = ft[vim.bo.ft]
    if suit_types then
        return suit_types[node_type] and true or false
    end

    for _, rgx in ipairs(ft.default) do
        if node_type:find(rgx) then
            return true
        end
    end
    return false
end

-- this is utils module for cool-chunk every mod
-- every method in this module should pass arguments as follow
-- 1. mod: BaseMod, for utils function to get mod options
-- 2. normal arguments
-- 3. opts: for utils function to get options specific for this function
-- every method in this module should return as follow
-- 1. return ret code, a enum value
-- 2. return ret value, a table or other something
local M = {}

---@enum CHUNK_RANGE_RETCODE
M.CHUNK_RANGE_RET = {
    OK = 0,
    CHUNK_ERR = 1,
    NO_CHUNK = 2,
}

---@param mod BaseMod
---@return CHUNK_RANGE_RETCODE enum
---@return table<number, number>
---@diagnostic disable-next-line: unused-local
function M.get_chunk_range(mod)
    local ok, cursor_node = pcall(treesitter.get_node)
    if not ok then
        return M.CHUNK_RANGE_RET.NO_CHUNK, {}
    end

    while cursor_node do
        local node_type = cursor_node:type()
        local node_start, _, node_end, _ = cursor_node:range()
        if node_start ~= node_end and is_suit_type(node_type) then
            return cursor_node:has_error() and M.CHUNK_RANGE_RET.CHUNK_ERR or M.CHUNK_RANGE_RET.OK,
                {
                    node_start + 1,
                    node_end + 1,
                }
        end
        cursor_node = cursor_node:parent()
    end
    return M.CHUNK_RANGE_RET.NO_CHUNK, {}
end

local function get_valid_ctx_range(cur_node, cur_row, cur_indent)
    local wrap_res = function(res)
        res[3] = fn.indent(res[2]) + 1
        res[5] = #fn.getline(res[4])

        return res
    end
    local start_row, _, end_row, _ = cur_node:range()
    local get_indent = require("nvim-treesitter.indent").get_indent
    local start_indent = get_indent(start_row + 1)
    local end_indent = get_indent(end_row + 1)
    if start_row == end_row then
        return nil
    end

    local res = wrap_res({ start_indent, start_row + 1, 0, end_row + 1, 0 })
    if start_indent < end_indent and (cur_node:type() == "elseif_statement" or cur_node:type() == "else_statement") then
        res = wrap_res({ start_indent, start_row + 1, _, end_row + 2, _ })
    end
    -- don't use all file range
    if res[2] == 1 then
        return nil
    end
    if start_indent <= end_indent then
        if cur_indent > start_indent then
            return res
        elseif cur_node:type() == "block" then
            return false
        elseif (cur_row == start_row + 1 or cur_row == end_row + 1) or
            cur_node:type() == "if_statement" then
            return res
        end
    end

    return res
end

---@param mod BaseMod
---@return table<number, number> | nil
---@diagnostic disable-next-line: unused-local
function M.get_ctx_jump(mod)
    local ok, cur_node = pcall(treesitter.get_node)
    if not ok then
        return nil
    end
    local cur_row, cur_col = unpack(api.nvim_win_get_cursor(0))
    local get_indent = require("nvim-treesitter.indent").get_indent
    local cur_indent = get_indent(cur_row)
    while cur_node do
        local range = get_valid_ctx_range(cur_node, cur_row, cur_indent)
        if range then
            local _, start_row, start_col, end_row, end_col = unpack(range)
            if not (
                    (cur_row == start_row and cur_col + 1 == start_col) or
                    (cur_row == end_row and cur_col + 1 == end_col)
                ) then
                return { start_row, start_col - 1, end_row, end_col }
            end
        end

        cur_node = cur_node:parent()
    end

    return nil
end

---@param mod BaseMod
---@return table<number, number> | nil not include end point
---@diagnostic disable-next-line: unused-local
function M.get_ctx_range(mod)
    local ok, cur_node = pcall(treesitter.get_node)
    if not ok then
        return nil
    end
    local cur_row, _ = unpack(api.nvim_win_get_cursor(0))
    local get_indent = require("nvim-treesitter.indent").get_indent
    local cur_indent = get_indent(cur_row)
    while cur_node do
        local range = get_valid_ctx_range(cur_node, cur_row, cur_indent)
        if range then
            local indent, start_row, _, end_row, _ = unpack(range)
            return { indent, start_row + 1, end_row - 1 }
        end

        cur_node = cur_node:parent()
    end
end

---@param col number the column number
---@return boolean
function M.col_in_screen(col)
    local leftcol = vim.o.wrap and 0 or vim.fn.winsaveview().leftcol
    return col >= leftcol
end

M.filetype_pattern = {
    rust = "rs",
    python = "py",
}

function M.filetype2pattern(t)
    local patterns = {}
    for _, v in ipairs(t) do
        if M.filetype_pattern[v] then
            v = M.filetype_pattern[v]
        end
        table.insert(patterns, "*." .. v)
    end

    return patterns
end

return M
