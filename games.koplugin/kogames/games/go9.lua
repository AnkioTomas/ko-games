--[[--
九路围棋：玩家执黑先行，启发式 AI 执白。提子、打劫（简单劫）、禁自杀、虚着；双方连续虚着终局，
按数子法（中国规则）计分，白贴 7.5 目。棋盘下标 (r-1)*9+c。
state = { board, turn, prev, passes, over, history, last }
--]]
local T = require("kogames.l10n")
local N = 9
local EMPTY, HUMAN, AI = 0, 1, 2
local KOMI = 7.5
local MAX_HISTORY = 60

local Core = {}

local NEI = {}
for r = 1, N do
    for c = 1, N do
        local l = {}
        if r > 1 then l[#l + 1] = (r - 2) * N + c end
        if r < N then l[#l + 1] = r * N + c end
        if c > 1 then l[#l + 1] = (r - 1) * N + c - 1 end
        if c < N then l[#l + 1] = (r - 1) * N + c + 1 end
        NEI[(r - 1) * N + c] = l
    end
end

local function other(who) return who == HUMAN and AI or HUMAN end

local function key(board) return table.concat(board) end

local function copy(b)
    local n = {}
    for i = 1, N * N do n[i] = b[i] end
    return n
end

--- idx 处棋串：返回 { 棋子下标列表, 气数 }
local function group(board, idx)
    local who = board[idx]
    local seen, stack, list, libs, nlib = { [idx] = true }, { idx }, {}, {}, 0
    while #stack > 0 do
        local i = table.remove(stack)
        list[#list + 1] = i
        for _, j in ipairs(NEI[i]) do
            local v = board[j]
            if v == EMPTY then
                if not libs[j] then libs[j] = true nlib = nlib + 1 end
            elseif v == who and not seen[j] then
                seen[j] = true
                stack[#stack + 1] = j
            end
        end
    end
    return list, nlib
end
Core.group = group

--- 试着落子：返回新棋盘与提子数；非法返回 nil, 原因（"occupied" | "suicide" | "ko"）
function Core.place(board, idx, who, prev)
    if not idx or board[idx] ~= EMPTY then return nil, "occupied" end
    local nb = copy(board)
    nb[idx] = who
    local opp, captured = other(who), 0
    for _, j in ipairs(NEI[idx]) do
        if nb[j] == opp then
            local g, libs = group(nb, j)
            if libs == 0 then
                for _, k in ipairs(g) do nb[k] = EMPTY end
                captured = captured + #g
            end
        end
    end
    local _, libs = group(nb, idx)
    if libs == 0 then return nil, "suicide" end
    if prev and key(nb) == prev then return nil, "ko" end
    return nb, captured
end

--- 数子法：返回 黑地(含子), 白地(含子)
function Core.area(board)
    local b, w = 0, 0
    local seen = {}
    for i = 1, N * N do
        local v = board[i]
        if v == HUMAN then b = b + 1
        elseif v == AI then w = w + 1
        elseif not seen[i] then
            local stack, size, tb, tw = { i }, 0, false, false
            seen[i] = true
            while #stack > 0 do
                local k = table.remove(stack)
                size = size + 1
                for _, j in ipairs(NEI[k]) do
                    local u = board[j]
                    if u == EMPTY then
                        if not seen[j] then seen[j] = true stack[#stack + 1] = j end
                    elseif u == HUMAN then tb = true
                    else tw = true end
                end
            end
            if tb and not tw then b = b + size elseif tw and not tb then w = w + size end
        end
    end
    return b, w
end

--- 终局差：黑 - 白 - 贴目（>0 黑胜）
function Core.margin(board)
    local b, w = Core.area(board)
    return b - w - KOMI, b, w
end

function Core.fresh()
    local b = {}
    for i = 1, N * N do b[i] = EMPTY end
    return { board = b, turn = HUMAN, prev = nil, passes = 0, over = false, history = {} }
end

local function snapshot(s)
    return { board = copy(s.board), turn = s.turn, prev = s.prev, passes = s.passes, last = s.last }
end

--- 当前行棋方落子，成功返回 true；不合法返回 false, 原因
function Core.play(s, idx)
    if s.over then return false, "over" end
    local nb, cap = Core.place(s.board, idx, s.turn, s.prev)
    if not nb then return false, cap end
    s.prev = key(s.board)
    s.board, s.last = nb, idx
    s.passes = 0
    s.turn = other(s.turn)
    return true, cap
end

function Core.pass(s)
    if s.over then return false end
    s.prev = key(s.board)
    s.passes = s.passes + 1
    s.last = nil
    if s.passes >= 2 then s.over = true else s.turn = other(s.turn) end
    return true
end

function Core.winner(s)
    if not s.over then return nil end
    return Core.margin(s.board) > 0 and HUMAN or AI
end

-- AI ------------------------------------------------------------------------

--- 空点 idx 是否是 who 的真眼候选（四周全是己方棋子，边角容许）
local function isEye(board, idx, who)
    for _, j in ipairs(NEI[idx]) do
        if board[j] ~= who then return false end
    end
    -- 至少有两口气的相邻己方棋串，避免填掉只有一只眼的活棋
    local ok = 0
    for _, j in ipairs(NEI[idx]) do
        local _, libs = group(board, j)
        if libs >= 2 then ok = ok + 1 end
    end
    return ok == #NEI[idx]
end

--- 为 AI 评估所有合法着法，返回最佳着法下标（无好棋则 nil 表示虚着）
function Core.aiMove(s, rng)
    local board = s.board
    local best, bi = 1.5, nil
    local stones = 0
    for i = 1, N * N do if board[i] ~= EMPTY then stones = stones + 1 end end
    local function near(idx, rad)
        local r, c = math.floor((idx - 1) / N) + 1, (idx - 1) % N + 1
        for dr = -rad, rad do
            for dc = -rad, rad do
                local rr, cc = r + dr, c + dc
                if rr >= 1 and rr <= N and cc >= 1 and cc <= N and board[(rr - 1) * N + cc] ~= EMPTY then
                    return true
                end
            end
        end
        return false
    end
    -- 己方全包围的空域（自己的地）不落子
    local owned = {}
    local seen = {}
    for i = 1, N * N do
        if board[i] == EMPTY and not seen[i] then
            local stack, region, tb, tw = { i }, {}, false, false
            seen[i] = true
            while #stack > 0 do
                local k = table.remove(stack)
                region[#region + 1] = k
                for _, j in ipairs(NEI[k]) do
                    local u = board[j]
                    if u == EMPTY then
                        if not seen[j] then seen[j] = true stack[#stack + 1] = j end
                    elseif u == HUMAN then tb = true else tw = true end
                end
            end
            if tw and not tb and #region <= 12 then
                for _, k in ipairs(region) do owned[k] = true end
            elseif tb and not tw and #region <= 4 then
                for _, k in ipairs(region) do owned[k] = "enemy" end
            end
        end
    end
    for idx = 1, N * N do
        if board[idx] == EMPTY and owned[idx] ~= true and not isEye(board, idx, AI) then
            local nb, cap = Core.place(board, idx, AI, s.prev)
            if nb then
                local _, libs = group(nb, idx)
                local score = 0
                local r, c = math.floor((idx - 1) / N) + 1, (idx - 1) % N + 1
                score = score + cap * 10
                -- 己方被打吃的棋串：长气逃跑
                for _, j in ipairs(NEI[idx]) do
                    if board[j] == AI then
                        local g, l0 = group(board, j)
                        if l0 == 1 then score = score + 6 + #g * 2 end
                    elseif board[j] == HUMAN then
                        local g, l1 = group(nb, j)
                        if l1 == 1 then score = score + 3 + #g end
                        local _, l0 = group(board, j)
                        if l0 == 2 and l1 == 1 then score = score + 2 end
                    end
                end
                if libs == 1 and cap == 0 then score = score - 25 end
                if libs == 2 then score = score - 1 end
                if owned[idx] == "enemy" then score = score - 3 end
                -- 位置：靠近中心、星位，并且在棋子附近
                local dc = math.abs(r - 5) + math.abs(c - 5)
                score = score + (8 - dc) * 0.25
                if r == 1 or c == 1 or r == N or c == N then score = score - 1.5 end
                if stones < 8 and (r == 3 or r == 7) and (c == 3 or c == 7) then score = score + 1.5 end
                if stones < 8 and r == 5 and c == 5 then score = score + 2.5 end
                if near(idx, 1) then score = score + 1.2 elseif near(idx, 2) then score = score + 0.8 end
                -- 贴着己方棋却不增加气的废着
                if libs <= 2 and cap == 0 then score = score - 1 end
                score = score + (rng and rng:int(100) / 100 or 0)
                if score > best then best, bi = score, idx end
            end
        end
    end
    return bi
end

--- 轮到 AI：落子或虚着。玩家刚虚着且 AI 已领先时直接虚着结束
function Core.aiTurn(s, rng)
    if s.over or s.turn ~= AI then return end
    if s.passes >= 1 and Core.margin(s.board) < 0 then
        Core.pass(s)
        return
    end
    local mv = Core.aiMove(s, rng)
    if mv then Core.play(s, mv) else Core.pass(s) end
end

--- 玩家落子/虚着，随后 AI 应对；返回 true 或 false, 原因
function Core.humanMove(s, idx, rng)
    if s.over or s.turn ~= HUMAN then return false, "over" end
    local snap = snapshot(s)
    local ok, why
    if idx == "pass" then ok = Core.pass(s) else ok, why = Core.play(s, idx) end
    if not ok then return false, why end
    s.history[#s.history + 1] = snap
    if #s.history > MAX_HISTORY then table.remove(s.history, 1) end
    Core.aiTurn(s, rng)
    return true
end

function Core.undo(s)
    local snap = table.remove(s.history)
    if not snap then return false end
    s.board, s.turn, s.prev, s.passes, s.last, s.over = snap.board, snap.turn, snap.prev, snap.passes, snap.last, false
    return true
end

local M = { id = "go9", title = T("围棋"), icon = "radio_button_unchecked", art = "icon_go9", tier = "A", desc = T("九路对弈"), help = T("九路围棋，你执黑先行，点按交叉点落子。\n棋子没有「气」（相邻的空点）就会被提走；不能下在没有气的地方（禁入点），也不能立刻提回刚被提的一子（打劫）。\n觉得没处可下时点「虚着」。双方连续虚着后终局，按数子法计分：棋子加围住的空点，白棋贴 7.5 目，多者获胜。\n终局时棋盘上的棋子都算活棋，请在虚着前先提掉对方的死子。"), core = Core }

function M.new(ctx)
    local self = {}
    local s
    local note

    local function persist() ctx:save({ state = s }) end

    local function finish(wasOver)
        if s.over and not wasOver and Core.winner(s) == HUMAN then
            ctx:record("wins", (ctx:best("wins") or 0) + 1)
        end
    end

    local function move(arg)
        local wasOver = s.over
        local ok, why = Core.humanMove(s, arg, ctx.rng)
        if not ok then
            if why == "ko" then note = T("打劫：不能立刻提回，请先下别处")
            elseif why == "suicide" then note = T("禁入点：落子后没有气")
            else note = nil end
            self.render()
            return
        end
        note = nil
        finish(wasOver)
        persist()
        self.render()
    end

    local function tap(r, c) move((r - 1) * N + c) end

    function self.render()
        local status
        if s.over then
            local m, b, w = Core.margin(s.board)
            status = (m > 0 and T("你赢了！") or T("对手获胜")) .. (T("    黑 %d  白 %d + 贴目 7.5")):format(b, w)
        elseif note then
            status = note
        elseif s.passes >= 1 then
            status = T("对手虚着，轮到你（黑）")
        else
            status = T("轮到你（黑）")
        end
        if not s.over then status = status .. (T("    累计获胜 %d 局")):format(ctx:best("wins") or 0) end
        local ownerOf = {}
        if s.over then
            -- 空点归属：只被一方包围的空域
            local seen = {}
            for i = 1, N * N do
                if s.board[i] == EMPTY and not seen[i] then
                    local stack, region, tb, tw = { i }, {}, false, false
                    seen[i] = true
                    while #stack > 0 do
                        local k = table.remove(stack)
                        region[#region + 1] = k
                        for _, j in ipairs(NEI[k]) do
                            local u = s.board[j]
                            if u == EMPTY then
                                if not seen[j] then seen[j] = true stack[#stack + 1] = j end
                            elseif u == HUMAN then tb = true else tw = true end
                        end
                    end
                    local o = (tb and not tw) and "black" or ((tw and not tb) and "white" or nil)
                    if o then for _, k in ipairs(region) do ownerOf[k] = o end end
                end
            end
        end
        ctx:render({
            title = T("围棋"),
            status = status,
            grid = {
                rows = N, cols = N, on_tap = tap, style = "go",
                stars = { { 3, 3 }, { 3, 7 }, { 5, 5 }, { 7, 3 }, { 7, 7 } },
                cell = function(r, c)
                    local idx = (r - 1) * N + c
                    local v = s.board[idx]
                    local mark = (s.last == idx) and (v == HUMAN and "white" or "black") or nil
                    if v == HUMAN then return { icon = "stone_black", icon_scale = 0.9, mark = mark } end
                    if v == AI then return { icon = "stone_white", icon_scale = 0.9, mark = mark } end
                    if ownerOf[idx] then return { mark = ownerOf[idx] } end
                    return {}
                end,
            },
            buttons = {
                {
                    { text = T("虚着"), enabled = not s.over and s.turn == HUMAN, callback = function() move("pass") end },
                    { text = T("悔棋"), enabled = #s.history > 0, callback = function() Core.undo(s) note = nil persist() self.render() end },
                    { text = T("新局"), callback = function() s = Core.fresh() note = nil persist() self.render() end },
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
