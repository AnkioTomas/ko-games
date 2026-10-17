--[[--
中国象棋（9×10，落在交叉点上）。玩家执红在下方先行，对手是 alpha-beta 搜索 AI（迭代加深 + 吃子静态搜索，限时），可悔棋。
棋盘下标 (r-1)*9+c，r=1 是黑方底线，r=10 是红方底线。棋子：红为正、黑为负，绝对值 1帅 2仕 3相 4马 5车 6炮 7兵。
着法编码 from*128+to。合法着法 = 伪合法着法且走后己方不被将军（含将帅对面）。
state = { board, turn, over, winner, history, level, last, quiet }。
--]]
local T = require("kogames.l10n")
local ROWS, COLS, N = 10, 9, 90
local RED, BLACK = 1, -1
local HUMAN, AI = RED, BLACK
local MAX_HISTORY = 30
local NO_CAPTURE_DRAW = 120

local K, A, E, H, R, C, P = 1, 2, 3, 4, 5, 6, 7
local VALUE = { [K] = 0, [A] = 20, [E] = 20, [H] = 40, [R] = 90, [C] = 45, [P] = 10 }
local MATE = 100000
local abs, floor = math.abs, math.floor

local Core = {}
Core.RED, Core.BLACK, Core.HUMAN, Core.AI = RED, BLACK, HUMAN, AI
Core.LEVELS = { { name = T("简单"), depth = 1, time = 0.3, noise = 14 }, { name = T("普通"), depth = 4, time = 0.8, noise = 0 } }

local function rc(i) return floor((i - 1) / COLS) + 1, (i - 1) % COLS + 1 end
local function idx(r, c) return (r - 1) * COLS + c end

local function newBoard()
    local b = {}
    for i = 1, N do b[i] = 0 end
    local back = { R, H, E, A, K, A, E, H, R }
    for c = 1, COLS do
        b[idx(1, c)] = -back[c]
        b[idx(10, c)] = back[c]
    end
    b[idx(3, 2)], b[idx(3, 8)] = -C, -C
    b[idx(8, 2)], b[idx(8, 8)] = C, C
    for c = 1, COLS, 2 do
        b[idx(4, c)] = -P
        b[idx(7, c)] = P
    end
    return b
end

function Core.fresh(level)
    return { board = newBoard(), turn = RED, over = false, winner = nil, history = {}, level = level or 1, last = nil, quiet = 0 }
end

local function inPalace(side, r, c)
    return c >= 4 and c <= 6 and ((side == RED and r >= 8) or (side == BLACK and r <= 3))
end

local HORSE = {
    { -2, -1, -1, 0 }, { -2, 1, -1, 0 }, { 2, -1, 1, 0 }, { 2, 1, 1, 0 },
    { -1, -2, 0, -1 }, { 1, -2, 0, -1 }, { -1, 2, 0, 1 }, { 1, 2, 0, 1 },
}
local ORTHO = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
local DIAG = { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }

