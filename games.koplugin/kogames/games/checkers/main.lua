--[[--
跳棋（8×8 英式/中国式简化规则）：玩家执黑先行，AI 执白（alpha-beta，限时迭代加深）。
强制吃子、连跳、到底线升王；无子可动者负；80 步（双方各 40）无吃子无兵走动判和。
棋盘下标 (r-1)*8+c，只用深色格 (r+c) 为奇数。棋子：1 玩家兵 2 玩家王 3 AI 兵 4 AI 王。
玩家在下方向上走，AI 在上方向下走。
--]]
local T = require("kogames.l10n")
local N = 8
local HUMAN, AI = 1, 2
local MAX_HISTORY = 60
local DRAW_PLIES = 80
local TIME_LIMIT = 0.45

local Core = {}

local function owner(p) if p == 0 then return nil end return p <= 2 and HUMAN or AI end
local function isKing(p) return p == 2 or p == 4 end
local function other(who) return who == HUMAN and AI or HUMAN end
local function rc(i) return math.floor((i - 1) / N) + 1, (i - 1) % N + 1 end
local function ix(r, c) return (r - 1) * N + c end
local function inb(r, c) return r >= 1 and r <= N and c >= 1 and c <= N end

local function copy(b)
    local n = {}
    for i = 1, #b do n[i] = b[i] end
    return n
end

function Core.fresh()
    local b = {}
    for r = 1, N do
        for c = 1, N do
            local v = 0
            if (r + c) % 2 == 1 then
                if r <= 3 then v = 3 elseif r >= 6 then v = 1 end
            end
            b[ix(r, c)] = v
        end
    end
    return { board = b, turn = HUMAN, over = false, result = nil, noprog = 0, history = {} }
end

local function dirsFor(p)
    if isKing(p) then return { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } end
    if owner(p) == HUMAN then return { { -1, -1 }, { -1, 1 } } end
    return { { 1, -1 }, { 1, 1 } }
end

local function promoRow(who) return who == HUMAN and 1 or N end

