local Array = require("cool-chunk.utils.array")
local api = vim.api
local utils = require("cool-chunk.utils.utils")

---@class BaseModOpts
---@field hl_group table<string, string>
---@field exclude_filetypes table<string, boolean>
---@field support_filetypes table<string>
---@field animate_duration number a animate duration
---@field fire_event table<string> a event for trigger
---@field notify boolean

---@class timer

---@class RuntimeVar
---@field old_ctx_range table<number>
---@field old_chunk_range table<number>
---@field is_loaded boolean
---@field is_enabled boolean
---@field animate_timer timer
---@field is_error boolean

---@class BaseMod
---@field name string the name of mod, use Snake_case naming style, such as line_num
---@field ns_id number namespace id
---@field bufnr number buffer number
---@field options BaseModOpts default config for mod, and user can change it when setup
---@field augroup_name string with format hl_{mod_name}_augroup, such as hl_chunk_augroup
local BaseMod = {
    name = "CoolChunk",
    options = {
        exclude_filetypes = {},
        support_filetypes = {},
        notify = false,
        hl_group = {},
        animate_duration = 0,
        fire_event = {},
    },
    ns_id = -1,
    bufnr = 0,
    old_ctx_range = {},
    old_chunk_range = {},
    text_changed = false,
    is_error = false,
    is_loaded = false,
    is_enabled = false,
    augroup_name = "",
    animate_timer = vim.loop.new_timer(),
}

---@return BaseMod
-- create a BaseMod instance, can implemented new feature by using the instance easily
function BaseMod:new(o)
    o = o or {}
    o.augroup_name = o.augroup_name or ("hl_" .. o.name .. "_augroup")
    self.__index = self
    setmetatable(o, self)
    return o
end

-- just enable a mod instance, called when the mod was disable or not init
function BaseMod:enable()
    if self.is_enabled then
        return false
    end
    self.is_enabled = true

    if not self.is_loaded then
        self:set_hl()
        self:create_mod_usercmd()
        self.is_loaded = true
    end
    self:enable_mod_autocmd()
    self:render()

    return true
end

function BaseMod:enable_mod_autocmd()
    api.nvim_create_augroup(self.augroup_name, { clear = true })

    api.nvim_create_autocmd(self.options.fire_event, {
        group = self.augroup_name,
        pattern = utils.filetype2pattern(self.options.support_filetypes),
        callback = function()
            self:render()
        end,
    })
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        group = self.augroup_name,
        pattern = utils.filetype2pattern(self.options.support_filetypes),
        callback = function()
            self.text_changed = true
        end,
    })
end

function BaseMod:set_hl()
end

function BaseMod:disable()
    if not self.is_enabled then
        return false
    end

    self.is_enabled = false
    self:disable_mod_autocmd()
    self:clear()

    return true
end

function BaseMod:render()
    self:notify("not implemented render " .. self.name, vim.log.levels.ERROR)
end

---@param opts?  table
---@param len?   number
function BaseMod:draw_by_animate(opts, len)
    opts = opts or {}

    local index = 1
    local interval = math.floor(self.options.animate_duration / len)
    local prev_opt = nil
    local prev_line = 0
    local shiftwidth = vim.fn.shiftwidth()
    local get_indent = vim.fn.indent
    local indent = 0
    if #opts.line_num > 1 then
        indent = get_indent(opts.line_num[1]) - shiftwidth
    end
    self.animate_timer = vim.loop.new_timer()
    self.animate_timer:start(0, interval, vim.schedule_wrap(function()
        if index >= len then
            return
        end

        local row_opts = {
            virt_text_pos = "overlay",
            hl_mode = "combine",
            priority = 100,
        }

        row_opts.virt_text = { { opts.virt_text[index][1], opts.hl_group } }
        row_opts.virt_text_win_col = opts.offset[index]
        local id
        local space_tab = (" "):rep(shiftwidth)
        local line_val = vim.fn.getline(opts.line_num[index]):gsub("\t", space_tab)
        if #vim.fn.getline(opts.line_num[index]) <= indent or
            line_val:sub(indent + 1, indent + 1):match("%s") then
            if utils.col_in_screen(indent) then
                id = api.nvim_buf_set_extmark(opts.bufnr, self.ns_id, opts.line_num[index] - 1, 0, row_opts)
            end
        end

        if prev_opt then
            api.nvim_buf_set_extmark(opts.bufnr, self.ns_id, prev_line, 0, prev_opt)
        end
        prev_line = opts.line_num[index] - 1
        if id then
            prev_opt = row_opts
            prev_opt.id = id
            prev_opt.virt_text = { { opts.virt_text[index][2], opts.hl_group } }
        else
            prev_opt = nil
        end

        index = index + 1
        if index == len then
            if not self.animate_timer:is_closing() then
                self.animate_timer:close()
            end
        end
    end))
end

function BaseMod:refresh(opts)
    self.ns_id = api.nvim_create_namespace(self.name)
    self.bufnr = api.nvim_get_current_buf()
    self.old_ctx_range = opts.ctx_range or {}
    self.old_chunk_range = opts.chunk_range or {}
    self.is_error = opts.is_error or false
end

function BaseMod:clear(line_start, line_end)
    line_start = line_start or 0
    line_end = line_end or -1

    if not self.animate_timer:is_closing() then
        self.animate_timer:close()
    end

    self.old_ctx_range = {}
    self.old_chunk_range = {}
    self.bufnr = 0
    self.is_error = nil
    self.text_changed = false

    if self.ns_id ~= -1 then
        api.nvim_buf_clear_namespace(self.bufnr, self.ns_id, line_start, line_end)
    end
    self.ns_id = -1
end

function BaseMod:disable_mod_autocmd()
    api.nvim_del_augroup_by_name(self.augroup_name)
end

function BaseMod:create_mod_usercmd()
    local token_array = Array:from(self.name:split("_"))
    local mod_name = token_array
        :map(function(value)
            return value:firstToUpper()
        end)
        :join()
    api.nvim_create_user_command("EnableCC" .. mod_name, function()
        self:enable()
    end, {})
    api.nvim_create_user_command("DisableCC" .. mod_name, function()
        self:disable()
    end, {})
end

-- set options for mod, if the mod dont have default config, it will notify you
---@param options BaseModOpts
function BaseMod:set_options(options)
    if self.options == nil then
        self:notify("not set the default config for " .. self.name, vim.log.levels.ERROR)
        return
    end
    self.options = vim.tbl_deep_extend("force", self.options, options or {})
end

---@param msg string
---@param level number?
---@param opts {once: boolean}?
function BaseMod:notify(msg, level, opts)
    level = level or vim.log.levels.INFO
    opts = opts or { once = false }
    -- notice that if self.options.notify is nil, it will still notify you
    if self.options == nil or self.options.notify == false then
        return
    end

    if opts.once then
        vim.notify_once(msg, level, opts)
    else
        vim.notify(msg, level, opts)
    end
end

return BaseMod
