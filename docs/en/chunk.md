# how to configure chunk mod

## what can chunk do

it is used to highlight the code block where the cursor is located.

## Configurable items

chunk have four configurable items

1. enable
2. notify
4. exclude_filetypes
5. support_filetypes
6. chars
7. style
9. error_sign

`enable` is used to control whether the mod is started, the default is true.

If set to false, the usercmd and autocmd it carries will not be generated, and the mod will be closed at this time

`notify` is used to control whether to pop up a prompt in some cases (such as using the disableHLChunk command twice in a row), the default is true

If set to false, vim's match will be used to highlight the code block, otherwise treesitter will be used to determine the current code block

`exclude_filetypes` is a lua table type, example as follows, the default exclude_filetypes can be found in the [default config](../../lua/hlchunk/utils/filetype.lua)

```lua
exclude_filetypes = {
    aerial = true,
    dashboard = true,
}
```

`support_filetypes` is a lua table type, example as follows

```lua
support_filetypes = {
    "*.lua",
    "*.js",
}
```

`chars` is also a lua table, the characters in it are used to indicate how to render the chunk line, which contains five parts

- horizontal_line
- vertical_line
- left_top
- left_bottom
- right_arrow

`style` can be many types, as follow

1. string, like `style = "#806d9c"`
2. table, like `style = {"#806d9c", "#c21f30"}`
3. table, like

```lua
style = {
   { fg = "#806d9c", bg = "#c21f30" },
   { fg = "#806d9c", bg = "#c21f30" },
}
```

4. table with function like

```lua
local cb = function()
    if vim.g.colors_name == "tokyonight" then
        return "#806d9c"
    else
        return "#00ffff"
    end
end
style = {
    { fg = cb },
    { fg = "#f35336" },
},
```

`error_sign` is a boolean, the default is true, if you use treesitter to highlight the chunk, when this is a wrong chunk, it will set the chunk color to maple red (or what other you want), to enable this option, style should have two color, the default style is

```lua
style = {
    "#806d9c",
    "#c21f30",
},
```

## example

below is the default style of chunk line

<img width="500" alt="image" src="https://raw.githubusercontent.com/shellRaining/img/main/2302/23_hlchunk1.png">

its configuration is

```lua
chunk = {
    chars = {
        horizontal_line = "─",
        vertical_line = "│",
        left_top = "╭",
        left_bottom = "╰",
        right_arrow = ">",
    },
    style = "#806d9c",
},
```

<a id="chunk_example1">you can also set like this gif</a>

<img width="500" alt="image" src="https://raw.githubusercontent.com/shellRaining/img/main/2303/08_hlchunk8.gif">

```lua
chunk = {
    chars = {
        horizontal_line = "─",
        vertical_line = "│",
        left_top = "┌",
        left_bottom = "└",
        right_arrow = "─",
    },
    style = "#00ffff",
},
```
