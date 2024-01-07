local M = {}
local api = vim.api
local uv = vim.loop
local version = '1.0.0'


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

local function readline_at_bytes(path, nbytes)
    local file = io.open(path, "rb")
    if file then
      file:seek("set", nbytes)
      local line = file:read()
      file:close()
      return line
    end
end

local function fit_path_to_window(path, head, tail)
    -- This is a bit of a pain because of the extra stuff around the path
    -- e.g. "1) /Users/folder/file.lua:110"

    local entry = head .. path .. tail
    if #entry <= M.conf.width then
        return entry
    end

    local short_path = vim.fn.pathshorten(path)
    local short_entry = head .. short_path .. tail
    if #short_entry <= M.conf.width then
        return short_entry
    end

    return string.sub(short_entry, #short_entry - M.conf.width, #short_entry)
end

local function fit_line_to_window(line)
    if #line > M.conf.width then
        return string.sub(line, 1, M.conf.width)
    end
    return line
end

local function make_float_win()
    -- if win exists already (~nil) delete it
    -- then create a floating win with the num-loc mappings
    if win then
        vim.api.nvim_win_close(win, true)
    end

    local lines = {}
    local files = {} -- used below to highlight filenames

    -- local loc_info  = {
    --     loc=loc_str,                                 -- string to be displayed in window
    --     lnum=lnum,                                   -- line number
    --     cnum=cnum,                                   -- column number
    --     path=path,                                   -- full path
    --     filename=vim.fn.expand("%:t"),               -- filename only, for highlight
    --     time = vim.fn.getftime(vim.fn.expand('%')),  -- WIP: use it to check if file changed
    --     line = vim.fn.getline(lnum)                  -- WIP: use it show what's at the destination
    -- }

    table.insert(lines, "")
    for i=1,5 do
        local location = M.locations[i]
        local content
        local entry
        if location ~= vim.NIL then
            table.insert(files, location.filename)
            local path
            if M.conf.short_path then
                path = vim.fn.pathshorten(location.path)
            else
                path = location.path
            end
            if M.conf.granularity == "pos" then
                local head = " " .. i .. ") "
                local tail = ":"..location.lnum.." "
                entry = fit_path_to_window(path, head, tail)
                content = fit_line_to_window("    " .. location.line)
            else
                entry = fit_line_to_window(" "..i..") "..path.." ")
                content = ""
            end
        else
            -- if there are no location still give some width to the win
            entry = " "..i..")                        "
            content = ""
        end

        table.insert(lines, entry)
        -- content lines are colored after window is created
        table.insert(lines, content)
    end

    if M.conf.verbose then
        table.insert(lines, "")
        table.insert(lines, "  D: (D)elete all")
        table.insert(lines, "  d: (d)elete one")
        table.insert(lines, "  g: toggle (g)ranularity")
        table.insert(lines, "  i: (i)nsert")
    end

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

    -- color line based on "does it still match the stored value?"
    for i=1,5 do
        local location = M.locations[i]
        if location ~= vim.NIL then
            local curline = readline_at_bytes(location.path, location.bytes_offset)
            curline = string.gsub(curline, "^%s*(.-)%s*$", "%1")
            if location.line == curline then
                vim.fn.matchaddpos(M.conf.uptodate_color, {1+i*2})
            else
                vim.fn.matchaddpos(M.conf.outdated_color, {1+i*2})
            end
        end
    end

    vim.cmd.redraw()
end

local function close_float_win()
    vim.api.nvim_win_close(win, true)
    win = nil
end


local function clear()
    M.locations = {vim.NIL, vim.NIL, vim.NIL, vim.NIL, vim.NIL}
    save(M.locations)
end

local function safe_landing(location)

    vim.cmd.edit(location.path)
    print("Moved to: " .. location.path)
    if M.conf.granularity == "pos" then
        -- we need to check we are landing somewhere that exists
        local nlines = vim.api.nvim_buf_line_count(0)
        -- target line exists
        if location.lnum <= nlines then
            vim.api.nvim_win_set_cursor(0, {location.lnum, 1})
            local landing = vim.api.nvim_get_current_line()
            -- target column exists
            if #landing >= location.cnum then
                vim.api.nvim_win_set_cursor(0, {location.lnum, location.cnum})
            else
                prompt("Target column doesn't exist.", "ErrorMsg")
                return
            end
        else
            prompt("Target line doesn't exist.", "ErrorMsg")
            return
        end
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
    vim.api.nvim_set_hl(0, 'OnelocGreen', { fg = "#4c8241", bold = true })
    vim.api.nvim_set_hl(0, 'OnelocRed', { fg = "#f44747", bold = true })
    vim.api.nvim_set_hl(0, 'OnelocGray', { fg = "#465166", bold = true })
end

M.conf = {
    flash_t = 200,
    flash_color = "OnelocFlash",
    file_color = "OnelocRed", --    highlight filenames          to be MORE VISIBLE
    outdated_color = "OnelocGray", -- highlight outdated line info to be LESS VISIBLE
    uptodate_color = "OnelocGreen", --  highlight uptodate line info to be MORE VISIBLE
    short_path = false,
    granularity = "pos", -- pos : include cursor position information
    verbose = false,
    width = 100
}
M.K_Esc = api.nvim_replace_termcodes('<Esc>', true, false, true)

function M.setup(user_conf)
    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf or {})
    M.json_path = vim.fn.stdpath("data") .. "/oneloc_"..version..".json"
    if vim.fn.filereadable(M.json_path) == 0 then
        save({vim.NIL, vim.NIL, vim.NIL, vim.NIL, vim.NIL})
        print("Initialized "..M.json_path)
    end
    M.locations = load()
