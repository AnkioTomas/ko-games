--[[--
国际象棋（8×8）。玩家执白先行，对手是 alpha-beta 搜索 AI（子力 + 位置表，迭代加深、限时）；
含王车易位、吃过路兵、升变、将军/将死/逼和、五十步与子力不足和棋，可悔棋。
棋盘下标 (r-1)*8+c，第 1 行是黑方底线；棋子为带符号整数：白正黑负，1兵 2马 3象 4车 5后 6王。
pos = { b, turn(1 白 / -1 黑), wk, wq, bk, bq（易位权）, ep（吃过路兵目标格）, half（半回合计数） }
state = { pos, history, over, result, reason, level, last, pending }
--]]
local T = require("kogames.l10n")
local N = 8
local WHITE, BLACK = 1, -1
local P, Nn, B, R, Q, K = 1, 2, 3, 4, 5, 6
local MAX_HISTORY = 60
local MATE = 100000

local Core = {}

local VALUE = { 100, 320, 330, 500, 900, 0 }

local PST = {
    { 0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5,
      0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0 },
    { -50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30,
      -30, 5, 15, 20, 20, 15, 5, -30, -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30,
      -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50 },
    { -20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10,
      -10, 5, 5, 10, 10, 5, 5, -10, -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10,
      -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20 },
    { 0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5,
      -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0 },
    { -20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10,
      -5, 0, 5, 5, 5, 5, 0, -5, 0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10,
      -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20 },
    { -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30,
      -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30,
      -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10,
      20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20 },
}

local KNIGHT = { { -2, -1 }, { -2, 1 }, { -1, -2 }, { -1, 2 }, { 1, -2 }, { 1, 2 }, { 2, -1 }, { 2, 1 } }
local KING = { { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 0 }, { 1, 1 } }
local DIAG = { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }
local ORTH = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local function abs(x) return x < 0 and -x or x end

function Core.fresh()
    local b = {}
    for i = 1, 64 do b[i] = 0 end
    local back = { R, Nn, B, Q, K, B, Nn, R }
    for c = 1, 8 do
        b[c], b[8 + c] = -back[c], -P
        b[48 + c], b[56 + c] = P, back[c]
    end
    return { b = b, turn = WHITE, wk = true, wq = true, bk = true, bq = true, ep = nil, half = 0 }
end

function Core.newState(level)
    return { pos = Core.fresh(), history = {}, over = false, level = level or 2 }
end

local function copyPos(p)
    local b, ob = {}, p.b
    for i = 1, 64 do b[i] = ob[i] end
    return { b = b, turn = p.turn, wk = p.wk, wq = p.wq, bk = p.bk, bq = p.bq, ep = p.ep, half = p.half }
end

--- sq 是否被 by（1/-1）一方攻击
local function attacked(b, sq, by)
    local r, c = math.floor((sq - 1) / 8) + 1, (sq - 1) % 8 + 1
    local pr = r + by
    if pr >= 1 and pr <= 8 then
        if c > 1 and b[(pr - 1) * 8 + c - 1] == by * P then return true end
        if c < 8 and b[(pr - 1) * 8 + c + 1] == by * P then return true end
    end
    for _, d in ipairs(KNIGHT) do
        local rr, cc = r + d[1], c + d[2]
        if rr >= 1 and rr <= 8 and cc >= 1 and cc <= 8 and b[(rr - 1) * 8 + cc] == by * Nn then return true end
    end
    for _, d in ipairs(KING) do
        local rr, cc = r + d[1], c + d[2]
        if rr >= 1 and rr <= 8 and cc >= 1 and cc <= 8 and b[(rr - 1) * 8 + cc] == by * K then return true end
    end
    for k = 1, 2 do
        local dirs, a1, a2 = k == 1 and DIAG or ORTH, by * B, by * R
        for _, d in ipairs(dirs) do
            local rr, cc = r + d[1], c + d[2]
            while rr >= 1 and rr <= 8 and cc >= 1 and cc <= 8 do
                local v = b[(rr - 1) * 8 + cc]
                if v ~= 0 then
                    if v == by * Q or v == (k == 1 and a1 or a2) then return true end
                    break
                end
                rr, cc = rr + d[1], cc + d[2]
            end
        end
    end
    return false
end

local function kingSq(b, who)
    local k = who * K
    for i = 1, 64 do if b[i] == k then return i end end
