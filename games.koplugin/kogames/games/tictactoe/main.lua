--[[--
井字棋（可选 3×3 连三、4×4 连四、5×5 连四）。你执 X 先手，电脑执 O：先看能否直接获胜、再看是否要堵，
3×3 用完整极小搜索（不会输），更大的棋盘按线路潜力打分。
--]]
local T = require("kogames.l10n")
local MODES = { { n = 3, k = 3 }, { n = 4, k = 4 }, { n = 5, k = 4 } }

local Core = {}

local function lines(n, k)
    local out = {}
    local dirs = { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }
    for r = 1, n do
        for c = 1, n do
            for _, d in ipairs(dirs) do
                local er, ec = r + d[1] * (k - 1), c + d[2] * (k - 1)
                if er >= 1 and er <= n and ec >= 1 and ec <= n then
                    local l = {}
                    for i = 0, k - 1 do l[#l + 1] = (r + d[1] * i - 1) * n + c + d[2] * i end
                    out[#out + 1] = l
                end
            end
        end
    end
    return out
end

function Core.fresh(n, k) return { n = n, k = k, board = {}, turn = 1, moves = 0 } end

--- 返回赢家（1/2）、"draw" 或 nil，以及获胜线。
function Core.winner(s)
    s.lines = s.lines or lines(s.n, s.k)
    for _, l in ipairs(s.lines) do
        local v = s.board[l[1]]
        if v then
            local ok = true
            for i = 2, #l do if s.board[l[i]] ~= v then ok = false break end end
            if ok then return v, l end
        end
    end
    if s.moves == s.n * s.n then return "draw" end
end

function Core.play(s, i)
    if s.board[i] or Core.winner(s) then return false end
    s.board[i] = s.turn
    s.turn = 3 - s.turn
    s.moves = s.moves + 1
    return true
end

local function minimax(s, me)
    local w = Core.winner(s)
    if w == me then return 1 elseif w == "draw" then return 0 elseif w then return -1 end
    local turn_is_me = s.turn == me
    local best = turn_is_me and -2 or 2
    for i = 1, s.n * s.n do
        if not s.board[i] then
            local t = s.turn
            s.board[i], s.turn, s.moves = t, 3 - t, s.moves + 1
            local v = minimax(s, me)
            s.board[i], s.turn, s.moves = nil, t, s.moves - 1
            if turn_is_me then best = math.max(best, v) else best = math.min(best, v) end
            if (turn_is_me and best == 1) or (not turn_is_me and best == -1) then break end
        end
    end
    return best
end

local function wins(s, i, who)
    s.board[i] = who
    local w = Core.winner(s)
    s.board[i] = nil
    return w == who
end

function Core.aiMove(s, rng)
    local me = s.turn
    local free = {}
    for i = 1, s.n * s.n do if not s.board[i] then free[#free + 1] = i end end
    if #free == 0 then return nil end
    for _, who in ipairs({ me, 3 - me }) do
        for _, i in ipairs(free) do if wins(s, i, who) then return i end end
    end
    if s.n == 3 then
        local best, pick = -2, {}
        for _, i in ipairs(free) do
            s.board[i], s.turn, s.moves = me, 3 - me, s.moves + 1
            local v = minimax(s, me)
            s.board[i], s.turn, s.moves = nil, me, s.moves - 1
            if v > best then best, pick = v, { i } elseif v == best then pick[#pick + 1] = i end
        end
        return pick[rng:int(#pick)]
    end
    s.lines = s.lines or lines(s.n, s.k)
    local score = {}
    for _, l in ipairs(s.lines) do
        local mine, theirs = 0, 0
        for _, i in ipairs(l) do
            if s.board[i] == me then mine = mine + 1 elseif s.board[i] then theirs = theirs + 1 end
        end
        local v = 0
        if theirs == 0 then v = 4 ^ mine elseif mine == 0 then v = 4 ^ theirs * 0.9 end
        for _, i in ipairs(l) do if not s.board[i] then score[i] = (score[i] or 0) + v end end
    end
    local best, pick = -1, {}
    for _, i in ipairs(free) do
        local v = score[i] or 0
        if v > best then best, pick = v, { i } elseif v == best then pick[#pick + 1] = i end
    end
    return pick[rng:int(#pick)]
end

local M = { id = "tictactoe", title = T("井字棋"), icon = "grid_on", tier = "A", desc = T("连成一线即获胜"), help = T("你执 X 先手，电脑执 O。点空格落子，横、竖、斜任意方向先连成一线者获胜。\n可选 3×3（连三）、4×4（连四）、5×5（连四）。3×3 的电脑不会输，最好的结果是平局；棋盘越大越有机会获胜。"), core = Core }

function M.new(ctx)
    local self = {}
    local s

    local function key() return "win" .. s.n end
    local function persist() ctx:save({ state = { n = s.n, k = s.k, board = s.board, turn = s.turn, moves = s.moves } }) end

    local function fresh(n, k)
        s = Core.fresh(n, k)
        persist()
        self.render()
    end

    local function finish()
        local w = Core.winner(s)
        if w == 1 then
            local stats = ctx.host:load("stats_" .. ctx.id) or {}
            ctx:record(key(), (stats[key()] or 0) + 1)
        end
    end

    local function tap(r, c)
        local i = (r - 1) * s.n + c
        if s.turn ~= 1 or not Core.play(s, i) then return end
        if not Core.winner(s) then
            local j = Core.aiMove(s, ctx.rng)
            if j then Core.play(s, j) end
        end
        if Core.winner(s) then finish() end
        persist()
        self.render()
    end

    function self.render()
        local w, line = Core.winner(s)
        local hot = {}
        for _, i in ipairs(line or {}) do hot[i] = true end
        local status
        if w == 1 then status = T("你赢了！") elseif w == 2 then status = T("电脑赢了") elseif w == "draw" then status = T("平局") else status = T("轮到你（X）") end
        local wins_n = ctx:best(key())
        if wins_n then status = status .. T("    胜场 %d", wins_n) end
        local size_row = {}
        for _, m in ipairs(MODES) do
            local selected = m.n == s.n
            size_row[#size_row + 1] = { text = m.n .. "×" .. m.n, selected = selected, callback = function()
                if not selected then fresh(m.n, m.k) end
            end }
        end
        ctx:render({
            title = T("井字棋"),
            status = status,
            grid = {
                rows = s.n, cols = s.n, gap = true,
                cell = function(r, c)
                    local i = (r - 1) * s.n + c
                    local v = s.board[i]
                    if not v then return { fill = "grey" } end
                    return { text = v == 1 and "X" or "O", scale = 0.6, fill = hot[i] and "black" or "grey" }
                end,
                on_tap = tap,
            },
            settings = { groups = { { label = T("大小"), options = size_row } }, reset = function() fresh(s.n, s.k) end },
            buttons = { { { menu = true, text = T("新游戏"), callback = function() fresh(s.n, s.k) end } } },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.board then
            s = saved.state
            s.board = s.board or {}
            self.render()
        else
            fresh(3, 3)
        end
    end

    self.state = function() return s end
    self.tap = tap
    return self
end

return M
