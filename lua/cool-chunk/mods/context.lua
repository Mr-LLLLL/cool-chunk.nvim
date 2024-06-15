local BaseMod = require("cool-chunk.base_mod")
local utils = require("cool-chunk.utils.utils")
local ft = require("cool-chunk.utils.filetype")
local Array = require("cool-chunk.utils.array")
local api = vim.api
local fn = vim.fn

---@class ContextOpts: BaseModOpts
---@field chars table<string, string>
---@field textobject string
---@field support_filetypes string
---@field jump_support_filetypes string
---@field jump_start string
---@field jump_end string

---@class ContextMod: BaseMod
---@field options ContextOpts
---@field textobject_buffers table<number>
---@field jump_buffers table<number>
local context_mod = BaseMod:new({
    name = "context",
    options = {
        notify = true,
        chars = {
            "│",
        },
        hl_group = {
            context = "LineNr",
        },
        exclude_filetypes = ft.exclude_filetypes,
        support_filetypes = ft.support_filetypes,
        textobject = "ih",
        jump_support_filetypes = { "lua" },
        jump_start = "[{",
        jump_end = "]}",
        fire_event = { "CursorHold", "CursorHoldI" },
    },
    textobject_buffers = {},
    jump_buffers = {},
})

function context_mod:render()
    if (not self.is_enabled) or self.options.exclude_filetypes[vim.bo.filetype] then
        return
    end

    local ctx_range = utils.get_ctx_range(self)
    if not ctx_range then
        self:clear()
        return
    end

    local ctx_col, beg_row, end_row = unpack(ctx_range)

    if #self.old_ctx_range > 2 and
        ctx_range[1] == self.old_ctx_range[1] and
        ctx_range[2] == self.old_ctx_range[2] and
        ctx_range[3] == self.old_ctx_range[3] and
        not self.text_changed then
        return
    end

    self:clear()
    self:refresh({ ctx_range = ctx_range })


    local shiftwidth = fn.shiftwidth()
    local row_opts = {
        virt_text_pos = "overlay",
        virt_text_win_col = ctx_col,
        hl_mode = "combine",
        priority = 99,
    }

    -- render middle section
    local offset = vim.o.wrap and 0 or fn.winsaveview().leftcol
    for i = beg_row, end_row do
        row_opts.virt_text = { { self.options.chars[1], self.options.hl_group.context } }
        row_opts.virt_text_win_col = ctx_col - offset
        local space_tab = (" "):rep(shiftwidth)
        local line_val = fn.getline(i):gsub("\t", space_tab)
        local indent = vim.fn.indent(i)
        if indent ~= 0 and indent <= row_opts.virt_text_win_col then
            goto continue
        end
        if #fn.getline(i) <= ctx_col or line_val:sub(ctx_col + 1, ctx_col + 1):match("%s") then
            if utils.col_in_screen(ctx_col) then
                api.nvim_buf_set_extmark(self.bufnr, self.ns_id, i - 1, 0, row_opts)
            end
        end

        ::continue::
    end
end

function context_mod:disable_mod_autocmd()
    BaseMod.disable_mod_autocmd(self)

    local textobject = self.options.textobject
    if #textobject ~= 0 then
        for bufnr in pairs(self.textobject_buffers) do
            vim.keymap.del({ "x", "o" }, textobject, { buffer = bufnr })
        end
    end

    local jump_start = self.options.jump_start
    if #jump_start ~= 0 then
        for bufnr in pairs(self.jump_buffers) do
            vim.keymap.del({ "n", "x" }, jump_start, { buffer = bufnr })
        end
    end

    local jump_end = self.options.jump_end
    if #jump_end ~= 0 then
        for bufnr in pairs(self.jump_buffers) do
            vim.keymap.del({ "n", "x" }, jump_end, { buffer = bufnr })
        end
    end
    self.textobject_buffers = {}
    self.jump_buffers = {}
end

function context_mod:enable_mod_autocmd()
    BaseMod.enable_mod_autocmd(self)

    api.nvim_create_autocmd(
        { "Filetype" },
        {
            group = self.augroup_name,
            pattern = self.options.support_filetypes,
            callback = function()
                local textobject = self.options.textobject
                if #textobject == 0 then
                    return
                end

                local bufnr = api.nvim_get_current_buf()
                if self.textobject_buffers[bufnr] then
                    return
                end
                self.textobject_buffers[bufnr] = true

                local token_array = Array:from(self.name:split("_"))
                local mod_name = token_array
                    :map(function(value)
                        return value:firstToUpper()
                    end)
                    :join()

                vim.keymap.set({ "x", "o" }, textobject, function()
                    if self.options.exclude_filetypes[vim.bo.ft] then
                        return
                    end

                    local cur_ctx_range = utils.get_ctx_range(self)
                    if not cur_ctx_range then
                        return
                    end

                    local _, s_row, e_row = unpack(cur_ctx_range)
                    local ctrl_v = api.nvim_replace_termcodes("<C-v>", true, true, true)
                    local cur_mode = vim.fn.mode()
                    if cur_mode == "v" or cur_mode == "V" or cur_mode == ctrl_v then
                        vim.cmd("normal! " .. cur_mode)
                    end

                    api.nvim_win_set_cursor(0, { s_row, 0 })
                    vim.cmd("normal! V")
                    api.nvim_win_set_cursor(0, { e_row, 0 })
                end, { noremap = true, desc = BaseMod.name .. mod_name, buffer = bufnr })
            end,
        }
    )
    api.nvim_create_autocmd(
        { "Filetype" },
        {
            group = self.augroup_name,
            pattern = self.options.jump_support_filetypes,
            callback = function()
                local bufnr = api.nvim_get_current_buf()
                if self.jump_buffers[bufnr] then
                    return
                end

                local token_array = Array:from(self.name:split("_"))
                local mod_name = token_array
                    :map(function(value)
                        return value:firstToUpper()
                    end)
                    :join()

                local jump_start = self.options.jump_start
                local jump_end = self.options.jump_end

                if #jump_start ~= 0 then
                    vim.keymap.set({ "n", "x" }, jump_start, function()
                        if self.options.exclude_filetypes[vim.bo.ft] then
                            return
                        end

                        local jump_range = utils.get_ctx_jump(self)
                        if not jump_range then
                            return
                        end

                        api.nvim_win_set_cursor(0, { jump_range[1], jump_range[2] })
                    end, { noremap = true, desc = BaseMod.name .. mod_name .. "JumpStart", buffer = bufnr })
                    self.jump_buffers[bufnr] = true
                end

                if #jump_end ~= 0 then
                    vim.keymap.set({ "n", "x" }, jump_end, function()
                        if self.options.exclude_filetypes[vim.bo.ft] then
                            return
                        end

                        local jump_range = utils.get_ctx_jump(self)
                        if not jump_range then
                            return
                        end

                        api.nvim_win_set_cursor(0, { jump_range[3], jump_range[4] })
                    end, { noremap = true, desc = BaseMod.name .. mod_name .. "JumpEnd", buffer = bufnr })
                    self.jump_buffers[bufnr] = true
                end
            end,
        }
    )
end

function context_mod:set_hl()
    if string.sub(self.options.hl_group.context, 1, 1) == "#" then
        local fg = self.options.hl_group.context

        local token_array = Array:from(self.name:split("_"))
        local mod_name = token_array
            :map(function(value)
                return value:firstToUpper()
            end)
            :join()
        self.options.hl_group.context = BaseMod.name .. mod_name .. "context"
        api.nvim_set_hl(0, self.options.hl_group.context, { fg = fg })
    end
end

return context_mod
