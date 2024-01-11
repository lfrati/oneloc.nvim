local M = {}
local api = vim.api
local uv = vim.loop
local version = '1.1.0'



local LIFOStack = {}
function LIFOStack:new()
    local obj = {data = {}}
    setmetatable(obj, {__index = self})
    return obj
end
function LIFOStack:push(value)
    table.insert(self.data, value)
end
function LIFOStack:pop()
    if #self.data == 0 then
        return vim.NIL
    end
    return table.remove(self.data)
end

-- https://stevedonovan.github.io/ldoc/manual/doc.md.html

local flash_ns = vim.api.nvim_create_namespace("OnelocFlash")
local win = nil

-- from :help uv.new_timer()
local function set_timeout(timeout, callback)
    local timer = uv.new_timer()
    if timer then
        timer:start(timeout, 0, function()
            timer:stop()
            timer:close()
            callback()
        end)
    end
    return timer
end

-- is this seriously not a default string method?
local function lpad(str, len, char)
    return str .. string.rep(char or " ", len - #str)
end

local function mask_line(lnum)
    local winwidth = vim.fn.winwidth(0)
    local line = vim.fn.getline(lnum)
    local mask = lpad(line, winwidth, " ")
    return mask
end

local function getkey()
    local key = vim.fn.getchar()
    if type(key) == 'number' then
        return vim.fn.nr2char(key)
    end
    return key
end

--------------------------------------------------------------------------------
-- LOCAL STUFF
--------------------------------------------------------------------------------

local function flash_line()
    -- Make the current line flash to help me find it more easily.
    local lnum, _ = unpack(vim.api.nvim_win_get_cursor(0))
    local mask = mask_line(lnum)
    local flash_id = api.nvim_buf_set_extmark(0, flash_ns, lnum - 1, 0, {
        virt_text = { { mask, M.conf.flash_color } },
        virt_text_pos = "overlay"
    })
    local bufnr = vim.fn.winbufnr(0)
    set_timeout(
        M.conf.flash_t,
        vim.schedule_wrap(function()
            api.nvim_buf_del_extmark(bufnr, flash_ns, flash_id)
            vim.cmd("redraw")
        end))
end

local function save(tbl)
    local json = vim.json.encode(tbl)
    local ok, result = pcall(vim.fn.writefile, { json }, M.json_path)
    if ok == false then
        print(result)
    end
end

local function load()
    local ok, result = pcall(vim.fn.readfile, M.json_path)
    if ok then
        return vim.json.decode(result[1])
    else
        error("ERROR: could not load " .. M.json_path)
    end
end

local function prompt(msg, style)
    vim.cmd.redraw()
    api.nvim_echo({ { msg, style } }, false, {})
end

local function read_nth_line(path, n)
    local line_count = 0

    for line in io.lines(path) do
        line_count = line_count + 1
        if line_count == n then
            return line
        end
    end
    return nil  -- Return nil if the file has fewer than n lines
end

local function read_line_at_bytes(path, nbytes)
    local file = io.open(path, "rb")
    if file then
      file:seek("set", nbytes - 1)
      local line = file:read()
      file:close()
      return line
    end
end

local function fit_path_to_window(path, head, tail)
    -- This is a bit of a pain because of the extra stuff around the path
    -- e.g.   normal "1) /Users/user/folder/file.lua:110"
    --       shorter "1) /U/u/f/file.lua:110"
    --      shortest "1) ile.lua:110"

    local entry = head .. path .. tail
    if #entry <= M.conf.width then
        return entry
    end

    local short_path = vim.fn.pathshorten(path)
    local short_entry = head .. short_path .. tail
    if #short_entry <= M.conf.width then
        return short_entry
    end

    local shortest_path = short_path .. tail
    shortest_path = string.sub(shortest_path, #short_entry - M.conf.width + #head, #shortest_path)
    return head .. shortest_path
end

local function fit_line_to_window(line)
    if #line >= M.conf.width then
        return string.sub(line, 1, M.conf.width)
    end
    return line
end

local function render(items)
    local lines = {}
    local files = {} -- used to highlight filenames

    table.insert(lines, "")
    for i=1,5 do
        local item = items[i]
        local content
        local entry
        if item ~= vim.NIL then
            table.insert(files, item.filename)
            local path = item.path
            if M.conf.scope == "pos" then
                local head = " " .. i .. " "
                local tail = ":"..item.lnum..":"..item.cnum.." "
                entry = fit_path_to_window(path, head, tail)
                content = fit_line_to_window("    " .. item.content)
            else
                entry = fit_line_to_window(" "..i.." "..path.." ")
                content = ""
            end
        else
            entry = fit_line_to_window(" "..i.."                        ")
            content = ""
        end

        table.insert(lines, entry)
        -- content lines are colored after window is created
        table.insert(lines, content)
        table.insert(lines, "")
    end

    return lines, files
end

local function check_if_same(item)

    -- fast path
    local current = read_line_at_bytes(item.path, item.bytes_offset)
    current = string.gsub(current, "^%s*(.-)%s*$", "%1")
    if current == item.content then
        return true
    end

    -- slow path
    current = read_nth_line(item.path, item.lnum)
    if current then
        current = string.gsub(current, "^%s*(.-)%s*$", "%1")
        if current == item.content then
            return true
        end
    end

    return false
end

local function colorize(items)

    -- https://stackoverflow.com/a/23247938
    vim.cmd[[
        hi Bang ctermfg=yellow guifg=yellow
        match Bang /\%>1v.*\%<3v/
    ]]

    -- color line based on "does it still match the stored value?"
    for i=1,5 do
        local item = items[i]
        if item ~= vim.NIL then
            if check_if_same(item) then
                -- 1 line of padding
                -- each item spans 3 lines 
                -- line content is the second line of the 3
                vim.fn.matchaddpos( M.conf.uptodate_color, {1 + (i-1)*3 + 2})
            else
                vim.fn.matchaddpos(M.conf.outdated_color, {1 + (i-1)*3 + 2})
            end
        end
    end
end

local function open_ui()
    -- if win exists already (~nil) delete it
    -- then create a floating win with the num-loc mappings
    if win then
        vim.api.nvim_win_close(win, true)
    end

    local lines, files = render(M.items)

    -- https://jacobsimpson.github.io/nvim-lua-manual/docs/interacting/
    local H = vim.api.nvim_list_uis()[1].height
    local W = vim.api.nvim_list_uis()[1].width
    local buf = vim.api.nvim_create_buf(false, true)
    local opts = {
        relative = 'win',
        width = M.conf.width,
        height = #lines,
        row = (H - #lines) * 0.5,
        col = (W - M.conf.width) * 0.5,
        anchor = 'NW',
        style = 'minimal',
        title = "Locations",
        title_pos = 'center',
        border = 'rounded'
    }

    vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
    win = vim.api.nvim_open_win(buf, false, opts)
    vim.api.nvim_win_set_option(win, 'winhl', 'Normal:')
    vim.api.nvim_set_current_win(win)

    -- WARNING: use after setting focuss to floating window
    M.set_tui_colors()

    -- highlight filenames for easier reading
    -- WARNING: use after setting focus to floating window
    for _,file in pairs(files) do
        vim.fn.matchadd(M.conf.file_color, file)
    end

    colorize(M.items)

    vim.cmd.redraw()
end

local function close_ui()
    if win then
        vim.api.nvim_win_close(win, true)
        win = nil
    end
end

local function safe_landing(item)

    vim.cmd.edit(item.path)
    print("Moved to: " .. item.path)

    if M.conf.scope == "pos" then
        -- we need to check we are landing somewhere that exists

        local nlines = vim.api.nvim_buf_line_count(0)
        -- target line exists
        if nlines < item.lnum  then
            prompt("Target line doesn't exist.", "ErrorMsg")
            return
        end

        vim.api.nvim_win_set_cursor(0, {item.lnum, 1})

        local landing = vim.api.nvim_get_current_line()
        if #landing < item.cnum then
            prompt("Target column doesn't exist.", "ErrorMsg")
            return
        end

        vim.api.nvim_win_set_cursor(0, {item.lnum, item.cnum})
    end

    vim.cmd("norm zz")
end

local function cursor2item()
    local path = vim.api.nvim_buf_get_name(0)
    local lnum, cnum = unpack(vim.api.nvim_win_get_cursor(0))
    return {
        lnum=lnum, -- 1 indexed
        cnum=cnum, -- 0 indexed >_>
        path=path, -- full path
        filename=vim.fn.expand("%:t"), -- filename only, for highlight
        -- remove leading and trailing spaces to show preview
        content = string.gsub(vim.fn.getline(lnum), "^%s*(.-)%s*$", "%1"),
        -- bytes offset of the stored line to check if it has change 
        bytes_offset = vim.fn.line2byte(lnum)
    }
end

local function insert(n, item)
    if 1 <= n and n <=5  then
        M.stack:push({op="insert", pos=n, item=M.items[n]})
        M.items[n] = item
        save(M.items)
    end
end

local function remove(n)
    if M.items[n] then
        M.stack:push({op="insert", pos=n, item=M.items[n]})
        M.items[n] = vim.NIL
        save(M.items)
    end
end

local function undo()
    local action = M.stack:pop()
    if action == vim.NIL then
        return
    end

    if action.op == "insert" then
        M.items[action.pos] = action.item
        save(M.items)
    end
end

local function check_range(key)
    local num = key:match("^[1-5]$")
    if num then
        return tonumber(num) or 1 -- or 1 to silence the check nil nagging
    end
end

--------------------------------------------------------------------------------
-- EXPORTED STUFF
--------------------------------------------------------------------------------

-- from https://jdhao.github.io/2020/09/22/highlight_groups_cleared_in_nvim/
-- some colorschemes can clear existing highlights >_>
-- to make sure our colors works we set them every time search is started
function M.set_editor_colors()
    vim.api.nvim_set_hl(0, 'OnelocFlash', { fg = "#d4d4d4", bg = "#613315", bold = true })
end

function M.set_tui_colors()
    vim.api.nvim_set_hl(0, 'OnelocGreen', { fg = "green", bold = true })
    vim.api.nvim_set_hl(0, 'OnelocRed', { fg = "red", bold = true })
    vim.api.nvim_set_hl(0, 'OnelocGray', { fg = "gray", bold = true })
end

M.conf = {
    flash_t = 200,
    flash_color = "OnelocFlash",
    file_color = "OnelocRed", --        highlight filenames          to be MORE VISIBLE
    outdated_color = "OnelocGray", --   highlight outdated line info to be LESS VISIBLE
    uptodate_color = "OnelocGreen", --  highlight uptodate line info to be MORE VISIBLE
    scope = "pos", -- pos : include cursor position information
    width = 70
}
M.K_ESC = api.nvim_replace_termcodes('<Esc>', true, false, true)
M.K_TAB = api.nvim_replace_termcodes('<Tab>', true, false, true)
M.stack = LIFOStack:new()

function M.setup(user_conf)
    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf or {})
    M.json_path = vim.fn.stdpath("data") .. "/oneloc_"..version..".json"
    if vim.fn.filereadable(M.json_path) == 0 then
        save({vim.NIL, vim.NIL, vim.NIL, vim.NIL, vim.NIL})
        print("Initialized "..M.json_path)
    end
    M.items = load()
end

function M.show()
    if vim.version().minor < 9 and vim.version().major <= 0 then
        prompt("Oneloc requires NVIM >= 0.9", "WarningMsg")
        return nil
    end

    open_ui()

    --    ESC : close the UI
    --  [1-5] : jump to the corresponding entry
    --      D : delete all location
    -- d[1-5] : delete one location
    --    TAB : toggle scope (file vs pos)
    --      u : undo last insertion/deletion
    while (true) do
        local key = getkey()

        if key == M.K_ESC then
            break
        elseif key == "D" then
            for i =1,5 do
                if M.items[i] ~= vim.NIL then
                    remove(i)
                end
            end
        elseif key == "d" then
            local num = check_range(getkey())
            if num then
                remove(num)
            end
        elseif key == M.K_TAB then
            M.conf.scope = (M.conf.scope == "file") and "pos" or "file"
        elseif key == "u" then
            undo()
        else
            local num = check_range(key)
            if num then
                close_ui()
                M.goto(num)
            end
        end
        open_ui()
    end

    close_ui()
    prompt("", 'Nornmal')
end

-- @tparam n int
function M.record_cursor(n)
    insert(n, cursor2item())
end

-- Jump to the location stored in the n-th item
--
-- @tparam n int
function M.goto(n)
    if vim.version().minor < 9 and vim.version().major <= 0 then
        prompt("Oneloc requires NVIM >= 0.9", "WarningMsg")
        return
    end

    M.set_editor_colors()

    M.items = load()
    local destination = M.items[n]
    if destination == vim.NIL then
        print("No location found for "..n)
        return
    end

    safe_landing(destination)
    flash_line()
end

-- Get the stored line information corresponding to item n, or ""
-- Can be used to fuzzy search in the buffer.
--
-- @param n int
-- @return str
function M.get(n)
    return (M.items[n] == vim.NIL) and "" or M.items[n].content
end

return M
