local M = {}

function M.get_pair_rows()
    local beg_row, end_row
    local base_flag = "nWz"
    local cur_row_val = vim.fn.getline(".")
    local cur_col = vim.fn.col(".")
    local cur_char = string.sub(cur_row_val, cur_col, cur_col)

    beg_row = vim.fn.searchpair("{", "", "}", base_flag .. "b" .. (cur_char == "{" and "c" or ""))
    end_row = vim.fn.searchpair("{", "", "}", base_flag .. (cur_char == "}" and "c" or ""))

    return { beg_row, end_row }
end

function M.get_rows_blank()
    local rows_blank = {}
    local beg_row = vim.fn.line("w0")
    local end_row = vim.fn.line("w$")
    for i = beg_row, end_row do
        local row_str = vim.fn.getline(i)
        if #row_str == 0 then
            rows_blank[i] = -1
            goto continue
        end
        ---@diagnostic disable-next-line: undefined-field
        rows_blank[i] = #(row_str:match("^%s+") or "")
        ::continue::
    end
    return rows_blank
end

return M