--- side 一方的伪合法着法（不检查自己是否被将军；将帅对面按「帅可吃将」生成）
local function gen(b, side, out, onlyCaps)
    out = out or {}
    local n = #out
    for i = 1, N do
        local p = b[i]
        if p * side > 0 then
            local t = abs(p)
            local r, c = rc(i)
            local from = i * 128
            local function try(rr, cc)
                if rr < 1 or rr > ROWS or cc < 1 or cc > COLS then return end
                local to = idx(rr, cc)
                local q = b[to]
                if q * side > 0 then return end
                if onlyCaps and q == 0 then return end
                n = n + 1
                out[n] = from + to
            end
            if t == K then
                for _, d in ipairs(ORTHO) do
                    if inPalace(side, r + d[1], c + d[2]) then try(r + d[1], c + d[2]) end
                end
                local rr = r + side * -1
                while rr >= 1 and rr <= ROWS do
                    local q = b[idx(rr, c)]
                    if q ~= 0 then
                        if q == -side * K then n = n + 1 out[n] = from + idx(rr, c) end
                        break
                    end
                    rr = rr - side
                end
            elseif t == A then
                for _, d in ipairs(DIAG) do
                    if inPalace(side, r + d[1], c + d[2]) then try(r + d[1], c + d[2]) end
                end
            elseif t == E then
                for _, d in ipairs(DIAG) do
                    local rr, cc = r + d[1] * 2, c + d[2] * 2
                    local home = side == RED and rr >= 6 or side == BLACK and rr <= 5
                    if home and rr >= 1 and rr <= ROWS and cc >= 1 and cc <= COLS and b[idx(r + d[1], c + d[2])] == 0 then try(rr, cc) end
                end
            elseif t == H then
                for _, d in ipairs(HORSE) do
                    local lr, lc = r + d[3], c + d[4]
                    if b[idx(lr, lc)] == 0 then try(r + d[1], c + d[2]) end
                end
            elseif t == R then
                for _, d in ipairs(ORTHO) do
                    local rr, cc = r + d[1], c + d[2]
                    while rr >= 1 and rr <= ROWS and cc >= 1 and cc <= COLS do
                        local q = b[idx(rr, cc)]
                        if q == 0 then
                            if not onlyCaps then n = n + 1 out[n] = from + idx(rr, cc) end
                        else
                            if q * side < 0 then n = n + 1 out[n] = from + idx(rr, cc) end
                            break
                        end
                        rr, cc = rr + d[1], cc + d[2]
                    end
                end
            elseif t == C then
                for _, d in ipairs(ORTHO) do
                    local rr, cc = r + d[1], c + d[2]
                    local screen = false
                    while rr >= 1 and rr <= ROWS and cc >= 1 and cc <= COLS do
                        local q = b[idx(rr, cc)]
                        if not screen then
                            if q == 0 then
                                if not onlyCaps then n = n + 1 out[n] = from + idx(rr, cc) end
                            else
                                screen = true
                            end
                        elseif q ~= 0 then
                            if q * side < 0 then n = n + 1 out[n] = from + idx(rr, cc) end
                            break
                        end
                        rr, cc = rr + d[1], cc + d[2]
                    end
                end
            else -- P
                try(r - side, c)
                local crossed = side == RED and r <= 5 or side == BLACK and r >= 6
                if crossed then try(r, c - 1) try(r, c + 1) end
            end
        end
    end
    return out
end

local function make(b, mv)
    local from, to = floor(mv / 128), mv % 128
    local cap = b[to]
    b[to], b[from] = b[from], 0
    return cap
end

local function unmake(b, mv, cap)
    local from, to = floor(mv / 128), mv % 128
    b[from], b[to] = b[to], cap
end

--- side 的将/帅是否被攻击
function Core.inCheck(b, side)
    local ks
    for i = 1, N do if b[i] == side * K then ks = i break end end
    if not ks then return true end
    local mvs = gen(b, -side)
    for _, mv in ipairs(mvs) do
        if mv % 128 == ks then return true end
    end
    return false
end

