local api = vim.api
local hl_chunk = require("hlchunk.hl_chunk")
local hl_indent = require("hlchunk.hl_indent")
local hl_line_num = require("hlchunk.hl_line_num")

local M = {}

local function enable_hl()
    hl_chunk.enable_hl_cur_chunk()
    hl_indent.enable_hl_indent()
    hl_line_num.enable_hl_line()
end
local function disable_hl()
    hl_chunk.disable_hl_cur_chunk()
    hl_indent.disable_hl_indent()
    hl_line_num.disable_hl_line()
end

api.nvim_create_user_command("EnableHL", enable_hl, {})
api.nvim_create_user_command("DisableHL", disable_hl, {})
api.nvim_create_user_command("DisableHLChunk", hl_chunk.disable_hl_cur_chunk, {})
api.nvim_create_user_command("EnableHLChunk", hl_chunk.enable_hl_cur_chunk, {})
api.nvim_create_user_command("DisableHLIndent", hl_indent.disable_hl_indent, {})
api.nvim_create_user_command("EnableHLIndent", hl_indent.enable_hl_indent, {})

return M
