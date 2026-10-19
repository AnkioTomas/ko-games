--[[--
独粒棋（Peg Solitaire，英式十字盘 33 孔）。点一颗棋子选中，再点它上/下/左/右隔一格的空孔，
就会跳过中间的棋子并把它吃掉。目标是只剩一颗，最好剩在正中。
--]]
local T = require("kogames.l10n")
local N = 7
local VALID = {}
for r = 1, N do
    for c = 1, N do
        VALID[(r - 1) * N + c] = (r >= 3 and r <= 5) or (c >= 3 and c <= 5)
    end
end
local DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local Core = {}

function Core.fresh()
    local b = {}
    for i = 1, N * N do b[i] = VALID[i] and true or nil end
    b[(4 - 1) * N + 4] = false
    return { board = b, hist = {} }
end

function Core.count(s)
    local n = 0
    for i = 1, N * N do if s.board[i] then n = n + 1 end end
    return n
end

--- 从 i 出发能跳到的孔（序号）列表。
function Core.targets(s, i)
    local out = {}
    if not s.board[i] then return out end
    local r, c = math.floor((i - 1) / N) + 1, (i - 1) % N + 1
    for _, d in ipairs(DIRS) do
        local r1, c1, r2, c2 = r + d[1], c + d[2], r + 2 * d[1], c + 2 * d[2]
        if r2 >= 1 and r2 <= N and c2 >= 1 and c2 <= N then
            local m, t = (r1 - 1) * N + c1, (r2 - 1) * N + c2
            if s.board[m] and s.board[t] == false then out[#out + 1] = t end
        end
    end
    return out
end

function Core.hasMove(s)
    for i = 1, N * N do
        if #Core.targets(s, i) > 0 then return true end
    end
    return false
end

function Core.jump(s, i, t)
    for _, x in ipairs(Core.targets(s, i)) do
        if x == t then
            local mid = (i + t) / 2
            s.hist[#s.hist + 1] = { i, mid, t }
            s.board[i], s.board[mid], s.board[t] = false, false, true
            return true
        end
    end
    return false
end

function Core.undo(s)
    local h = table.remove(s.hist)
    if not h then return false end
    s.board[h[1]], s.board[h[2]], s.board[h[3]] = true, true, false
    return true
end

local M = { id = "pegsolitaire", title = T("独粒棋"), icon = "radio_button_unchecked", tier = "A", desc = T("跳吃棋子，只剩一颗"), help = T("目标：把棋盘上的棋子吃到只剩一颗，剩在正中最完美。\n点一颗棋子选中，再点它上、下、左、右隔一格的空孔，棋子会跳过去并吃掉中间那颗。\n选中后，可以跳到的空孔会显示小方块。走错了可以撤销。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, sel

    local function persist() ctx:save({ state = s }) end

    local function fresh()
        s = Core.fresh()
        sel = nil
        persist()
        self.render()
    end

    local function tap(r, c)
        local i = (r - 1) * N + c
        if not VALID[i] or s.done then return end
        if sel and s.board[i] == false and Core.jump(s, sel, i) then
            sel = nil
            local left = Core.count(s)
            if left == 1 or not Core.hasMove(s) then
                s.done = true
                if ctx:record("left", left, true) then ctx:notify(T("新纪录：%d", left)) end
            end
        elseif s.board[i] then
            sel = (sel ~= i) and i or nil
        else
            sel = nil
        end
        persist()
        self.render()
    end

    function self.render()
        local left = Core.count(s)
        local status = T("剩余 %d 颗", left)
        local best = ctx:best("left")
        if best then status = status .. T("    最少 %d", best) end
        if s.done then
            status = status .. (left == 1 and T("    完成！") or T("    无路可走"))
        end
        local tg = {}
        if sel then for _, t in ipairs(Core.targets(s, sel)) do tg[t] = true end end
        ctx:render({
            title = T("独粒棋"),
            status = status,
            grid = {
                rows = N, cols = N, gap = true,
                cell = function(r, c)
                    local i = (r - 1) * N + c
                    if not VALID[i] then return nil end
                    if s.board[i] then
                        return { fill = i == sel and "dark" or "grey", shape = "black" }
                    end
                    return { fill = "grey", mark = tg[i] and "black" or nil }
                end,
                on_tap = tap,
            },
            buttons = {
                { { menu = true, text = T("撤销"), enabled = #s.hist > 0, callback = function()
                    if Core.undo(s) then s.done = nil sel = nil persist() self.render() end
                end },
                    { menu = true, text = T("新游戏"), callback = fresh } },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.board and saved.state.hist then
            s = saved.state
            self.render()
        else
            fresh()
        end
    end

    self.state = function() return s end
    self.tap = tap
    return self
end

return M
