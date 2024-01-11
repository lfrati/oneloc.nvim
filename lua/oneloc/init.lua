local M = {}
local api = vim.api
local uv = vim.loop
local version = '1.2.0'


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

-- @param key string or number
local function check_range(key)
    if type(key) == "number" then
        key = tostring(key)
    end
    local num = key:match("^[1-5]$")
    if num then
        return tonumber(num)
    end
    return vim.NIL
end


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

local function flash_line()
    -- Make the current line flash to help me find it more easily.
    local lnum, _ = unpack(vim.api.nvim_win_get_cursor(0))
    local mask = mask_line(lnum)
    local flash_id = api.nvim_buf_set_extmark(0, flash_ns, lnum - 1, 0, {
        virt_text = { { mask, M.conf.colors.flash } },
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


local function is_still_valid(item)
    local current = read_nth_line(item.path, item.lnum)
    if current then
        current = string.gsub(current, "^%s*(.-)%s*$", "%1")
        if current == item.content then
            return true
        end
    end

    return false
end

-- @param mode string ["files", "marks"]
local function safe_landing(item, mode)

    vim.cmd.edit(item.path)
    print("Moved to: " .. item.path)

    if mode == "marks" then
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
        lnum = lnum, -- 1 indexed
        cnum = cnum, -- 0 indexed >_>
        path = path, -- full path
        file = vim.fn.expand("%:t"), -- file name only, for highlight
        -- remove leading and trailing spaces to show preview
        content = string.gsub(vim.fn.getline(lnum), "^%s*(.-)%s*$", "%1"),
    }
end

local function save(items, path)
    local json = vim.json.encode(items)
    local ok, result = pcall(vim.fn.writefile, { json }, path)
    if ok == false then
        print(result)
    end
end
local function load(path)
    local ok, result = pcall(vim.fn.readfile, path)
    if ok then
        return vim.json.decode(result[1])
    else
        error("ERROR: could not load " .. path)
    end
end

-- ============================================================================
-- =======================        UI          =================================
-- ============================================================================

local UI = {}
function UI:new(colors, width, mode)
    local obj = {
        items = {vim.NIL, vim.NIL, vim.NIL, vim.NIL, vim.NIL},
        mode = mode,
        colors=colors,
        width=width,
        win=nil,
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end
function UI:render(items)
    local lines = {}

    table.insert(lines, "")
    for i=1,5 do
        local item = items[i]
        local entry = fit_line_to_window(" "..i)
        local content = ""
        if item ~= vim.NIL then
            if self.mode == "files" then
                local head = " " .. i .. " "
                local tail = ""
                entry = fit_path_to_window(item.path, head, tail)
                content = fit_line_to_window("    " .. item.content)
            else
                local head = " " .. i .. " "
                local tail = ":"..item.lnum..":"..item.cnum.." "
                entry = fit_path_to_window(item.path, head, tail)
                content = fit_line_to_window("    " .. item.content)
            end
        end

        table.insert(lines, entry)
        -- content lines are colored after window is created
        table.insert(lines, content)
        table.insert(lines, "")
    end

    return lines
end
function UI:colorize(items)
    -- https://stackoverflow.com/a/23247938
    vim.cmd[[
        hi Bang ctermfg=yellow guifg=yellow
        match Bang /\%>1v.*\%<3v/
    ]]
    -- color line based on "does it still match the stored value?"
    for i=1,5 do
        local item = items[i]
        if item ~= vim.NIL then
            vim.fn.matchadd(self.colors.file, item.file)
            if is_still_valid(item) then
                -- 1 line of padding
                -- each item spans 3 lines 
                -- line content is the second line of the 3
                vim.fn.matchaddpos(self.colors.uptodate, {1 + (i-1)*3 + 2})
            else
                vim.fn.matchaddpos(self.colors.outdated, {1 + (i-1)*3 + 2})
            end
        end
    end
end
function UI:open(items)
    -- if win exists already (~nil) delete it
    -- then create a floating win with the num-loc mappings
    if self.win then
        vim.api.nvim_win_close(self.win, true)
    end

    local lines = self:render(items)

    -- https://jacobsimpson.github.io/nvim-lua-manual/docs/interacting/
    local H = vim.api.nvim_list_uis()[1].height
    local W = vim.api.nvim_list_uis()[1].width
    local buf = vim.api.nvim_create_buf(false, true)
    local opts = {
        relative = 'win',
        width = self.width,
        height = #lines,
        row = (H - #lines) * 0.5,
        col = (W - self.width) * 0.5,
        anchor = 'NW',
        style = 'minimal',
        title = "Locations (".. self.mode .. ")",
        title_pos = 'center',
        border = 'rounded'
    }

    vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
    self.win = vim.api.nvim_open_win(buf, false, opts)
    vim.api.nvim_win_set_option(self.win, 'winhl', 'Normal:')
    vim.api.nvim_set_current_win(self.win)

    self:colorize(items)

    vim.cmd.redraw()
end
function UI:close()
    if self.win then
        vim.api.nvim_win_close(self.win, true)
        self.win = nil
    end
end

-- ============================================================================
-- =======================       CORE         =================================
-- ============================================================================

local Core = {}
function Core:new(json_path)
    local obj = {
        items = {vim.NIL, vim.NIL, vim.NIL, vim.NIL, vim.NIL},
        json_path = json_path,
        stack=LIFOStack:new()
    }
    setmetatable(obj, self)
    self.__index = self
    return obj
end
function Core:insert(key, item)
    local n = check_range(key)
    if n == vim.NIL then
        return
    end
    self.stack:push({pos=n, item=self.items[n]})
    self.items[n] = item
    save(self.items, self.json_path)
end
function Core:remove(key)
    local n = check_range(key)
    if n == vim.NIL or self.items[n] == vim.NIL then
        return
    end

    self.stack:push({pos=n, item=self.items[n]})
    self.items[n] = vim.NIL
    save(self.items, self.json_path)
end
function Core:undo()
    local action = self.stack:pop()
    if action == vim.NIL then
        return
    end
    self.items[action.pos] = action.item
    save(self.items, self.json_path)
end
function Core:goto(key, mode)
    local n = check_range(key)
    if n == vim.NIL then
        return
    end

    self.items = load(self.json_path)
    local destination = self.items[n]

    if destination == vim.NIL then
        print("No location found for "..n)
        return
    end

    safe_landing(destination, mode)
    flash_line()
end

--==============================================================================
--==============             MAIN LOOP               ===========================
--==============================================================================

local function show(ui, core)
    if vim.version().minor < 9 and vim.version().major <= 0 then
        prompt("Oneloc requires NVIM >= 0.9", "WarningMsg")
        return nil
    end

    ui:open(core.items)

    --    ESC : close the UI
    --  [1-5] : jump to the corresponding entry
    --      D : delete all location
    -- d[1-5] : delete one location
    --      u : undo last insertion/deletion
    while (true) do
        local key = getkey()

        if key == M.K_ESC then
            break
        elseif key == M.K_TAB then
            ui.mode = (ui.mode == "marks") and "files" or "marks"
        elseif key == "D" then
            for i =1,5 do
                core:remove(i)
            end
        elseif key == "d" then
            core:remove(getkey())
        elseif key == "u" then
            core:undo()
        else
            ui:close()
            core:goto(key)
        end
        ui:open(core.items)
    end

    ui:close(core.items)
end

--==============================================================================
--==============             EXPORTED STUFF          ===========================
--==============================================================================

-- from https://jdhao.github.io/2020/09/22/highlight_groups_cleared_in_nvim/
-- some colorschemes can clear existing highlights >_>
function M.set_colors()
    vim.api.nvim_set_hl(0, 'OnelocFlash', { fg = "#d4d4d4", bg = "#613315", bold = true })
    vim.api.nvim_set_hl(0, 'OnelocGreen', { fg = "green", bold = true })
    vim.api.nvim_set_hl(0, 'OnelocRed', { fg = "red", bold = true })
    vim.api.nvim_set_hl(0, 'OnelocGray', { fg = "gray", bold = true })
end

M.conf = {
    flash_t = 200,
    width = 70,
    mode = "files",
    colors = {
        flash = "OnelocFlash",--      highlight cursor line       
        file = "OnelocRed", --        highlight file name
        outdated = "OnelocGray", --   highlight outdated line info
        uptodate = "OnelocGreen", --  highlight uptodate line info
    }
}
M.K_ESC = api.nvim_replace_termcodes('<Esc>', true, false, true)
M.K_TAB = api.nvim_replace_termcodes('<Tab>', true, false, true)

function M.setup(user_conf)
    if vim.version().minor < 9 and vim.version().major <= 0 then
        prompt("Oneloc requires NVIM >= 0.9", "WarningMsg")
    end

    M.conf = vim.tbl_deep_extend("force", M.conf, user_conf or {})
    M.json_path = vim.fn.stdpath("data") .. "/oneloc_"..version..".json"
    M.ui = UI:new(M.conf.colors, M.conf.width, M.conf.mode)
    M.core = Core:new(M.json_path)

    if vim.fn.filereadable(M.json_path) == 0 then
        save({vim.NIL, vim.NIL, vim.NIL, vim.NIL, vim.NIL}, M.json_path)
    end
    M.core.items = load(M.json_path)

    vim.api.nvim_create_augroup('OnelocColors', { clear = true })
    vim.api.nvim_create_autocmd('BufEnter', {
        group = "OnelocColors",
        pattern = '',
        callback = function()
            M.core.items = load(M.json_path)
        end
    })
    vim.api.nvim_create_autocmd('BufLeave', {
        group = "OnelocColors",
        pattern = '',
        callback = function()
            save(M.core.items, M.json_path)
        end
    })

end

-- @tparam n int
function M.record_cursor(n)
    local item = cursor2item()
    M.core:insert(n, item)
end

-- Jump to the location stored in the n-th item
--
-- @tparam n int
function M.goto(n)
    M.set_colors()
    M.core:goto(n)
end
function M.show()
    M.set_colors()
    show(M.ui, M.core)
end
return M
