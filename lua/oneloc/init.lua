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
    -- vim.fn.win_getid()
    -- vim.fn.win
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

    -- local loc_info  = {
    --     loc=loc_str,                                 -- string to be displayed in window
    --     lnum=lnum,                                   -- line number
    --     cnum=cnum,                                   -- column number
    --     path=path,                                   -- full path
    --     filename=vim.fn.expand("%:t"),               -- filename only, for highlight
    --     time = vim.fn.getftime(vim.fn.expand('%')),  -- WIP: use it to check if file changed
    --     line = vim.fn.getline(lnum)                  -- WIP: use it show what's at the destination
    -- }

    if M.conf.granularity == "pos" then
        table.insert(lines, "Mode: LINE")
        table.insert(lines, "")
    else
        table.insert(lines, "Mode: FILE")
        table.insert(lines, "")
    end

    for i=1,5 do
        local location = M.locations[i]

        if location ~= vim.NIL then
            table.insert(files, location.filename)
            local path
            if M.conf.short_path then
                path = vim.fn.pathshorten(location.path)
            else
                path = location.path
            end
            if M.conf.granularity == "pos" then
                entry = " "..i..") "..path..":"..location.lnum.." "
            else
                entry = " "..i..") "..path.." "
            end
        else
            -- if there are no location still give some width to the win
            entry = " "..i..")                        "
        end

        -- record max length to adjust window size
        if #entry > width then
            width = #entry
        end
        table.insert(lines, entry)

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
    -- vim.fn.matchadd(M.conf.file_color, 'Mode: LINE')
    -- vim.fn.matchadd(M.conf.file_color, 'Mode: FILE')
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

M.conf = {
    flash_t = 200,
    flash_color = "OnelocFlash",
    file_color = "ErrorMsg",
    short_path = true,
    granularity = "pos", -- pos : include cursor position information
    verbose = false
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
        loc=loc_str, -- string to be displayed in window
        lnum=lnum,
        cnum=cnum,
        path=path, -- full path
        filename=vim.fn.expand("%:t"), -- filename only, for highlight
        time = vim.fn.getftime(vim.fn.expand('%')),
        line = vim.fn.getline(lnum)
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
