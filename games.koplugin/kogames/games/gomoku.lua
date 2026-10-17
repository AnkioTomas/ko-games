--[[--
五子棋（自由规则，15×15）。玩家执黑先行，对手是启发式评分 AI；可悔棋。
--]]
local T = require("kogames.l10n")
local N = 15
local EMPTY, HUMAN, AI = 0, 1, 2

local Core = {}

function Core.fresh()
    local s = { board = {}, moves = {}, winner = nil }
    for i = 1, N * N do s.board[i] = EMPTY end
    return s
end

local DIRS = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }

local function at(board, r, c)
    if r < 1 or r > N or c < 1 or c > N then return nil end
    return board[(r - 1) * N + c]
end

-- 假设 who 落在 (r,c)，该方向上连成的子数和两端是否敞开
local function line(board, r, c, who, dr, dc)
    local n, open = 1, 0
    for sign = -1, 1, 2 do
        local rr, cc = r + dr * sign, c + dc * sign
        while at(board, rr, cc) == who do
            n = n + 1
            rr, cc = rr + dr * sign, cc + dc * sign
        end
        if at(board, rr, cc) == EMPTY then open = open + 1 end
    end
    return n, open
end

function Core.wins(board, r, c, who)
    for _, d in ipairs(DIRS) do
        if (line(board, r, c, who, d[1], d[2])) >= 5 then return true end
    end
    return false
end

local function score(n, open)
    if n >= 5 then return 100000 end
    if open == 0 then return 0 end
    if n == 4 then return open == 2 and 10000 or 1000 end
    if n == 3 then return open == 2 and 1000 or 100 end
    if n == 2 then return open == 2 and 100 or 10 end
    return open == 2 and 10 or 1
end

local function cellScore(board, r, c, who)
    local total = 0
    for _, d in ipairs(DIRS) do total = total + score(line(board, r, c, who, d[1], d[2])) end
    return total
end

local function hasNeighbor(board, r, c)
    for dr = -2, 2 do for dc = -2, 2 do
        local v = at(board, r + dr, c + dc)
        if v and v ~= EMPTY then return true end
    end end
    return false
end

--- 选 AI 的落点：自己进攻分 + 堵对手分；开局走天元。返回 r, c。
function Core.aiMove(s, rng)
    if #s.moves == 0 then return 8, 8 end
    local best, br, bc = -1, nil, nil
    for r = 1, N do
        for c = 1, N do
            if at(s.board, r, c) == EMPTY and hasNeighbor(s.board, r, c) then
                local v = cellScore(s.board, r, c, AI) * 1.1 + cellScore(s.board, r, c, HUMAN) + rng:float()
                if v > best then best, br, bc = v, r, c end
            end
        end
    end
    return br, bc
end

function Core.place(s, r, c, who)
    local idx = (r - 1) * N + c
    if s.winner or s.board[idx] ~= EMPTY then return false end
    s.board[idx] = who
    s.moves[#s.moves + 1] = idx
    if Core.wins(s.board, r, c, who) then s.winner = who
    elseif #s.moves == N * N then s.winner = 0 end
    return true
end

function Core.undo(s)
    -- 悔一回合：对手和自己各一步；对手没来得及走（玩家刚赢）则只撤一步
    local n = (s.winner == HUMAN or #s.moves % 2 == 1) and 1 or 2
    for _ = 1, n do
        local idx = table.remove(s.moves)
        if idx then s.board[idx] = EMPTY end
    end
    s.winner = nil
end

local M = { id = "gomoku", title = T("五子棋"), icon = "radio_button_unchecked", tier = "A", desc = T("人机对弈"), core = Core }

function M.new(ctx)
    local self = {}
    local s

    local function persist() ctx:save({ state = s }) end

    local function tap(r, c)
        if s.winner then return end
        if not Core.place(s, r, c, HUMAN) then return end
        if not s.winner then
            local ar, ac = Core.aiMove(s, ctx.rng)
            if ar then Core.place(s, ar, ac, AI) end
        end
        if s.winner == HUMAN then
            ctx:record("wins", (ctx:best("wins") or 0) + 1)
        end
        persist()
        self.render()
    end

    function self.render()
        local last = s.moves[#s.moves]
        local status = T("你执黑")
        if s.winner == HUMAN then status = T("你赢了！")
        elseif s.winner == AI then status = T("对手获胜")
        elseif s.winner == 0 then status = T("平局") end
        status = status .. (T("    第 %d 手    累计获胜 %d 局")):format(#s.moves, ctx:best("wins") or 0)
        ctx:render({
            title = T("五子棋"),
            status = status,
            grid = {
                rows = N, cols = N, on_tap = tap,
                cell = function(r, c)
                    local idx = (r - 1) * N + c
                    local v = s.board[idx]
                    local cell = {}
                    if idx == last then cell.fill = "grey" end
                    if v == HUMAN then cell.shape = "black" elseif v == AI then cell.shape = "white" end
                    return cell
                end,
            },
            buttons = {
                {
                    { text = T("悔棋"), enabled = #s.moves > 0, callback = function() Core.undo(s) persist() self.render() end },
                    { text = T("新局"), callback = function() s = Core.fresh() persist() self.render() end },
                    { text = T("返回"), callback = function() ctx:exit() end },
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
