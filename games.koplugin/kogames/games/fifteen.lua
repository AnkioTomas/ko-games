--[[--
数字华容道。点击与空格同行/同列的数字，整段向空格滑动；滑动手势 dir 表示数字移动的方向
（向 west 滑 = 空格右侧的数字向左移动）。可撤销，记录各尺寸最少步数。
--]]
local T = require("kogames.l10n")
local SIZES = { 3, 4, 5 }
local UNDO_CAP = 100

local Core = {}

function Core.solvedBoard(n)
    local b = {}
    for i = 1, n * n - 1 do b[i] = i end
    b[n * n] = 0
    return b
end

function Core.blank(s)
    for i = 1, s.n * s.n do if s.board[i] == 0 then return math.floor((i - 1) / s.n) + 1, (i - 1) % s.n + 1 end end
end

function Core.solved(s)
    local n = s.n
    for i = 1, n * n - 1 do if s.board[i] ~= i then return false end end
    return s.board[n * n] == 0
end

--- 点击 (r,c)：与空格同行或同列时整段滑动，返回是否移动。
function Core.slide(s, r, c)
    local n = s.n
    local br, bc = Core.blank(s)
    if (r == br) == (c == bc) then return false end
    local b = s.board
    if r == br then
        local step = c < bc and -1 or 1
        for k = bc, c - step, step do b[(r - 1) * n + k] = b[(r - 1) * n + k + step] end
    else
        local step = r < br and -1 or 1
        for k = br, r - step, step do b[(k - 1) * n + c] = b[(k + step - 1) * n + c] end
    end
    b[(r - 1) * n + c] = 0
    s.moves = s.moves + 1
    return true
end

--- 数字向 dir 方向移动一格（即空格对侧的数字移入空格）。
function Core.swipe(s, dir)
    local br, bc = Core.blank(s)
    local r, c = br, bc
    if dir == "west" then c = bc + 1 elseif dir == "east" then c = bc - 1
    elseif dir == "north" then r = br + 1 elseif dir == "south" then r = br - 1 else return false end
    if r < 1 or c < 1 or r > s.n or c > s.n then return false end
    return Core.slide(s, r, c)
end

local OFFS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

function Core.fresh(rng, n)
    n = n or 4
    local s
    repeat
        s = { n = n, board = Core.solvedBoard(n), moves = 0 }
        local last
        for _ = 1, n * n * 30 do
            local br, bc = Core.blank(s)
            local cand = {}
            for i, o in ipairs(OFFS) do
                local r, c = br + o[1], bc + o[2]
                if r >= 1 and c >= 1 and r <= n and c <= n and i ~= last then cand[#cand + 1] = i end
            end
            local i = cand[rng:int(#cand)]
            local o = OFFS[i]
            Core.slide(s, br + o[1], bc + o[2])
            -- 反方向是撤销上一步
            last = i % 2 == 1 and i + 1 or i - 1
        end
        s.moves = 0
    until not Core.solved(s)
    return s
end

local function copyBoard(b)
    local t = {}
    for i = 1, #b do t[i] = b[i] end
    return t
end

local M = { id = "fifteen", title = T("数字华容道"), icon = "apps", art = "icon_fifteen", tier = "A", desc = T("滑动数字归位"), core = Core }

function M.new(ctx)
    local self = {}
    local s, undo

    local function key() return "best" .. s.n end
    local function persist() ctx:save({ state = s, undo = undo }) end

    local function fresh(n)
        s, undo = Core.fresh(ctx.rng, n), {}
        persist()
        self.render()
    end

    local function afterMove(before)
        undo[#undo + 1] = before
        if #undo > UNDO_CAP then table.remove(undo, 1) end
        if Core.solved(s) then
            s.done = true
            if ctx:record(key(), s.moves, true) then ctx:notify(T("新纪录：%d", s.moves)) end
        end
        persist()
        self.render()
    end

    local function tapCell(r, c)
        if s.done then return end
        local before = copyBoard(s.board)
        if Core.slide(s, r, c) then afterMove(before) end
    end

    local function swipe(dir)
        if s.done then return end
        local before = copyBoard(s.board)
        if Core.swipe(s, dir) then afterMove(before) end
    end

    function self.render()
        local n = s.n
        local best = ctx:best(key())
        local status = T("步数 %d", s.moves)
        if best then status = status .. T("    最少 %d", best) end
        if s.done then status = status .. T("    完成！") end
        local size_row = {}
        for _, k in ipairs(SIZES) do
            size_row[#size_row + 1] = { text = k .. "×" .. k, selected = k == n, callback = function() if k ~= n then fresh(k) end end }
        end
        ctx:render({
            title = T("数字华容道"),
            status = status,
            grid = {
                rows = n, cols = n, gap = true,
                cell = function(r, c)
                    local v = s.board[(r - 1) * n + c]
                    if v == 0 then return nil end
                    return { text = tostring(v), fill = "grey", scale = v >= 10 and 0.42 or 0.5 }
                end,
                on_tap = tapCell,
            },
            on_swipe = swipe,
            buttons = {
                size_row,
                {
                    { text = T("撤销"), enabled = #undo > 0 and not s.done, callback = function()
                        s.board = table.remove(undo)
                        s.moves = s.moves - 1
                        persist()
                        self.render()
                    end },
                    { text = T("新游戏"), callback = function() fresh(s.n) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.board then
            s, undo = saved.state, saved.undo or {}
        else
            s, undo = Core.fresh(ctx.rng, 4), {}
        end
        self.render()
    end

    self.state = function() return s end
    self.tap = tapCell
    self.swipe = swipe
    return self
end

return M
