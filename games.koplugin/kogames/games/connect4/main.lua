--[[--
四子棋（7 列 × 6 行，重力落子）。玩家执黑先行，对手是 alpha-beta 搜索 AI；可悔棋。
棋盘下标 (r-1)*COLS+c，r=1 为最上一行。
--]]
local T = require("kogames.l10n")
local ROWS, COLS = 6, 7
local EMPTY, HUMAN, AI = 0, 1, 2
local ORDER = { 4, 3, 5, 2, 6, 1, 7 }
local WIN = 1000000

local Core = {}

function Core.fresh()
    local s = { board = {}, moves = {}, winner = nil }
    for i = 1, ROWS * COLS do s.board[i] = EMPTY end
    return s
end

local DIRS = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }

local function at(board, r, c)
    if r < 1 or r > ROWS or c < 1 or c > COLS then return nil end
    return board[(r - 1) * COLS + c]
end

function Core.wins(board, r, c, who)
    for _, d in ipairs(DIRS) do
        local n = 1
        for sign = -1, 1, 2 do
            local rr, cc = r + d[1] * sign, c + d[2] * sign
            while at(board, rr, cc) == who do
                n = n + 1
                rr, cc = rr + d[1] * sign, cc + d[2] * sign
            end
        end
        if n >= 4 then return true end
    end
    return false
end

--- 该列最下面的空行；列满返回 nil
function Core.landing(board, c)
    for r = ROWS, 1, -1 do
        if board[(r - 1) * COLS + c] == EMPTY then return r end
    end
    return nil
end

--- 在列 c 落子，返回落到的行；列满、已结束返回 false
function Core.drop(s, c, who)
    if s.winner or c < 1 or c > COLS then return false end
    local r = Core.landing(s.board, c)
    if not r then return false end
    local idx = (r - 1) * COLS + c
    s.board[idx] = who
    s.moves[#s.moves + 1] = idx
    if Core.wins(s.board, r, c, who) then s.winner = who
    elseif #s.moves == ROWS * COLS then s.winner = 0 end
    return r
end

function Core.undo(s)
    -- 对手没来得及走（玩家刚赢）则只撤一步
    local n = (s.winner == HUMAN or #s.moves % 2 == 1) and 1 or 2
    for _ = 1, n do
        local idx = table.remove(s.moves)
        if idx then s.board[idx] = EMPTY end
    end
    s.winner = nil
end

-- 所有长度 4 的窗口
local WINDOWS = {}
for r = 1, ROWS do for c = 1, COLS do
    for _, d in ipairs(DIRS) do
        local er, ec = r + d[1] * 3, c + d[2] * 3
        if er >= 1 and er <= ROWS and ec >= 1 and ec <= COLS then
            local w = {}
            for k = 0, 3 do w[k + 1] = (r + d[1] * k - 1) * COLS + c + d[2] * k end
            WINDOWS[#WINDOWS + 1] = w
        end
    end
end end

local function evaluate(b)
    local score = 0
    for i = 1, ROWS do
        local v = b[(i - 1) * COLS + 4]
        if v == AI then score = score + 3 elseif v == HUMAN then score = score - 3 end
    end
    for _, w in ipairs(WINDOWS) do
        local a, h = 0, 0
        for k = 1, 4 do
            local v = b[w[k]]
            if v == AI then a = a + 1 elseif v == HUMAN then h = h + 1 end
        end
        if h == 0 then
            if a == 3 then score = score + 5 elseif a == 2 then score = score + 2 end
        elseif a == 0 then
            if h == 3 then score = score - 5 elseif h == 2 then score = score - 2 end
        end
    end
    return score
end

-- 以 who 的视角做 negamax；返回分数
local function search(b, who, depth, alpha, beta, filled)
    local opp = who == AI and HUMAN or AI
    if filled == ROWS * COLS then return 0 end
    if depth == 0 then
        local e = evaluate(b)
        return who == AI and e or -e
    end
    local best = -math.huge
    for _, c in ipairs(ORDER) do
        local r = Core.landing(b, c)
        if r then
            local idx = (r - 1) * COLS + c
            b[idx] = who
            local v
            if Core.wins(b, r, c, who) then v = WIN + depth
            else v = -search(b, opp, depth - 1, -beta, -alpha, filled + 1) end
            b[idx] = EMPTY
            if v > best then best = v end
            if v > alpha then alpha = v end
            if alpha >= beta then break end
        end
    end
    return best
end

--- AI 选列（1..7），棋盘已满返回 nil
function Core.aiMove(s, depth)
    depth = depth or 5
    local b = {}
    for i = 1, ROWS * COLS do b[i] = s.board[i] end
    local best, bc = -math.huge, nil
    local alpha = -math.huge
    for _, c in ipairs(ORDER) do
        local r = Core.landing(b, c)
        if r then
            local idx = (r - 1) * COLS + c
            b[idx] = AI
            local v
            if Core.wins(b, r, c, AI) then v = WIN + depth
            else v = -search(b, HUMAN, depth - 1, -math.huge, -alpha, #s.moves + 1) end
            b[idx] = EMPTY
            if v > best then best, bc = v, c end
            if v > alpha then alpha = v end
        end
    end
    return bc
end

local M = { id = "connect4", title = T("四子棋"), icon = "radio_button_unchecked", tier = "A", desc = T("人机对弈"), help = T("你执黑先手。点按任意一列，棋子会落到该列最底部的空位。\n横、竖、斜任意方向先连成四子者获胜。\n下错了可以悔棋，会同时撤回你和对手的最近一步。"), core = Core }

function M.new(ctx)
    local self = {}
    local s

    local function persist() ctx:save({ state = s }) end

    local function tap(_, c)
        if s.winner then return end
        if not Core.drop(s, c, HUMAN) then return end
        if not s.winner then
            local ac = Core.aiMove(s)
            if ac then Core.drop(s, ac, AI) end
        end
        if s.winner == HUMAN then
            ctx:record("wins", (ctx:best("wins") or 0) + 1)
        end
        persist()
        self.render()
    end

    function self.render()
        local status = T("你执黑")
        if s.winner == HUMAN then status = T("你赢了！")
        elseif s.winner == AI then status = T("对手获胜")
        elseif s.winner == 0 then status = T("平局") end
        status = status .. (T("    第 %d 手    累计获胜 %d 局")):format(#s.moves, ctx:best("wins") or 0)
        ctx:render({
            title = T("四子棋"),
            status = status,
            grid = {
                rows = ROWS, cols = COLS, on_tap = tap,
                cell = function(r, c)
                    local v = s.board[(r - 1) * COLS + c]
                    if v == HUMAN then return { icon = "stone_black", icon_scale = 0.85 } end
                    if v == AI then return { icon = "stone_white", icon_scale = 0.85 } end
                    return {}
                end,
            },
            buttons = {
                {
                    { text = T("悔棋"), enabled = #s.moves > 0, callback = function() Core.undo(s) persist() self.render() end },
                    { text = T("新局"), callback = function() s = Core.fresh() persist() self.render() end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        s = saved and saved.state or Core.fresh()
        self.render()
    end

    self.tap, self.state = tap, function() return s end
    return self
end

return M
