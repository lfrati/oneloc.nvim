# 🌍 oneloc.nvim 

A simple plugin to keep track of a few important locations you want to jump to and from often.
Provides 3 things:
- a function to record the current location `nmap("<Leader><Leader>1", ":lua require('oneloc').record_cursor(1)<CR>")`
- a function to jump to a recorded location `namp("<Leader>1", ":lua require('oneloc').goto(1)<CR>")`
- a simple ui to check what you have recorded:

<p align="center">
<img width="581" alt="image" src="https://github.com/lfrati/oneloc.nvim/assets/3115640/8a7c677a-66ba-4927-9b8b-dc70eca2093a">
</p>

- Red color = filename to get it at a glance 👀
- Green color = that's what your are going to find if you jump there 👍
- Gray color = that's what was there when you recorded the location 🤷‍♂️

From there you have a few options:
- `ESC` close the floating window.
- `[1-5]` jump to the corresponding location.
- `D` delete ALL the locations.
- `d[1-5]` delete location in position `[1-5]`.
- `u` undo last insert/delete action
- `TAB` toggle granularity between `pos` (jump back to line/column where the location was saved) and `file` just open the file (may jump to last position, depending on your setup, see configuration)

Note: when you add a new location, the line/column information is stored too. This way you can easily use it to move within large files, if you want.

## 📦 Installation

Requires `neovim >= 0.9`

Using [lazy](https://github.com/folke/lazy.nvim)
```lua
{ 'lfrati/oneloc.nvim', config = function()
    -- values shown in setup are the defaults,
    -- feel free to call just require("oneloc").setup {} if you like them
    require("oneloc").setup {
      flash_t = 200,                --  ms
      colors = {
        flash = "OnelocFlash",      --  highlight cursor line
        file = "OnelocRed",         --  highlight filenames
        outdated = "OnelocGray",    --  highlight outdated line info
        uptodate = "OnelocGreen",   --  highlight uptodate line info
      },
      scope = "pos",                -- pos : include cursor position information
      width = 70                    -- width of ui window
    }
    for i=1,5 do
        -- <Leader>[1-5] to go somewhere
        vim.keymap.set({ "n" }, "<Leader>"..i, ":lua require('oneloc').goto("..i..")<CR>")
        -- <Leader><Leader>[1-5] to record someplace
        vim.keymap.set({ "n" }, "<Leader><Leader>"..i, ":lua require('oneloc').record_cursor("..i..")<CR>")
    end
    vim.keymap.set({ "n" }, "<Leader><Leader>o", ":lua require('oneloc').show()<CR>")

end }
```

## 🛠️ Configuration
Upon landing somewhere a flash helps find where the cursor is.
- Don't like it? Set `flash_t = 0` in setup.
- Don't like the colors? Set `ccolors.xyz = <HIGHLIGHT>` in setup, where `<HIGHLIGHT>` is the name of an existing highlight group (up to you to make sure it exists!).
- Not enough space on screen? No worries, the location information shrinks as width shrinks
  
| normal | shorter| shortest |
|---|---|---|
| <img width="583" alt="image" src="https://github.com/lfrati/oneloc.nvim/assets/3115640/65b77920-27ae-40ab-9190-98e053ada35d"> | <img width="439" alt="image" src="https://github.com/lfrati/oneloc.nvim/assets/3115640/a33c76dd-def5-457b-b1cd-eaaad815c64e"> | <img width="193" alt="image" src="https://github.com/lfrati/oneloc.nvim/assets/3115640/203ad893-b633-49f4-b496-13f6b2a9430c"> |
  
Locations include line/column information, this lets you use this plugin as a replacement for marks too.
- Don't like it and would rather just use it to jump between files? Set the default with `granularity = "file"` in setup. This way you'll go back to files as if you used `:edit file`. If you want to restore the last location when re-opening a file check `:h restore-cursor` or [this issue](https://github.com/neovim/neovim/issues/16339#issuecomment-1457394370)

## Why oneloc.nvim?
Some time ago I stumbled upon [harpoon](https://www.youtube.com/watch?v=Qnos8aApa9g).
The idea is that you keep a persistent mapping between a small number of keys <-> locations.
From my search plugin [onesearch](https://github.com/lfrati/onesearch.nvim) I've realized I really like simple [minor-modes](https://www.gnu.org/software/emacs/manual/html_node/emacs/Minor-Modes.html).
Here is my take on a navigation plugin with a simple floating window and persistent locations. Hope you'll like it 🙂 