end

function Core.inCheck(pos, who)
    who = who or pos.turn
    local k = kingSq(pos.b, who)
    return k ~= nil and attacked(pos.b, k, -who)
end

--- 伪合法着法 { f, t, p = 升变子型, fl = "ep"|"cs" }
local function gen(pos, capsOnly)
    local b, t, out = pos.b, pos.turn, {}
    local function add(f, to, p, fl) out[#out + 1] = { f = f, t = to, p = p, fl = fl } end
    for r = 1, 8 do
        for c = 1, 8 do
            local i = (r - 1) * 8 + c
            local v = b[i]
            if v ~= 0 and v * t > 0 then
                local a = abs(v)
                if a == P then
                    local r2 = r - t
                    local last = (r2 == 1 or r2 == 8)
                    if r2 >= 1 and r2 <= 8 then
                        local to = (r2 - 1) * 8 + c
                        if b[to] == 0 and (not capsOnly or last) then
                            if last then
                                for _, pt in ipairs({ Q, R, B, Nn }) do add(i, to, pt) end
                            else
                                add(i, to)
                                local start = (t == WHITE and r == 7) or (t == BLACK and r == 2)
                                if start and b[to - 8 * t] == 0 and not capsOnly then add(i, to - 8 * t) end
                            end
                        end
                        for dc = -1, 1, 2 do
                            local cc = c + dc
                            if cc >= 1 and cc <= 8 then
                                local tt = (r2 - 1) * 8 + cc
                                if b[tt] * t < 0 then
                                    if last then
                                        for _, pt in ipairs({ Q, R, B, Nn }) do add(i, tt, pt) end
                                    else
                                        add(i, tt)
                                    end
                                elseif pos.ep == tt then
                                    add(i, tt, nil, "ep")
                                end
                            end
                        end
                    end
                elseif a == Nn or a == K then
                    for _, d in ipairs(a == Nn and KNIGHT or KING) do
                        local rr, cc = r + d[1], c + d[2]
                        if rr >= 1 and rr <= 8 and cc >= 1 and cc <= 8 then
                            local tt = (rr - 1) * 8 + cc
                            local o = b[tt]
                            if o * t <= 0 and (not capsOnly or o ~= 0) then add(i, tt) end
                        end
                    end
                else
                    for k = 1, 2 do
                        if (k == 1 and a ~= R) or (k == 2 and a ~= B) then
                            for _, d in ipairs(k == 1 and DIAG or ORTH) do
                                local rr, cc = r + d[1], c + d[2]
                                while rr >= 1 and rr <= 8 and cc >= 1 and cc <= 8 do
                                    local tt = (rr - 1) * 8 + cc
                                    local o = b[tt]
                                    if o * t > 0 then break end
                                    if o ~= 0 or not capsOnly then add(i, tt) end
                                    if o ~= 0 then break end
                                    rr, cc = rr + d[1], cc + d[2]
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not capsOnly then
        local home = t == WHITE and 61 or 5
        if b[home] == t * K and not attacked(b, home, -t) then
            local ks, qs = t == WHITE and pos.wk or pos.bk, t == WHITE and pos.wq or pos.bq
            if ks and b[home + 3] == t * R and b[home + 1] == 0 and b[home + 2] == 0
                and not attacked(b, home + 1, -t) and not attacked(b, home + 2, -t) then
                add(home, home + 2, nil, "cs")
            end
            if qs and b[home - 4] == t * R and b[home - 1] == 0 and b[home - 2] == 0 and b[home - 3] == 0
                and not attacked(b, home - 1, -t) and not attacked(b, home - 2, -t) then
                add(home, home - 2, nil, "cs")
            end
        end
    end
    return out
end

--- 走一步，返回新局面（不修改原局面）
function Core.make(pos, m)
    local np = copyPos(pos)
    local b, t = np.b, pos.turn
    local piece = b[m.f]
    local cap = b[m.t]
    b[m.t], b[m.f] = piece, 0
    if m.fl == "ep" then
        b[m.t + 8 * t] = 0
        cap = P
    elseif m.fl == "cs" then
        if m.t > m.f then b[m.f + 1], b[m.f + 3] = b[m.f + 3], 0 else b[m.f - 1], b[m.f - 4] = b[m.f - 4], 0 end
    end
    if m.p then b[m.t] = t * m.p end
    if abs(piece) == K then
        if t == WHITE then np.wk, np.wq = false, false else np.bk, np.bq = false, false end
    end
    if m.f == 64 or m.t == 64 then np.wk = false end
    if m.f == 57 or m.t == 57 then np.wq = false end
    if m.f == 8 or m.t == 8 then np.bk = false end
    if m.f == 1 or m.t == 1 then np.bq = false end
    np.ep = (abs(piece) == P and abs(m.t - m.f) == 16) and (m.f + m.t) / 2 or nil
    np.half = (abs(piece) == P or cap ~= 0) and 0 or pos.half + 1
    np.turn = -t
    return np
end

local function legalMoves(pos)
    local out, t = {}, pos.turn
    for _, m in ipairs(gen(pos)) do
        local np = Core.make(pos, m)
        local k = kingSq(np.b, t)
        if k and not attacked(np.b, k, -t) then out[#out + 1] = m end
    end
    return out
end
Core.legalMoves = legalMoves

--- 从 f 出发的合法着法（升变会有 4 条）
function Core.movesFrom(pos, f)
    local out = {}
    for _, m in ipairs(legalMoves(pos)) do if m.f == f then out[#out + 1] = m end end
    return out
end

local function insufficient(b)
    local minors = 0
    for i = 1, 64 do
        local a = abs(b[i])
        if a == P or a == R or a == Q then return false end
        if a == Nn or a == B then minors = minors + 1 end
    end
    return minors <= 1
end

--- 判定终局：返回 nil 或 result("win"/"loss"/"draw"), reason("mate"/"stalemate"/"fifty"/"material")
function Core.status(pos)
    if #legalMoves(pos) == 0 then
        if Core.inCheck(pos) then
            return pos.turn == WHITE and "loss" or "win", "mate"
        end
        return "draw", "stalemate"
    end
    if pos.half >= 100 then return "draw", "fifty" end
    if insufficient(pos.b) then return "draw", "material" end
end

local function evaluate(pos)
    local b, s = pos.b, 0
    for i = 1, 64 do
        local v = b[i]
        if v ~= 0 then
            local a = abs(v)
            if v > 0 then
                s = s + VALUE[a] + PST[a][i]
            else
                local r, c = math.floor((i - 1) / 8), (i - 1) % 8
                s = s - VALUE[a] - PST[a][(7 - r) * 8 + c + 1]
            end
        end
    end
    return s * pos.turn
end

local function ordered(pos, moves)
    local b = pos.b
    for _, m in ipairs(moves) do
        local sc = 0
        local victim = b[m.t]
        if m.fl == "ep" then victim = P end
        if victim ~= 0 then sc = 1000 + 10 * abs(victim) - abs(b[m.f]) end
        if m.p then sc = sc + 800 + m.p end
        m.o = sc
    end
    table.sort(moves, function(x, y) return x.o > y.o end)
    return moves
end

local deadline, aborted, nodes

local function quiesce(pos, alpha, beta, qd)
    nodes = nodes + 1
    if nodes % 256 == 0 and os.clock() > deadline then aborted = true end
    local stand = evaluate(pos)
    if aborted or qd <= 0 then return stand end
    if stand >= beta then return stand end
    if stand > alpha then alpha = stand end
    local t = pos.turn
    for _, m in ipairs(ordered(pos, gen(pos, true))) do
        local np = Core.make(pos, m)
        local k = kingSq(np.b, t)
        if k and not attacked(np.b, k, -t) then
            local v = -quiesce(np, -beta, -alpha, qd - 1)
            if aborted then return 0 end
            if v >= beta then return v end
            if v > alpha then alpha = v end
        end
    end
    return alpha
end

local function search(pos, depth, alpha, beta, ply)
    nodes = nodes + 1
    if nodes % 256 == 0 and os.clock() > deadline then aborted = true end
    if aborted then return 0 end
    if depth <= 0 then return quiesce(pos, alpha, beta, 4) end
    local t = pos.turn
    local best, any = -math.huge, false
    for _, m in ipairs(ordered(pos, gen(pos))) do
        local np = Core.make(pos, m)
        local k = kingSq(np.b, t)
        if k and not attacked(np.b, k, -t) then
            any = true
            local v = -search(np, depth - 1, -beta, -alpha, ply + 1)
            if aborted then return 0 end
            if v > best then best = v end
            if v > alpha then alpha = v end
            if alpha >= beta then break end
        end
    end
    if not any then
        if Core.inCheck(pos) then return -MATE + ply end
        return 0
    end
    return best
end

--- AI（当前行棋方）选着：level 1 简单（浅搜 + 随机扰动），2 普通（迭代加深到 3 层，限时）
function Core.aiMove(pos, level, rng, seconds)
    local moves = legalMoves(pos)
    if #moves == 0 then return nil end
    level = level or 2
    local maxDepth = level == 1 and 1 or 3
    local noise = level == 1 and 60 or 0
    deadline = os.clock() + (seconds or 0.8)
    aborted, nodes = false, 0
    ordered(pos, moves)
    local best = moves[1]
    for depth = 1, maxDepth do
        local scored, alpha, top = {}, -math.huge, nil
        local done = true
        for _, m in ipairs(moves) do
            local v = -search(Core.make(pos, m), depth - 1, -math.huge, -alpha, 1)
            if aborted then done = false break end
            if noise > 0 and rng then v = v + (rng:float() * 2 - 1) * noise end
            scored[#scored + 1] = { m = m, v = v }
            if v > alpha then alpha, top = v, #scored end
        end
        if not done then break end
        -- 被剪枝的着法只有上界，真正抬高 alpha 的那手才是最佳
        scored[top].v = math.huge
        table.sort(scored, function(x, y) return x.v > y.v end)
        scored[1].v = alpha
        best = scored[1].m
        for i, e in ipairs(scored) do moves[i] = e.m end
        if scored[1].v > MATE / 2 then break end
    end
    return best
end

local function posKey(p)
    return table.concat(p.b, ",") .. (p.turn > 0 and "w" or "b") .. (p.wk and "K" or "") .. (p.wq and "Q" or "")
        .. (p.bk and "k" or "") .. (p.bq and "q" or "") .. (p.ep or "")
end

--- 当前局面（轮到玩家时）在历史中是否已出现三次
local function threefold(s)
    if s.pos.turn ~= WHITE then return false end
    local key, n = posKey(s.pos), 1
    for _, h in ipairs(s.history) do
        if h.pos.turn == WHITE and posKey(h.pos) == key then n = n + 1 end
    end
    return n >= 3
end
Core.threefold = threefold

local function finish(s)
    local res, why = Core.status(s.pos)
    if not res and threefold(s) then res, why = "draw", "repetition" end
    s.over, s.result, s.reason = res ~= nil, res, why
end

local function snapshot(s)
    s.history[#s.history + 1] = { pos = s.pos, last = s.last }
    if #s.history > MAX_HISTORY then table.remove(s.history, 1) end
end

--- 玩家（白）走 m，随后 AI 应一手；不合法返回 false
function Core.humanMove(s, m, rng, seconds)
    if s.over or s.pos.turn ~= WHITE then return false end
    local ok
    for _, lm in ipairs(Core.movesFrom(s.pos, m.f)) do
        if lm.t == m.t and lm.p == m.p then ok = lm break end
    end
    if not ok then return false end
    snapshot(s)
    s.pending = nil
    s.pos = Core.make(s.pos, ok)
    s.last = { f = ok.f, t = ok.t }
    finish(s)
    if not s.over then
        local am = Core.aiMove(s.pos, s.level, rng, seconds)
        if am then
            s.pos = Core.make(s.pos, am)
            s.last = { f = am.f, t = am.t }
            finish(s)
        end
    end
    return true
end

function Core.undo(s)
    s.pending = nil
    local snap = table.remove(s.history)
    if not snap then return false end
    s.pos, s.last = snap.pos, snap.last
    s.over, s.result, s.reason = false, nil, nil
    return true
end

local function name(i) return string.char(96 + (i - 1) % 8 + 1) .. (9 - (math.floor((i - 1) / 8) + 1)) end
Core.squareName = name

local LETTER = { "p", "n", "b", "r", "q", "k" }
local function iconOf(v) return "chess_" .. (v > 0 and "w" or "b") .. LETTER[abs(v)] end
Core.iconOf = iconOf

local M = { id = "chess", title = T("国际象棋"), icon = "extension", tier = "C", desc = T("人机对弈"),
    help = T("你执白先行，点选己方棋子后，棋盘上的小点就是它能走的位置（被吃子的格子会变深）。\n兵走到底线可升变（选后/车/象/马）；支持王车易位与吃过路兵。\n王被将军时必须化解；无法化解即被将死，无棋可走但没被将军则为和棋。\n可在“简单 / 普通”间切换对手强度，并可悔棋。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, sel

    local function persist() ctx:save({ state = s }) end

    local function conclude(wasOver)
        if s.over and not wasOver and s.result == "win" then
            ctx:record("wins", (ctx:best("wins") or 0) + 1)
        end
    end

    local function play(m)
        local wasOver = s.over
        if Core.humanMove(s, m, ctx.rng) then
            sel = nil
            conclude(wasOver)
            persist()
        end
    end

    local function tap(r, c)
        if s.over or s.pending then return end
        local idx = (r - 1) * N + c
        if sel then
            local hits = {}
            for _, m in ipairs(Core.movesFrom(s.pos, sel)) do
                if m.t == idx then hits[#hits + 1] = m end
            end
            if #hits == 1 then
                play(hits[1])
                self.render()
                return
            elseif #hits > 1 then
                s.pending = { f = sel, t = idx }
                persist()
                self.render()
                return
            end
        end
        local v = s.pos.b[idx]
        sel = (v > 0 and idx ~= sel) and idx or nil
        self.render()
    end

    function self.render()
        local pos = s.pos
        local status
        if s.over then
            if s.result == "win" then status = T("将死！你赢了")
            elseif s.result == "loss" then status = T("你被将死了")
            elseif s.reason == "stalemate" then status = T("无棋可走，和棋")
            elseif s.reason == "fifty" then status = T("五十步无进展，和棋")
            elseif s.reason == "repetition" then status = T("三次重复局面，和棋")
            else status = T("子力不足，和棋") end
        elseif s.pending then status = T("选择升变的棋子")
        elseif Core.inCheck(pos, WHITE) then status = T("你被将军了！")
        else status = T("轮到你（白）") end
        if s.last then status = status .. "    " .. (T("上一步 %s-%s")):format(name(s.last.f), name(s.last.t)) end
        status = status .. (T("    累计获胜 %d 局")):format(ctx:best("wins") or 0)

        local dest = {}
        if sel and not s.over then
            for _, m in ipairs(Core.movesFrom(pos, sel)) do dest[m.t] = true end
        end

        local buttons = {}
        if s.pending then
            buttons[#buttons + 1] = { label = T("升变为") }
            local row = {}
            for _, o in ipairs({ { Q, T("后") }, { R, T("车") }, { B, T("象") }, { Nn, T("马") } }) do
                row[#row + 1] = { text = o[2], callback = function()
                    local pd = s.pending
                    play({ f = pd.f, t = pd.t, p = o[1] })
                    self.render()
                end }
            end
            buttons[#buttons + 1] = row
        end
        buttons[#buttons + 1] = {
            { menu = true, text = T("悔棋"), enabled = #s.history > 0, callback = function() Core.undo(s) sel = nil persist() self.render() end },
            { menu = true, text = T("新局"), callback = function() s = Core.newState(s.level) sel = nil persist() self.render() end },
        }
        local levels = {
            { text = T("简单"), selected = s.level == 1, callback = function() s = Core.newState(1) sel = nil persist() self.render() end },
            { text = T("普通"), selected = s.level == 2, callback = function() s = Core.newState(2) sel = nil persist() self.render() end },
        }
        ctx:render({
            title = T("国际象棋"),
            status = status,
            grid = {
                rows = N, cols = N, on_tap = tap,
                cell = function(r, c)
                    local idx = (r - 1) * N + c
                    local v = pos.b[idx]
                    local cell = {}
                    if (r + c) % 2 == 0 then cell.fill = "grey" end
                    if v ~= 0 then
                        cell.icon, cell.icon_scale = iconOf(v), 0.92
                        if dest[idx] or idx == sel then cell.fill = "dark" end
                    elseif dest[idx] then
                        cell.icon, cell.icon_scale = "goal", 0.3
                    end
                    return cell
                end,
            },
            settings = { groups = { { label = T("难度"), options = levels } }, reset = function() s = Core.newState(s.level) sel = nil persist() self.render() end },
            buttons = buttons,
        })
    end

    function self.start()
        local saved = ctx:load()
        s = saved and saved.state or Core.newState()
        self.render()
    end

    self.tap, self.state = tap, function() return s end
    return self
end

return M