--- side 的全部合法着法
function Core.legalMoves(b, side)
    local out = {}
    for _, mv in ipairs(gen(b, side)) do
        local cap = make(b, mv)
        if not Core.inCheck(b, side) then out[#out + 1] = mv end
        unmake(b, mv, cap)
    end
    return out
end

--- 某个棋子（下标 from）的合法落点集合 { [to]=true }
function Core.destinations(b, from)
    local p = b[from]
    local set = {}
    if p == 0 then return set end
    for _, mv in ipairs(Core.legalMoves(b, p > 0 and RED or BLACK)) do
        if floor(mv / 128) == from then set[mv % 128] = true end
    end
    return set
end

local function finish(s)
    if s.over then return end
    if #Core.legalMoves(s.board, s.turn) == 0 then
        s.over, s.winner = true, -s.turn -- 无着可走（被将死或困毙）判负
    elseif s.quiet >= NO_CAPTURE_DRAW then
        s.over, s.winner = true, 0
    end
end

--- 当前行棋方走 from→to；非法返回 false
function Core.play(s, from, to)
    if s.over then return false end
    local p = s.board[from]
    if not p or p * s.turn <= 0 then return false end
    local mv = from * 128 + to
    local ok = false
    for _, m in ipairs(Core.legalMoves(s.board, s.turn)) do
        if m == mv then ok = true break end
    end
    if not ok then return false end
    local cap = make(s.board, mv)
    s.quiet = cap ~= 0 and 0 or s.quiet + 1
    s.last = { from, to }
    s.turn = -s.turn
    finish(s)
    return true
end

local function evaluate(b) -- 红方视角
    local sc = 0
    for i = 1, N do
        local p = b[i]
        if p ~= 0 then
            local t, sg = abs(p), p > 0 and 1 or -1
            local r, c = rc(i)
            local v = VALUE[t] * 10
            local cen = 4 - abs(c - 5)
            if t == P then
                local adv = sg == RED and (10 - r) or r - 1
                if adv >= 5 then v = v + 60 + (adv - 5) * 10 end
            elseif t == H or t == C or t == R then
                v = v + cen * 3
            end
            sc = sc + sg * v
        end
    end
    return sc
end

local ctl

local function order(b, moves)
    local keyed = {}
    for i, mv in ipairs(moves) do
        local cap = abs(b[mv % 128])
        local mover = abs(b[floor(mv / 128)])
        keyed[i] = { mv, cap ~= 0 and (cap == K and 10000 or VALUE[cap] * 10 - mover) or -1000 }
    end
    table.sort(keyed, function(x, y) return x[2] > y[2] end)
    for i, k in ipairs(keyed) do moves[i] = k[1] end
    return moves
end

local function quiesce(b, side, alpha, beta, qd)
    local stand = side * evaluate(b)
    if qd == 0 or stand >= beta then return stand end
    if stand > alpha then alpha = stand end
    for _, mv in ipairs(order(b, gen(b, side, nil, true))) do
        local cap = make(b, mv)
        local v
        if abs(cap) == K then v = MATE else v = -quiesce(b, -side, -beta, -alpha, qd - 1) end
        unmake(b, mv, cap)
        if v > alpha then alpha = v end
        if alpha >= beta then break end
    end
    return alpha
end

local function search(b, side, depth, alpha, beta)
    ctl.nodes = ctl.nodes + 1
    if ctl.nodes % 128 == 0 and os.clock() > ctl.deadline then ctl.abort = true end
    if ctl.abort then return 0 end
    if depth == 0 then return quiesce(b, side, alpha, beta, 4) end
    local best = -MATE
    for _, mv in ipairs(order(b, gen(b, side))) do
        local cap = make(b, mv)
        local v
        if abs(cap) == K then v = MATE + depth else v = -search(b, -side, depth - 1, -beta, -alpha) end
        unmake(b, mv, cap)
        if ctl.abort then return 0 end
        if v > best then best = v end
        if v > alpha then alpha = v end
        if alpha >= beta then break end
    end
    return best
end

--- AI（黑）选着；返回 from, to；无着可走返回 nil。level 为 Core.LEVELS 下标，rng 提供 :int(n)
function Core.aiMove(s, level, rng)
    local lv = Core.LEVELS[level or s.level or 1]
    local b = {}
    for i = 1, N do b[i] = s.board[i] end
    local root = Core.legalMoves(b, s.turn)
    if #root == 0 then return nil end
    local side = s.turn
    local best = root[1]
    local scores = {}
    ctl = { nodes = 0, deadline = os.clock() + lv.time, abort = false }
    order(b, root)
    for depth = 1, lv.depth do
        local alpha, bi, cur = -MATE - 100, nil, {}
        for _, mv in ipairs(root) do
            local cap = make(b, mv)
            local v = -search(b, -side, depth - 1, -MATE - 100, lv.noise > 0 and MATE + 100 or -alpha)
            unmake(b, mv, cap)
            if ctl.abort then break end
            if lv.noise > 0 and rng then v = v + rng:int(lv.noise + 1) - 1 end
            cur[mv] = v
            if v > alpha then alpha, bi = v, mv end
        end
        if ctl.abort then break end
        best, scores = bi or best, cur
        table.sort(root, function(x, y) return (cur[x] or -MATE) > (cur[y] or -MATE) end)
        if alpha >= MATE - 10 then break end
    end
    return floor(best / 128), best % 128
end

--- 玩家（红）走一步，随后 AI 应一步；返回是否成功
function Core.humanMove(s, from, to, rng)
    if s.turn ~= HUMAN or s.over then return false end
    local snap = { board = {}, turn = s.turn, last = s.last, quiet = s.quiet }
    for i = 1, N do snap.board[i] = s.board[i] end
    if not Core.play(s, from, to) then return false end
    s.history[#s.history + 1] = snap
    if #s.history > MAX_HISTORY then table.remove(s.history, 1) end
    if not s.over and s.turn == AI then
        local f, t = Core.aiMove(s, s.level, rng)
        if f then Core.play(s, f, t) end
    end
    return true
end

function Core.undo(s)
    local snap = table.remove(s.history)
    if not snap then return false end
    s.board, s.turn, s.last, s.quiet = snap.board, snap.turn, snap.last, snap.quiet
    s.over, s.winner = false, nil
    return true
end

local RED_CH = { [K] = "帅", [A] = "仕", [E] = "相", [H] = "马", [R] = "车", [C] = "炮", [P] = "兵" }
local BLACK_CH = { [K] = "将", [A] = "士", [E] = "象", [H] = "马", [R] = "车", [C] = "炮", [P] = "卒" }

local M = { id = "xiangqi", title = T("中国象棋"), icon = "radio_button_unchecked", tier = "B", desc = T("人机对弈"),
    help = T("你执红棋在下方先行，点按己方棋子，棋盘上的小圆圈提示可走的位置（带圆环的是可以吃掉的对方棋子），再点按目标位置走子。\n走法：帥/將只能在九宫内走一步，不能与对方将帅在同一列中间无子相对；仕/士在九宫内斜走；相/象走田字且不能过河、不能塞象眼；傌/馬走日，蹩马腿不能走；俥/車直走；炮/砲不吃子时直走，吃子需隔一个子；兵/卒过河前只能前进，过河后可左右。\n被将军时必须应将；把对方将死或无子可走即获胜。双方各 120 步无人吃子判和。下错了可以点「悔棋」。"), core = Core }

function M.new(ctx)
    local self = {}
    local s
    local sel

    local function persist() ctx:save({ state = s }) end

    local function afterMove(wasOver)
        if s.over and not wasOver and s.winner == HUMAN then
            ctx:record("wins", (ctx:best("wins") or 0) + 1)
        end
        persist()
    end

    local function tap(r, c)
        if s.over or s.turn ~= HUMAN then return end
        local i = idx(r, c)
        local p = s.board[i]
        if sel and sel.dest[i] then
            local wasOver = s.over
            Core.humanMove(s, sel.from, i, ctx.rng)
            sel = nil
            afterMove(wasOver)
        elseif p * HUMAN > 0 and not (sel and sel.from == i) then
            sel = { from = i, dest = Core.destinations(s.board, i) }
        else
            sel = nil
        end
        self.render()
    end

    local function statusText()
        local line
        if s.over then
            line = s.winner == HUMAN and T("你赢了！") or s.winner == AI and T("对手获胜") or T("和棋")
        elseif Core.inCheck(s.board, HUMAN) then line = T("你被将军！")
        elseif Core.inCheck(s.board, AI) then line = T("将军！轮到你（红）")
        else line = T("轮到你（红）") end
        return line .. (T("    累计获胜 %d 局")):format(ctx:best("wins") or 0)
    end

    function self.render()
        local lvButtons = {}
        for i, lv in ipairs(Core.LEVELS) do
            lvButtons[#lvButtons + 1] = { text = lv.name, selected = s.level == i, callback = function() s.level = i persist() self.render() end }
        end
        ctx:render({
            title = T("中国象棋"),
            status = statusText(),
            grid = {
                rows = ROWS, cols = COLS, ratio = 1, style = "go", on_tap = tap,
                cell = function(r, c)
                    local i = idx(r, c)
                    local p = s.board[i]
                    local isDest = sel and sel.dest[i]
                    if p == 0 then
                        if isDest then return { icon = "goal", icon_scale = 0.3 } end
                        if s.last and s.last[1] == i then return { mark = "black" } end
                        return {}
                    end
                    local t = abs(p)
                    local selected = sel and sel.from == i
                    local cell = { scale = 0.42 }
                    if p > 0 then
                        cell.text = RED_CH[t]
                        if selected then cell.shape, cell.color = "black", "white" else cell.shape, cell.color = "white", "black" end
                    else
                        cell.text = BLACK_CH[t]
                        cell.shape, cell.color = "black", "white"
                    end
                    if isDest then cell.icon, cell.icon_scale = "goal", 1.0 end
                    return cell
                end,
            },
            buttons = {
                { label = T("难度") },
                lvButtons,
                {
                    { text = T("悔棋"), enabled = #s.history > 0, callback = function() sel = nil Core.undo(s) persist() self.render() end },
                    { text = T("新局"), callback = function() sel = nil s = Core.fresh(s.level) persist() self.render() end },
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
