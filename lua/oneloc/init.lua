local M = {}
local api = vim.api
local uv = vim.loop

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

local function table_contains(tbl, x)
    for i, v in pairs(tbl) do
        if v == x then
            return i
        end
    end
    return -1
end

local function split (inputstr, sep)
    -- split string based on separator
    if sep == nil then
      sep = ":"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
      table.insert(t, str)
    end
    return t
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
    set_timeout(
        M.conf.flash_t,
        vim.schedule_wrap(function()
            api.nvim_buf_del_extmark(0, flash_ns, flash_id)
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

local function get_file_name(path)
      return path:match("[^/]*.$")
end

local function parse_loc_str(loc_str)
    -- [[ Given a location like 
    --
    --      "/Users/lfrati/git/oneloc.nvim/lua/oneloc/init.lua:258:10"
    --
    --    parse it into the table:
    --
    --      { loc = "/Users/lfrati/git/oneloc.nvim/lua/oneloc/init.lua:258:10",
    --        path = "/Users/lfrati/git/oneloc.nvim/lua/oneloc/init.lua",
    --        line = 258,
    --        col = 10,
    --        filename = "init.lua"
    --      }
    -- ]]
    local path, l, c = unpack(split(loc_str))
    return {
        loc=loc_str,
        path=path,
        line=tonumber(l),
        col=tonumber(c),
        filename=get_file_name(path)
    }
end

local function make_float_win()
    -- if win exists already (~nil) delete it
    -- then create a floating win with the num-loc mappings
    if win then
        vim.api.nvim_win_close(win, true)
    end

    local lines = {}
    local width = 0 -- set win width to max length of lines
    local entry = ""
    local files = {} -- used below to highlight filenames

    for i=1,5 do
        local loc_str = M.locations[i]
        if loc_str ~= vim.NIL then

            -- { loc path line col filename }
            local location = parse_loc_str(loc_str)
            table.insert(files, location.filename)
            if M.conf.short_path then
                location.path = vim.fn.pathshorten(location.path)
            end
            if M.conf.granularity == "pos" then
                entry = " "..i..") "..location.path..":"..location.line.." "
            else
                entry = " "..i..") "..location.path.." "
            end
        else
            -- if there are no location still give some width to the win
            entry = " "..i..")                        "
        end

        if #entry > width then
            width = #entry
        end

        table.insert(lines, entry)
    end
    -- https://jacobsimpson.github.io/nvim-lua-manual/docs/interacting/
    local H = vim.api.nvim_list_uis()[1].height
    local W = vim.api.nvim_list_uis()[1].width
    local buf = vim.api.nvim_create_buf(false, true)
    local opts = {
        relative = 'win',
        width = width,
        height = #lines,
        row = (H - #lines) * 0.5,
        col = (W - width) * 0.5,
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

    -- highlight filenames for easier reading
    -- WARNING: use after setting focus to floating window
    for _,file in pairs(files) do
        vim.fn.matchadd(M.conf.file_color, file)
    end
    vim.cmd.redraw()
end

local function close_float_win()
    vim.api.nvim_win_close(win, true)
    win = nil
end

local function prompt(msg, style)
    vim.cmd.redraw()
    api.nvim_echo({ { msg, style } }, false, {})
end

local function update(n, path)
    local ix = table_contains(M.locations, path)
    if ix == -1 then
        -- new location
        M.locations[n] = path
    else
        -- location exists already, swap old and new location
        M.locations[ix] = M.locations[n]
        M.locations[n] = path
    end
    save(M.locations)
end

local function clear()
    M.locations = {vim.NIL, vim.NIL, vim.NIL, vim.NIL, vim.NIL}
    save(M.locations)
end

--------------------------------------------------------------------------------
-- EXPORTED STUFF
--------------------------------------------------------------------------------

M.conf = {
    flash_t = 200,
    flash_color = "OnelocFlash",
    file_color = "ErrorMsg",
    short_path = true,
    granularity = "pos"
}
M.K_Esc = api.nvim_replace_termcodes('<Esc>', true, false, true)

function M.set_colors()
    vim.api.nvim_set_hl(0, 'OnelocFlash', { fg = "#d4d4d4", bg = "#613315", bold = true })
end

function M.setup(user_conf)
    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf or {})
    M.json_path = vim.fn.stdpath("data") .. "/oneloc.json"
    if vim.fn.filereadable(M.json_path) == 0 then
        save({vim.NIL, vim.NIL, vim.NIL, vim.NIL, vim.NIL})
        print("Initialized "..M.json_path)
    end
    M.locations = load()
end


function M.show()
    -- WARNING: Need to get the path before focusing the make_float_wining window!
    local path = vim.api.nvim_buf_get_name(0)
    local lnum, cnum = unpack(vim.api.nvim_win_get_cursor(0))

    path = path..":"..lnum..":"..cnum

    make_float_win()

    --   ESC : closes the make_float_wining window
    -- [1-5] : inserts current path in chosen, swaps what was there if needed
    --     d : Prompt user y/N to delete all locations
    while (true) do
        local key = getkey()
        local num = key:match("^[1-5]$")

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
            num = key:match("^[1-5]$")
            if num then
                num = tonumber(num)
                local old = M.locations[num]
                if num and old ~= vim.NIL then
                    M.locations[num] = vim.NIL
                    save(M.locations)
                    prompt("Location ["..num..") "..old.."] deleted.", 'WarningMsg')
                    make_float_win()
                end
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
        elseif num then
            update(tonumber(num), path)
            make_float_win()
        end
    end

    close_float_win()
    prompt("", 'Nornmal')
end


local function safe_landing(loc_string)

    local location = parse_loc_str(loc_string)

    vim.cmd.edit(location.path)

    print("Moved to: " .. location.path)

    if M.conf.granularity == "pos" then
        -- we need to check we are landing somewhere that exists
        local nlines = vim.api.nvim_buf_line_count(0)
        -- target line exists
        if location.line <= nlines then
            vim.api.nvim_win_set_cursor(0, {location.line, 1})
            local landing = vim.api.nvim_get_current_line()
            -- target column exists
            if #landing >= location.col then
                vim.api.nvim_win_set_cursor(0, {location.line, location.col})
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

function M.goto(n)
    M.set_colors()

    -- api.nvim_echo({ { "ONETAB: ".. path, 'Normal' } }, false, {})
    M.locations = load()

    local location = M.locations[n]
    if location == vim.NIL then
        print("No location found for "..n)
    else
        safe_landing(location)
        flash_line()
    end
end

return M
