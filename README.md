# 🌍 oneloc.nvim 

### Why oneloc.nvim?
Some time ago I stumbled upon [harpoon](https://www.youtube.com/watch?v=Qnos8aApa9g).
The idea is that you keep a persistent mapping between a small number of keys <-> locations.
But it was a bit too complex for my tastes. So I made my only simplified version. Hope you'll like it.

## 📦 Installation

Requires `neovim >= 0.8`

Using [lazy](https://github.com/folke/lazy.nvim)
```lua
{ 'lfrati/oneloc.nvim', config = function()
    require("oneloc").setup {}
    for i=1,5 do
        vim.keymap.set({ "o", "n" }, "<Leader>"..i, ":lua require('oneloc').goto("..i..")<CR>")
    end
    vim.keymap.set({ "o", "n" }, "<Leader><Leader>o", ":lua require('oneloc').show()<CR>")

end }
```

## ⚙️  How it works

Super simple, there are only 2 functions you care aboout `show()` and `goto(n)` (see example mapping above)

`show()` creates a simple floating window that shows you the current locations

From there you have a few options:
- `ESC`
- `[1-5]`
- `d`
- `D`

That's it. The only other piece is `goto(n)`, can you guess what it does?
Yep. It opens the corresponding entry. (so `goto(2)` sends you to the second location in the floating windows, if it exists of course).

## 🛠️ Configuration

WIP

```
    flash_t = 200,
    flash_color = "OnelocFlash",
    file_color = "ErrorMsg",
    short_path = true,
```