end

local function check_range(key)
    local num = key:match("^[1-5]$")
    if num then
        return tonumber(num) or 1 -- or 1 to silence the check nil nagging
    end
end

function M.show()
    if vim.version().minor < 9 and vim.version().major <= 0 then
        prompt("Oneloc requires NVIM >= 0.9", "WarningMsg")
        return nil
    end

    -- WARNING: Need to get the path before focusing the make_float_wining window!
    local path = vim.api.nvim_buf_get_name(0)
    local lnum, cnum = unpack(vim.api.nvim_win_get_cursor(0))
    local loc_str = path..":"..lnum..":"..cnum
    local loc_info  = {
        loc=loc_str, -- location string to be displayed in window
        lnum=lnum, -- 1 indexed
        cnum=cnum, -- 0 indexed >_>
        path=path, -- full path
        filename=vim.fn.expand("%:t"), -- filename only, for highlight
        -- remove leading and trailing spaces to show preview
        line = string.gsub(vim.fn.getline(lnum), "^%s*(.-)%s*$", "%1"),
        -- bytes offset of the stored line to check if it has change 
        bytes_offset = vim.fn.line2byte(lnum)
    }

    make_float_win()

    --    ESC : closes the make_float_wining window
    --  [1-5] : inserts current path in chosen, swaps what was there if needed
    --      D : prompt user y/N to delete all locations
    -- d[1-5] : delete correposding entry
    --      g : toggle granularity
    --      i : insert
    while (true) do
        local key = getkey()

        if key == M.K_Esc then
            break
        elseif key == "D" then
            prompt("Delete ALL the locations? [y/N]", 'WarningMsg')
            key = getkey()
            if key == "y" then
                clear()
                prompt("Locations deleted.", 'WarningMsg')
                make_float_win()
            else
                prompt("Deletion aborted.", 'Nornmal')
            end
        elseif key == "d" then
            prompt("Which location to delete? [1-5]", 'WarningMsg')
            key = getkey()
            local num = check_range(key)
            if num then
                M.locations[num] = vim.NIL
                save(M.locations)
                make_float_win()
            else
                prompt("Deletion aborted.", 'Nornmal')
            end
        elseif key == "g" then
            if M.conf.granularity == "pos" then
                M.conf.granularity = "file"
            else
                M.conf.granularity = "pos"
            end
            make_float_win()
        elseif key == "i" then
            key = getkey()
            prompt("Got"..key, 'WarningMsg')
            local num = check_range(key)
            if num then
                M.locations[num] = loc_info
                save(M.locations)
                make_float_win()
            end
        else
            local num = check_range(key)
            if num then
                close_float_win()
                M.goto(num)
                make_float_win()
            end
        end
    end

    close_float_win()
    prompt("", 'Nornmal')
end


function M.goto(n)
    if vim.version().minor < 9 and vim.version().major <= 0 then
        prompt("Oneloc requires NVIM >= 0.9", "WarningMsg")
        return
    end

    M.set_editor_colors()

    M.locations = load()

    local location = M.locations[n]
    if location == vim.NIL then
        print("No location found for "..n)
    else
        safe_landing(location)
        flash_line()
    end
end

function M.get(n)
    -- get the stored line information corresponding to entry n
    -- can be used to search it in the buffer
    if M.locations[n] == vim.NIL then
        return ""
    end
    return M.locations[n].line
end

return M
