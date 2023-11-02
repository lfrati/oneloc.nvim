# 🌍 oneloc.nvim 

### Why oneloc.nvim?
Some time ago I stumbled upon [harpoon](https://www.youtube.com/watch?v=Qnos8aApa9g).
The idea is that you keep a persistent mapping between a small number of keys <-> locations.
From my search plugin [onesearch](https://github.com/lfrati/onesearch.nvim) I've realized I really like simple [minor-modes](https://www.gnu.org/software/emacs/manual/html_node/emacs/Minor-Modes.html).
Here is my take on a navigation plugin with a simple floating window and persistent locations. Hope you'll like it 🙂 

## 📦 Installation

Requires `neovim >= 0.9`

Using [lazy](https://github.com/folke/lazy.nvim)
```lua
{ 'lfrati/oneloc.nvim', config = function()
    -- values shown in setup are the defaults,
    -- feel free to call just require("oneloc").setup {} if you like them
    require("oneloc").setup {
        flash_t = 200,
        flash_color = "OnelocFlash",
        file_color = "ErrorMsg",
        short_path = false,
        granularity = "pos", -- or "file"
    }
    for i=1,5 do
        vim.keymap.set({ "n" }, "<Leader>"..i, ":lua require('oneloc').goto("..i..")<CR>")
    end
    vim.keymap.set({ "n" }, "<Leader><Leader>o", ":lua require('oneloc').show()<CR>")

end }
```

## ⚙️  How it works

Super simple, there are only 2 functions you care aboout `show()` and `goto(n)` (see example mappings above)

`show()` creates a simple floating window that shows you the current locations:

<img width="625" alt="image" src="https://github.com/lfrati/oneloc.nvim/assets/3115640/38eb3f5f-9999-48a7-b1d5-58db6d636d9d">

From there you have a few options:
- `ESC` close the floating window.
- `[1-5]` insert the current path in position `[1-5]`. If there was something there already, swap them.
- `d[1-5]` delete location in position `[1-5]`.
- `D` prompt the user `y/N` to delete ALL the locations.

That's it. The only other piece is `goto(n)`, can you guess what it does?
Yep. It opens the corresponding entry. (so `goto(2)` sends you to the second location in the floating windows, if it exists of course).

Note that when you add a new location, the line/column information is stored too. This way you can easily use it to move within large files, if you want.

## 🛠️ Configuration
Upon landing somewhere a flash helps find where the cursor is.
- Don't like it? Set `flash_t = 0` in setup.
- Don't like the color? Set `flash_color = <HIGHLIGHT>` in setup, where `<HIGHLIGHT>` is the name of an existing highlight group (up to you to make sure it exists!).

Locations in the floating window, show the full path.
- Lines are too long? Set `short_path = true` to show only the first letters of folders

|`short_path = false`| `short_path = true`|
|---|---|
| <img width="450" alt="image" src="https://github.com/lfrati/oneloc.nvim/assets/3115640/be299f02-3004-4a9d-88c9-7ea9f7ff8ccf"> | <img width="265" alt="image" src="https://github.com/lfrati/oneloc.nvim/assets/3115640/b611e476-4b32-4a17-8de9-82c0deac4d08"> |

Filenames in the floating window are highlighted to more easily see them at a glance
- Don't like the color? Set `file_color = <HIGHLIGHT>` in setup using your favorite hightlight group.
  
Locations include line/column information, this lets you use this plugin as a replacement for marks too.
- Don't like it and would rather just use it to jump between files? Set `granularity = "file"` in setup. This way you'll go back to files as if you used `:edit file`. If you want to restore the last location when re-opening a file check `:h restore-cursor` or [this issue](https://github.com/neovim/neovim/issues/16339#issuecomment-1457394370)
