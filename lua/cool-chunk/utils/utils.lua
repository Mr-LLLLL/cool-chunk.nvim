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

-- How the indentation is measured is important: a file can be indented with
-- spaces, tabs or both, and a tab is displayed as several cells ('tabstop').
-- nvim-treesitter's get_indent() returns an indent counted in shiftwidth, it
-- can't be compared with a screen column (like the virt_text_win_col of an
-- extmark) and it's wrong for tab indented files, so every indent below is
-- measured in screen columns with tabs expanded like they are displayed, and
-- byte columns are only used where a cursor position is needed.

---Get the leading blanks of a line, only spaces and tabs are indentation
---@param lnum number 1-based line number
---@return string
local function get_indent_str(lnum)
    local line = fn.getline(lnum)
    return line:match("^[ \t]*") or ""
end

---Get the indentation of a line in screen columns, tabs are expanded with
---'tabstop' exactly like they are displayed in the window
---@param lnum number 1-based line number
---@return number
function M.get_indent_cols(lnum)
    return fn.strdisplaywidth(get_indent_str(lnum))
end

---Get the indentation of a line in bytes, cursor columns are byte based
---@param lnum number 1-based line number
---@return number
local function get_indent_bytes(lnum)
    return #get_indent_str(lnum)
end

---Blank lines have no indentation of their own, use the previous non-blank
---line instead, so a cursor on a blank line still gets the right context
---@param lnum number 1-based line number
---@return number
local function get_indent_for_compare(lnum)
    if fn.getline(lnum):match("^%s*$") then
        lnum = fn.prevnonblank(lnum)
        if lnum == 0 then
            return 0
        end
    end
    return M.get_indent_cols(lnum)
end

---Expand the tabs of a line to spaces according to 'tabstop', so the string
---index is the screen column. Note this is only exact when no double width
---character is before the column, which is enough to check the indent area.
---@param line string
---@return string
function M.expand_tabs(line)
    local tabstop = vim.bo.tabstop
    if tabstop < 1 or not line:find("\t", 1, true) then
        return line
    end

    local parts = {}
    local col = 0
    local pos = 1
    while pos <= #line do
        local tab = line:find("\t", pos, true)
        local text = tab and line:sub(pos, tab - 1) or line:sub(pos)
        parts[#parts + 1] = text
        col = col + fn.strdisplaywidth(text)
        if not tab then
            break
        end
        local spaces = tabstop - (col % tabstop)
        parts[#parts + 1] = (" "):rep(spaces)
        col = col + spaces
        pos = tab + 1
    end

    return table.concat(parts)
end

---Whether the screen cell at {col} of the line is blank, so a virtual text can
---be drawn there without covering any char
---@param line string
---@param col number 0-based screen column
---@return boolean
function M.is_blank_at(line, col)
    if fn.strdisplaywidth(line) <= col then
        return true
    end
    return M.expand_tabs(line):sub(col + 1, col + 1):match("%s") ~= nil
end

---@param cur_node TSNode
---@param cur_row number 1-based line number of the cursor
---@param cur_indent number screen columns of the cursor line indentation
---@return table|boolean|nil range res, false when the node should be skipped
---@return number|nil ctx_end_row the last row the context line should cover
local function get_valid_ctx_range(cur_node, cur_row, cur_indent)
    local wrap_res = function(res)
        -- cursor columns are byte based, while the indent columns are not
        res[3] = get_indent_bytes(res[2]) + 1
        res[5] = #fn.getline(res[4])

        return res
    end
    local start_row, _, end_row, _ = cur_node:range()
    -- tree-sitter rows are 0-based, convert them to 1-based line numbers
    local start_line, end_line = start_row + 1, end_row + 1
    local start_indent = get_indent_for_compare(start_line)
    local end_indent = get_indent_for_compare(end_line)
    if start_row == end_row then
        return nil
    end

    -- The end line of a node is the line of its closing token (`end`, `}`, ...)
    -- in most languages, it has the same indentation as the start line and the
    -- context line should stop before it. Languages without a closing token
    -- (python, yaml, ...) end on a content line which is deeper indented, that
    -- line is still a part of the context and must be kept.
    local ctx_end_line = end_line
    if end_indent <= start_indent then
        ctx_end_line = end_line - 1
    end

    local res = wrap_res({ start_indent, start_line, 0, end_line, 0 })
    -- don't use all file range
    if res[2] == 1 then
        return nil
    end
    if start_indent <= end_indent then
        if cur_indent > start_indent then
            return res, ctx_end_line
        elseif cur_node:type() == "block" then
            return false
        elseif (cur_row == start_line or cur_row == end_line) or
            cur_node:type() == "if_statement" then
            return res, ctx_end_line
        end
    end

    return res, ctx_end_line
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
    local cur_indent = get_indent_for_compare(cur_row)
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
---@return table<number, number> | nil { indent columns, first row, last row }, the first row of the node is not included
---@diagnostic disable-next-line: unused-local
function M.get_ctx_range(mod)
    local ok, cur_node = pcall(treesitter.get_node)
    if not ok then
        return nil
    end
    local cur_row, _ = unpack(api.nvim_win_get_cursor(0))
    local cur_indent = get_indent_for_compare(cur_row)
    while cur_node do
        local range, ctx_end_row = get_valid_ctx_range(cur_node, cur_row, cur_indent)
        if range then
            local indent, start_row = unpack(range)
            -- the start line opens the node, the context line starts after it
            return { indent, start_row + 1, ctx_end_row }
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
