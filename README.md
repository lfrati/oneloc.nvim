# 🌍 oneloc.nvim 

### Why oneloc.nvim?

## 📦 Installation

Requires `neovim >= 0.8`

Using [lazy](https://github.com/folke/lazy.nvim)
```lua
{ 'lfrati/oneloc.nvim', config = function()
    require("oneloc").setup {}
    for i=1,5 do
        vim.keymap.set({ "o", "n" }, "<Leader>"..i, ":lua require('oneloc').goto("..i..")<CR>")
        vim.keymap.set({ "o", "n" }, "<Leader><Leader>"..i, ":lua require('oneloc').update("..i..")<CR>")
    end
    vim.keymap.set({ "o", "n" }, "<Leader><Leader>o", ":lua require('oneloc').show()<CR>")

end }
```
