--[[--
黑白棋（8×8）。玩家执黑先行，对手是 alpha-beta 搜索 AI（位置权重 + 行动力）；无子可下自动跳过，可悔棋。
棋盘下标 (r-1)*8+c。state = { board, turn, over, passed, history }。
--]]
local T = require("kogames.l10n")
local N = 8
local EMPTY, HUMAN, AI = 0, 1, 2
local MAX_HISTORY = 40

local Core = {}

local DIRS = { { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 } }

local WEIGHT = {
    100, -20, 10, 5, 5, 10, -20, 100,
    -20, -50, -2, -2, -2, -2, -50, -20,
    10, -2, 1, 1, 1, 1, -2, 10,
    5, -2, 1, 0, 0, 1, -2, 5,
    5, -2, 1, 0, 0, 1, -2, 5,
    10, -2, 1, 1, 1, 1, -2, 10,
    -20, -50, -2, -2, -2, -2, -50, -20,
    100, -20, 10, 5, 5, 10, -20, 100,
}

local function other(who) return who == HUMAN and AI or HUMAN end

local function newBoard()
    local b = {}
    for i = 1, N * N do b[i] = EMPTY end
    b[27], b[36] = AI, AI
    b[28], b[35] = HUMAN, HUMAN
    return b
end

function Core.fresh()
    return { board = newBoard(), turn = HUMAN, over = false, passed = nil, history = {} }
end

