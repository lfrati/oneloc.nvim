local M = {}
local api = vim.api
local uv = vim.loop

-- https://stevedonovan.github.io/ldoc/manual/doc.md.html

local flash_ns = vim.api.nvim_create_namespace("OnelocFlash")

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
    set_timeout(
        M.conf.flash_t,
        vim.schedule_wrap(function()
            api.nvim_buf_del_extmark(0, flash_ns, flash_id)
            vim.cmd("redraw")
        end))
end

--------------------------------------------------------------------------------
-- EXPORTED STUFF
--------------------------------------------------------------------------------

M.conf = {
    flash_t = 200,
    flash_color = "OnelocFlash",
    short_path = true,
}
M.K_Esc = api.nvim_replace_termcodes('<Esc>', true, false, true)

function M.set_colors()
    vim.api.nvim_set_hl(0, 'OnelocFlash', { fg = "#d4d4d4", bg = "#613315", bold = true })
end

function M.setup(user_conf)
    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf or {})
    M.json_path = vim.fn.stdpath("data") .. "/oneloc.json"
    if vim.fn.filereadable(M.json_path) == 0 then
        M.save({})
        print("Initialized "..M.json_path)
    end
    M.locations = M.load()
end

function M.save(tbl)
    local json = vim.json.encode(tbl)
    local ok, result = pcall(vim.fn.writefile, { json }, M.json_path)

    if ok then
        print("Saved.")
    else
        print(result)
    end
end

function M.load()
    local ok, result = pcall(vim.fn.readfile, M.json_path)
    if ok then
        return vim.json.decode(result[1])
    else
        error("ERROR: could not load " .. M.json_path)
    end
end

function M.show()
    local lines = {}
    local width = 0
    local line
    for i=1,5 do
        local path = M.locations[i]
        if path ~= nil and path ~= vim.NIL then
            if M.conf.short_path then
            line = " "..i..") "..vim.fn.pathshorten(path).." "
            else
                line = " "..i..") "..path.." "
            end
        else
            line = " "..i..")                          "
        end
        if #line > width then
            width = #line
        end
        table.insert(lines, line)
    end
    if width > 0 then
        -- https://jacobsimpson.github.io/nvim-lua-manual/docs/interacting/
        local H = vim.api.nvim_list_uis()[1].height
        local W = vim.api.nvim_list_uis()[1].width
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
        local opts = {
            relative = 'win',
            width = width,
            height = #lines,
            row = (H - #lines) * 0.5,
            col = (W - width) * 0.5,
            anchor = 'NW',
            style = 'minimal',
            title="Oneloc:",
            border= 'single'
        }
        local win = vim.api.nvim_open_win(buf, false, opts)
        vim.api.nvim_win_set_option(win, 'winhl', 'Normal:')
        vim.api.nvim_set_current_win(win)
        vim.cmd("redraw")

        while (true) do
            local key = getkey()
            if key == M.K_Esc then -- reject
                vim.api.nvim_win_close(win, true)
                break
            end
        end

    end
end

function M.update(n)
    local path = vim.api.nvim_buf_get_name(0)
    M.locations[n] = path
    M.save(M.locations)
    M.show()
end

function M.clear()
    M.locations = {}
    M.save(M.locations)
end

function M.goto(n)
    M.set_colors()

    -- api.nvim_echo({ { "ONETAB: ".. path, 'Normal' } }, false, {})
    M.locations = M.load()

    local destination = M.locations[n]
    -- decoding json may put vim.NIL inside the json, gotta check both
    if destination == vim.NIL or destination == nil then
        print("No destination found for "..n)
    else
        P("Moving to: "..destination)
        vim.cmd.edit(destination)
        flash_line()
    end
end

return M