-- 从 pos 出发的所有连跳序列；b 会被临时改动并复原
local function jumps(b, pos, piece, who, path, caps, out)
    local r, c = rc(pos)
    local extended = false
    for _, d in ipairs(dirsFor(piece)) do
        local mr, mc, lr, lc = r + d[1], c + d[2], r + 2 * d[1], c + 2 * d[2]
        if inb(lr, lc) then
            local mid = ix(mr, mc)
            local land = ix(lr, lc)
            if owner(b[mid]) == other(who) and b[land] == 0 then
                extended = true
                local taken = b[mid]
                b[mid] = 0
                path[#path + 1] = land
                caps[#caps + 1] = mid
                local crowned = not isKing(piece) and lr == promoRow(who)
                if crowned then
                    out[#out + 1] = { from = path[1], to = land, path = copy(path), caps = copy(caps) }
                else
                    jumps(b, land, piece, who, path, caps, out)
                end
                path[#path], caps[#caps] = nil, nil
                b[mid] = taken
            end
        end
    end
    if not extended and #caps > 0 then
        out[#out + 1] = { from = path[1], to = pos, path = copy(path), caps = copy(caps) }
    end
end

--- who 的全部合法着法（有吃子则只返回吃子）；着法 = { from, to, path, caps }
function Core.moves(board, who)
    local caps, steps = {}, {}
    for i = 1, N * N do
        local p = board[i]
        if owner(p) == who then
            local b = board
            local from = board[i]
            b[i] = 0
            jumps(b, i, from, who, { i }, {}, caps)
            b[i] = from
            if #caps == 0 then
                local r, c = rc(i)
                for _, d in ipairs(dirsFor(p)) do
                    local rr, cc = r + d[1], c + d[2]
                    if inb(rr, cc) and board[ix(rr, cc)] == 0 then
                        steps[#steps + 1] = { from = i, to = ix(rr, cc), path = { i, ix(rr, cc) }, caps = {} }
                    end
                end
            end
        end
    end
    if #caps > 0 then return caps, true end
    return steps, false
end

--- 返回走完后的新棋盘与是否升王
function Core.apply(board, mv)
    local nb = copy(board)
    local p = nb[mv.from]
    nb[mv.from] = 0
    for _, k in ipairs(mv.caps) do nb[k] = 0 end
    local r = rc(mv.to)
    local crowned = false
    if not isKing(p) and r == promoRow(owner(p)) then
        p = p + 1
        crowned = true
    end
    nb[mv.to] = p
    return nb, crowned
end

--- 玩家 from 出发、到 to 的着法（多条时取第一条）
function Core.find(moves, from, to)
    for _, m in ipairs(moves) do
        if m.from == from and m.to == to then return m end
    end
end

local function checkEnd(s)
    if #Core.moves(s.board, s.turn) == 0 then
        s.over, s.result = true, other(s.turn)
    elseif s.noprog >= DRAW_PLIES then
        s.over, s.result = true, 0
    end
end

--- 当前行棋方走一步着法 mv，推进状态
function Core.play(s, mv)
    local p = s.board[mv.from]
    s.noprog = (#mv.caps > 0 or not isKing(p)) and 0 or s.noprog + 1
    s.board = Core.apply(s.board, mv)
    s.last = { from = mv.from, to = mv.to }
    s.turn = other(s.turn)
    checkEnd(s)
end

-- AI ------------------------------------------------------------------------

local function evaluate(b)
    local score = 0
    for i = 1, N * N do
        local p = b[i]
        if p ~= 0 then
            local r, c = rc(i)
            local v
            if isKing(p) then
                v = 170
                local cr = math.abs(r - 4.5) + math.abs(c - 4.5)
                v = v - cr * 2
            else
                v = 100
                local adv = owner(p) == AI and (r - 1) or (N - r)
                v = v + adv * 3
                if c == 1 or c == N then v = v - 3 end
            end
            if owner(p) == AI then score = score + v else score = score - v end
        end
    end
    return score
end

local Timeout = {}

local function search(b, who, depth, alpha, beta, ply, deadline)
    if os.clock() > deadline then error(Timeout) end
    local moves = Core.moves(b, who)
    if #moves == 0 then
        local v = -100000 + ply
        return who == AI and v or -v
    end
    if depth == 0 then
        -- 有吃子时多搜一层避免水平线效应
        if #moves > 0 and moves[1].caps[1] and ply < 14 then depth = 1 else return evaluate(b) end
    end
    local maximizing = who == AI
    local best = maximizing and -math.huge or math.huge
    for _, mv in ipairs(moves) do
        local v = search(Core.apply(b, mv), other(who), depth - 1, alpha, beta, ply + 1, deadline)
        if maximizing then
            if v > best then best = v end
            if v > alpha then alpha = v end
        else
            if v < best then best = v end
            if v < beta then beta = v end
        end
        if alpha >= beta then break end
    end
    return best
end

--- AI 选着：迭代加深，限时；返回着法或 nil（无着可走）
function Core.aiMove(s, limit, maxDepth)
    local moves = Core.moves(s.board, AI)
    if #moves == 0 then return nil end
    if #moves == 1 then return moves[1] end
    local deadline = os.clock() + (limit or TIME_LIMIT)
    local best = moves[1]
    for depth = 1, maxDepth or 10 do
        local ok, res = pcall(function()
            local bm, bv, alpha = nil, -math.huge, -math.huge
            -- 上一层最佳着法先搜，剪枝更有效
            table.sort(moves, function(a, b2) return a == best and b2 ~= best end)
            for _, mv in ipairs(moves) do
                local v = search(Core.apply(s.board, mv), HUMAN, depth - 1, alpha, math.huge, 1, deadline)
                if v > bv then bv, bm = v, mv end
                if v > alpha then alpha = v end
            end
            return bm
        end)
        if not ok then
            if res ~= Timeout then error(res, 0) end
            break
        end
        best = res
    end
    return best
end

local function snapshot(s)
    return { board = copy(s.board), turn = s.turn, noprog = s.noprog, last = s.last }
end

--- 玩家走 mv，之后 AI 应对
function Core.humanMove(s, mv, limit)
    if s.over or s.turn ~= HUMAN then return false end
    s.history[#s.history + 1] = snapshot(s)
    if #s.history > MAX_HISTORY then table.remove(s.history, 1) end
    Core.play(s, mv)
    if not s.over and s.turn == AI then
        local am = Core.aiMove(s, limit)
        if am then Core.play(s, am) end
    end
    return true
end

function Core.undo(s)
    local snap = table.remove(s.history)
    if not snap then return false end
    s.board, s.turn, s.noprog, s.last = snap.board, snap.turn, snap.noprog, snap.last
    s.over, s.result = false, nil
    return true
end

function Core.counts(board)
    local h, a = 0, 0
    for i = 1, N * N do
        local o = owner(board[i])
        if o == HUMAN then h = h + 1 elseif o == AI then a = a + 1 end
    end
    return h, a
end

local ICON = { "ck_man_b", "ck_king_b", "ck_man_w", "ck_king_w" }

local M = { id = "checkers", title = T("跳棋"), icon = "radio_button_unchecked", tier = "A", desc = T("人机对弈"), help = T("八路跳棋：你执黑棋在下方，先行。棋子只能沿深色格斜着走一步；走到最上面一行升为「王」，王可以前后斜走。\n如果能跳过对方的棋子（落点为空格）就必须跳，被跳过的棋子被吃掉，能连跳就要连跳。\n点一枚棋子，圆点提示它能去的地方，再点圆点走棋。吃光对方或让对方无路可走即获胜。"), core = Core }

function M.new(ctx)
    local self = {}
    local s
    local sel
    local note

    local function persist() ctx:save({ state = s }) end

    local function tap(r, c)
        if s.over or s.turn ~= HUMAN then return end
        local idx = ix(r, c)
        local moves, forced = Core.moves(s.board, HUMAN)
        if sel then
            local mv = Core.find(moves, sel, idx)
            if mv then
                sel, note = nil, nil
                Core.humanMove(s, mv)
                if s.over and s.result == HUMAN then ctx:record("wins", (ctx:best("wins") or 0) + 1) end
                persist()
                self.render()
                return
            end
        end
        sel, note = nil, nil
        if owner(s.board[idx]) == HUMAN then
            local has = false
            for _, m in ipairs(moves) do if m.from == idx then has = true break end end
            if has then sel = idx
            elseif forced then note = T("有棋子可以吃子，必须先吃") end
        end
        self.render()
    end

    function self.render()
        local h, a = Core.counts(s.board)
        local status
        if s.over then
            status = s.result == HUMAN and T("你赢了！") or (s.result == AI and T("对手获胜") or T("和棋"))
        elseif note then
            status = note
        else
            local _, forced = Core.moves(s.board, HUMAN)
            status = forced and T("轮到你（黑），必须吃子") or T("轮到你（黑）")
        end
        status = status .. (T("    黑 %d  白 %d    累计获胜 %d 局")):format(h, a, ctx:best("wins") or 0)
        local dest = {}
        if sel then
            for _, m in ipairs(Core.moves(s.board, HUMAN)) do
                if m.from == sel then dest[m.to] = true end
            end
        end
        ctx:render({
            title = T("跳棋"),
            status = status,
            grid = {
                rows = N, cols = N, on_tap = tap,
                cell = function(r, c)
                    if (r + c) % 2 == 0 then return {} end
                    local idx = ix(r, c)
                    local p = s.board[idx]
                    local cell = { fill = "dark" }
                    if p ~= 0 then
                        cell.icon, cell.icon_scale = ICON[p], 0.82
                        if sel == idx then cell.fill = "raised" end
                    elseif dest[idx] then
                        cell.icon, cell.icon_scale = "goal", 0.3
                    elseif s.last and (s.last.from == idx) then
                        cell.fill = "grey"
                    end
                    return cell
                end,
            },
            buttons = {
                {
                    { text = T("悔棋"), enabled = #s.history > 0, callback = function() Core.undo(s) sel, note = nil, nil persist() self.render() end },
                    { text = T("新局"), callback = function() s = Core.fresh() sel, note = nil, nil persist() self.render() end },
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
