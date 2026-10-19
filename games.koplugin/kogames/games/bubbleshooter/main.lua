--[[--
泡泡龙（回合版）。选一列（点棋盘或点 ◀ ▶），按「发射」，泡泡沿这一列飞到最上面的泡泡下方停住。
同色四向相连 3 个以上消除，消除后不再与顶部相连的泡泡会掉落。连续几次没有消除时整体下压一行，
任何泡泡压到发射线（最底一行）就结束。下一个泡泡只会是盘面上还存在的颜色。
--]]
local T = require("kogames.l10n")

local ROWS, COLS = 11, 9
local MODES = {
    { id = "easy", colors = 4, period = 7, label = "简单" },
    { id = "normal", colors = 5, period = 6, label = "普通" },
    { id = "hard", colors = 6, period = 5, label = "困难" },
}
local START_ROWS = 5

local Core = {}

local function modeOf(id)
    for _, m in ipairs(MODES) do if m.id == id then return m end end
    return MODES[2]
end

local function randomRow(s, rng)
    local row = {}
    for c = 1, COLS do row[c] = rng:int(s.colors) end
    return row
end

--- 盘面上现有的颜色（用来决定下一个泡泡）。
local function present(s)
    local seen, list = {}, {}
    for i = 1, ROWS * COLS do
        local v = s.board[i]
        if v ~= 0 and not seen[v] then seen[v] = true list[#list + 1] = v end
    end
    table.sort(list)
    return list
end

local function draw(s, rng)
    local list = present(s)
    if #list == 0 then return rng:int(s.colors) end
    return list[rng:int(#list)]
end

function Core.fresh(rng, mode)
    local m = modeOf(mode)
    local s = { mode = m.id, colors = m.colors, period = m.period, board = {}, score = 0, misses = 0, aim = 5 }
    for i = 1, ROWS * COLS do s.board[i] = 0 end
    for r = 1, START_ROWS do
        local row = randomRow(s, rng)
        for c = 1, COLS do s.board[(r - 1) * COLS + c] = row[c] end
    end
    s.cur, s.nxt = draw(s, rng), draw(s, rng)
    return s
end

--- 这一列里泡泡会停在哪一行（nil 表示这一列已经堆到发射线）。
function Core.landing(s, col)
    local r = ROWS
    while r >= 1 and s.board[(r - 1) * COLS + col] == 0 do r = r - 1 end
    r = r + 1
    if r > ROWS then return nil end
    return r
end

local function neighbors(i)
    local r, c = math.floor((i - 1) / COLS) + 1, (i - 1) % COLS + 1
    local out = {}
    if r > 1 then out[#out + 1] = i - COLS end
    if r < ROWS then out[#out + 1] = i + COLS end
    if c > 1 then out[#out + 1] = i - 1 end
    if c < COLS then out[#out + 1] = i + 1 end
    return out
end

local function group(s, i)
    local color, seen, stack, list = s.board[i], { [i] = true }, { i }, {}
    while #stack > 0 do
        local k = table.remove(stack)
        list[#list + 1] = k
        for _, n in ipairs(neighbors(k)) do
            if not seen[n] and s.board[n] == color then seen[n] = true stack[#stack + 1] = n end
        end
    end
    return list
end

--- 与第一行不相连的泡泡数。
local function dropFloating(s)
    local seen, stack = {}, {}
    for c = 1, COLS do
        if s.board[c] ~= 0 then seen[c] = true stack[#stack + 1] = c end
    end
    while #stack > 0 do
        local k = table.remove(stack)
        for _, n in ipairs(neighbors(k)) do
            if not seen[n] and s.board[n] ~= 0 then seen[n] = true stack[#stack + 1] = n end
        end
    end
    local n = 0
    for i = 1, ROWS * COLS do
        if s.board[i] ~= 0 and not seen[i] then s.board[i] = 0 n = n + 1 end
    end
    return n
end

local function descend(s, rng)
    for i = ROWS * COLS, COLS + 1, -1 do s.board[i] = s.board[i - COLS] end
    local row = randomRow(s, rng)
    for c = 1, COLS do s.board[c] = row[c] end
end

function Core.over(s)
    for c = 1, COLS do if s.board[(ROWS - 1) * COLS + c] ~= 0 then return true end end
    return false
end

function Core.cleared(s)
    for i = 1, COLS do if s.board[i] ~= 0 then return false end end
    return true
end

--- 发射。返回 { popped, fell, descended } 或 nil（这一列已满）。
function Core.fire(s, rng, col)
    local r = Core.landing(s, col)
    if not r or Core.over(s) then return nil end
    local i = (r - 1) * COLS + col
    s.board[i] = s.cur
    local res = { popped = 0, fell = 0 }
    local g = group(s, i)
    if #g >= 3 then
        for _, k in ipairs(g) do s.board[k] = 0 end
        res.popped = #g
        res.fell = dropFloating(s)
        s.score = s.score + res.popped * 10 + res.fell * 20
        s.misses = 0
    else
        s.misses = s.misses + 1
        if s.misses >= s.period then
            descend(s, rng)
            s.misses, res.descended = 0, true
        end
    end
    if Core.cleared(s) then
        s.score = s.score + 200
        res.cleared = true
        for k = 1, 3 do descend(s, rng) end
    end
    s.cur = s.nxt
    s.nxt = draw(s, rng)
    if not present(s)[1] then s.cur = rng:int(s.colors) end
    return res
end

function Core.swap(s) s.cur, s.nxt = s.nxt, s.cur end

local M = { id = "bubbleshooter", title = T("泡泡龙"), icon = "bubble_chart", tier = "A", desc = T("选一列发射泡泡，三个同色相连即消除"), help = T("目标：尽量多得分，别让泡泡压到最底下的发射线。\n点棋盘的一列或点 ◀ ▶ 选择发射的列，点「发射」，泡泡会沿这一列飞到最上面的泡泡下方停住（虚线是路径）。\n同色泡泡上下左右相连 3 个以上就消除；消除后不再与最上面一行相连的泡泡会掉落，掉落的分更高。\n每连续几次没有消除，整体会下压一行（难度越高越频繁）。清空全部泡泡有额外奖励。\n「换弹」交换当前和下一个泡泡（左下角深色的是下一个）。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, last

    local function persist() ctx:save({ state = s }) end

    local function fresh(mode)
        s, last = Core.fresh(ctx.rng, mode or (s and s.mode) or "normal"), nil
        persist()
        self.render()
    end

    local function fire()
        if Core.over(s) then return end
        local res = Core.fire(s, ctx.rng, s.aim)
        if not res then last = T("这一列已经满了") self.render() return end
        if res.popped > 0 then
            last = T("消除 %d 个，掉落 %d 个", res.popped, res.fell)
        elseif res.descended then
            last = T("泡泡下压一行")
        else
            last = nil
        end
        if Core.over(s) and ctx:record("score_" .. s.mode, s.score) then ctx:notify(T("新纪录：%d", s.score)) end
        persist()
        self.render()
    end

    function self.render()
        local over = Core.over(s)
        local land = not over and Core.landing(s, s.aim)
        local status = T("得分 %d    再 %d 次不消除就下压", s.score, s.period - s.misses)
        local best = ctx:best("score_" .. s.mode)
        if best then status = status .. T("    最高 %d", best) end
        local mode_row = {}
        for _, m in ipairs(MODES) do
            mode_row[#mode_row + 1] = { text = T(m.label), selected = m.id == s.mode, callback = function() fresh(m.id) end }
        end
        local buttons
        if over then
            buttons = { { label = T("泡泡压到底了，游戏结束") }, { { text = T("重新开始"), callback = function() fresh() end } } }
        else
            buttons = {
                { { text = "◀", callback = function() s.aim = math.max(1, s.aim - 1) self.render() end },
                    { text = T("发射"), callback = fire },
                    { text = "▶", callback = function() s.aim = math.min(COLS, s.aim + 1) self.render() end } },
                { { text = T("换弹"), callback = function() Core.swap(s) persist() self.render() end } },
            }
            if last then table.insert(buttons, 1, { label = last }) end
        end
        buttons[#buttons + 1] = { { menu = true, text = T("新游戏"), callback = function() fresh() end } }
        local nxtCol = s.aim == 1 and COLS or 1
        ctx:render({
            title = T("泡泡龙"),
            status = status,
            grid = {
                rows = ROWS + 1, cols = COLS,
                cell = function(r, c)
                    if r == ROWS + 1 then
                        if over then return nil end
                        if c == s.aim then return { icon = string.format("sym_%02d", s.cur), icon_scale = 0.8, fill = "grey" } end
                        if c == nxtCol then return { icon = string.format("sym_%02d_w", s.nxt), icon_scale = 0.6, fill = "black" } end
                        return nil
                    end
                    local v = s.board[(r - 1) * COLS + c]
                    if v ~= 0 then return { icon = string.format("sym_%02d", v), icon_scale = 0.8, fill = "grey" } end
                    if land and c == s.aim and r >= land then return { mark = "black" } end
                end,
                on_tap = function(_, c)
                    if over then return end
                    s.aim = c
                    self.render()
                end,
            },
            settings = { groups = { { label = T("难度"), options = mode_row } }, reset = function() fresh() end },
            buttons = buttons,
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.board and #saved.state.board == ROWS * COLS and saved.state.cur then
            s = saved.state
            self.render()
        else
            fresh("normal")
        end
    end

    self.state = function() return s end
    self.fire = fire
    return self
end

return M