--- who 落在 idx 会翻转的棋子下标列表（空格才可能有）
function Core.flips(board, idx, who)
    local out = {}
    if board[idx] ~= EMPTY then return out end
    local r, c = math.floor((idx - 1) / N) + 1, (idx - 1) % N + 1
    local opp = other(who)
    for _, d in ipairs(DIRS) do
        local rr, cc = r + d[1], c + d[2]
        local run = {}
        while rr >= 1 and rr <= N and cc >= 1 and cc <= N and board[(rr - 1) * N + cc] == opp do
            run[#run + 1] = (rr - 1) * N + cc
            rr, cc = rr + d[1], cc + d[2]
        end
        if #run > 0 and rr >= 1 and rr <= N and cc >= 1 and cc <= N and board[(rr - 1) * N + cc] == who then
            for _, i in ipairs(run) do out[#out + 1] = i end
        end
    end
    return out
end

function Core.legalMoves(board, who)
    local out = {}
    for i = 1, N * N do
        if board[i] == EMPTY and #Core.flips(board, i, who) > 0 then out[#out + 1] = i end
    end
    return out
end

function Core.count(board)
    local h, a = 0, 0
    for i = 1, N * N do
        if board[i] == HUMAN then h = h + 1 elseif board[i] == AI then a = a + 1 end
    end
    return h, a
end

local function apply(board, idx, who)
    local f = Core.flips(board, idx, who)
    board[idx] = who
    for _, i in ipairs(f) do board[i] = who end
end

--- 当前行棋方落子；不合法返回 false。之后自动处理跳过与终局。
function Core.play(s, idx)
    if s.over or not idx or s.board[idx] ~= EMPTY then return false end
    if #Core.flips(s.board, idx, s.turn) == 0 then return false end
    apply(s.board, idx, s.turn)
    local nxt = other(s.turn)
    s.passed = nil
    if #Core.legalMoves(s.board, nxt) > 0 then
        s.turn = nxt
    elseif #Core.legalMoves(s.board, s.turn) > 0 then
        s.passed = nxt
    else
        s.over = true
    end
    return true
end

--- 0 平局，HUMAN / AI 胜者；未结束返回 nil
function Core.winner(s)
    if not s.over then return nil end
    local h, a = Core.count(s.board)
    if h > a then return HUMAN elseif a > h then return AI end
    return 0
end

local function evaluate(b)
    local score = 0
    for i = 1, N * N do
        local v = b[i]
        if v == AI then score = score + WEIGHT[i] elseif v == HUMAN then score = score - WEIGHT[i] end
    end
    local ma, mh = #Core.legalMoves(b, AI), #Core.legalMoves(b, HUMAN)
    return score + 6 * (ma - mh)
end

local function search(b, who, depth, alpha, beta)
    local moves = Core.legalMoves(b, who)
    if #moves == 0 then
        local opp = other(who)
        if #Core.legalMoves(b, opp) == 0 then
            local h, a = Core.count(b)
            local d = (a - h) * 1000
            return who == AI and d or -d
        end
        return -search(b, opp, depth, -beta, -alpha)
    end
    if depth == 0 then
        local e = evaluate(b)
        return who == AI and e or -e
    end
    local best = -math.huge
    for _, idx in ipairs(moves) do
        local nb = {}
        for i = 1, N * N do nb[i] = b[i] end
        apply(nb, idx, who)
        local v = -search(nb, other(who), depth - 1, -beta, -alpha)
        if v > best then best = v end
        if v > alpha then alpha = v end
        if alpha >= beta then break end
    end
    return best
end

--- AI 选点（下标）；无子可下返回 nil
function Core.aiMove(s, depth)
    depth = depth or 4
    local moves = Core.legalMoves(s.board, AI)
    local best, bi, alpha = -math.huge, nil, -math.huge
    for _, idx in ipairs(moves) do
        local nb = {}
        for i = 1, N * N do nb[i] = s.board[i] end
        apply(nb, idx, AI)
        local v = -search(nb, HUMAN, depth - 1, -math.huge, -alpha)
        if v > best then best, bi = v, idx end
        if v > alpha then alpha = v end
    end
    return bi
end

--- 玩家落子（idx），随后 AI 连走到轮到玩家或终局
function Core.humanMove(s, idx, depth)
    if s.turn ~= HUMAN or s.over then return false end
    local snap = { board = {}, turn = s.turn }
    for i = 1, N * N do snap.board[i] = s.board[i] end
    if not Core.play(s, idx) then return false end
    s.history[#s.history + 1] = snap
    if #s.history > MAX_HISTORY then table.remove(s.history, 1) end
    while not s.over and s.turn == AI do
        Core.play(s, Core.aiMove(s, depth))
    end
    return true
end

function Core.undo(s)
    local snap = table.remove(s.history)
    if not snap then return false end
    s.board, s.turn, s.over, s.passed = snap.board, snap.turn, false, nil
    return true
end

local M = { id = "reversi", title = T("黑白棋"), icon = "radio_button_unchecked", art = "icon_reversi", tier = "A", desc = T("人机对弈"), core = Core }

function M.new(ctx)
    local self = {}
    local s

    local function persist() ctx:save({ state = s }) end

    local function tap(r, c)
        local wasOver = s.over
        if not Core.humanMove(s, (r - 1) * N + c) then return end
        if s.over and not wasOver and Core.winner(s) == HUMAN then
            ctx:record("wins", (ctx:best("wins") or 0) + 1)
        end
        persist()
        self.render()
    end

    function self.render()
        local h, a = Core.count(s.board)
        local status
        local w = Core.winner(s)
        if w == HUMAN then status = T("你赢了！")
        elseif w == AI then status = T("对手获胜")
        elseif w == 0 then status = T("平局")
        elseif s.passed == AI then status = T("对手无子可下，轮到你")
        else status = T("轮到你（黑）") end
        status = status .. (T("    黑 %d  白 %d    累计获胜 %d 局")):format(h, a, ctx:best("wins") or 0)
        local legal = {}
        if not s.over and s.turn == HUMAN then
            for _, i in ipairs(Core.legalMoves(s.board, HUMAN)) do legal[i] = true end
        end
        ctx:render({
            title = T("黑白棋"),
            status = status,
            grid = {
                rows = N, cols = N, on_tap = tap,
                cell = function(r, c)
                    local idx = (r - 1) * N + c
                    local v = s.board[idx]
                    if v == HUMAN then return { icon = "stone_black", icon_scale = 0.85 } end
                    if v == AI then return { icon = "stone_white", icon_scale = 0.85 } end
                    if legal[idx] then return { icon = "goal", icon_scale = 0.3 } end
                    return {}
                end,
            },
            buttons = {
                {
                    { text = T("悔棋"), enabled = #s.history > 0, callback = function() Core.undo(s) persist() self.render() end },
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
