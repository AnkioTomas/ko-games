--[[--
黄金矿工（回合版）。实时摆动的钩子在墨水屏上不可行，改成：选一个角度（点棋盘或点 ◀ ▶），按「发射」，
一次结算。每次发射消耗「时间」：往返距离 ×（1 + 物品重量），所以重的石头和大金块很费时间；
没抓到东西也要花固定时间。时间用完时现金达到目标就过关，否则游戏结束。
炸药：开启后下一次抓到的东西会被炸掉（不得分），只花去程时间，用来甩掉石头之类的累赘。
--]]
local T = require("kogames.l10n")

local ROWS, COLS = 11, 9
local ORIGIN_X, ORIGIN_Y = COLS / 2, 0.5
local STEPS, STEP_DEG = 11, 15
local MID = (STEPS + 1) / 2
local MISS_COST = 3
local FIRST_ROW = 3

local KINDS = {
    gold_s = { value = 50, w = 0.8, odds = 34 },
    gold_m = { value = 120, w = 1.4, odds = 20 },
    gold_l = { value = 300, w = 2.4, odds = 8 },
    stone = { value = 20, w = 2.6, odds = 22 },
    diamond = { value = 600, w = 0.5, odds = 5 },
    bag = { value = 0, w = 1.2, odds = 11 },
}
local ORDER = { "gold_s", "gold_m", "gold_l", "stone", "diamond", "bag" }
local MODES = { { id = "easy", time = 80, label = "休闲" }, { id = "normal", time = 60, label = "标准" }, { id = "hard", time = 45, label = "困难" } }

local Core = {}

function Core.target(level)
    local t = 0
    for l = 1, level do t = t + 220 + 130 * l end
    return t
end

local function pick(rng)
    local total = 0
    for _, k in ipairs(ORDER) do total = total + KINDS[k].odds end
    local n = rng:int(total)
    for _, k in ipairs(ORDER) do
        n = n - KINDS[k].odds
        if n <= 0 then return k end
    end
end

function Core.genBoard(rng, level, money)
    local need = Core.target(level) - money
    local board
    for _ = 1, 60 do
        board = {}
        for i = 1, ROWS * COLS do board[i] = 0 end
        local free = {}
        for r = FIRST_ROW, ROWS do
            for c = 1, COLS do free[#free + 1] = (r - 1) * COLS + c end
        end
        rng:shuffle(free)
        local n = math.min(14 + level * 2, 26)
        local sum = 0
        for i = 1, n do
            local k = pick(rng)
            board[free[i]] = k
            sum = sum + (k == "bag" and 120 or KINDS[k].value)
        end
        if sum >= need * 1.8 then break end
    end
    return board
end

function Core.fresh(rng, mode)
    local s = { level = 1, money = 0, dyn = 1, armed = false, aim = MID, mode = mode or "normal", shots = 0 }
    s.time = Core.budget(s)
    s.board = Core.genBoard(rng, 1, 0)
    return s
end

function Core.budget(s)
    for _, m in ipairs(MODES) do
        if m.id == s.mode then return m.time end
    end
    return 60
end

function Core.remaining(s)
    local n = 0
    for _, v in ipairs(s.board) do if v ~= 0 and v ~= "stone" then n = n + 1 end end
    return n
end

--- 当前关是否结束：时间耗尽，或可得分的东西都抓完了。
function Core.levelOver(s) return s.time <= 0 or Core.remaining(s) == 0 end
function Core.won(s) return s.money >= Core.target(s.level) end

function Core.angle(idx) return (idx - MID) * STEP_DEG end

--- 沿角度发射的射线：返回命中格序号（或 nil）、命中距离、途经的空格列表。
function Core.ray(s, idx)
    local a = math.rad(Core.angle(idx))
    local dx, dy = math.sin(a), math.cos(a)
    local path, seen = {}, {}
    local t = 0.6
    while true do
        local x, y = ORIGIN_X + dx * t, ORIGIN_Y + dy * t
        if x < 0 or x >= COLS or y >= ROWS then return nil, nil, path end
        local c, r = math.floor(x) + 1, math.floor(y) + 1
        local i = (r - 1) * COLS + c
        if s.board[i] ~= 0 then
            local cx, cy = c - 0.5 - ORIGIN_X, r - 0.5 - ORIGIN_Y
            return i, math.sqrt(cx * cx + cy * cy), path
        end
        if not seen[i] and r > 1 then seen[i] = true path[#path + 1] = i end
        t = t + 0.05
    end
end

function Core.setAim(s, idx) s.aim = math.max(1, math.min(STEPS, idx)) end

--- 点棋盘上的格子 -> 对应的发射角度序号。
function Core.aimAt(r, c)
    local dx, dy = c - 0.5 - ORIGIN_X, r - 0.5 - ORIGIN_Y
    if dy <= 0 then return nil end
    local deg = math.deg(math.atan2(dx, dy))
    return math.max(1, math.min(STEPS, math.floor(deg / STEP_DEG + 0.5) + MID))
end

--- 发射。返回 { hit=kind|nil, gain=, cost=, blown=, dyn= }。
function Core.fire(s, rng)
    if Core.levelOver(s) then return nil end
    local i, dist = Core.ray(s, s.aim)
    local res = { cost = MISS_COST, gain = 0 }
    s.shots = s.shots + 1
    if i then
        local kind = s.board[i]
        local def = KINDS[kind]
        res.hit = kind
        s.board[i] = 0
        if s.armed and s.dyn > 0 then
            s.dyn = s.dyn - 1
            res.blown = true
            res.cost = math.max(1, math.ceil(dist))
        else
            res.cost = math.max(1, math.ceil(dist * (1 + def.w)))
            if kind == "bag" then
                if rng:int(5) == 1 then
                    s.dyn = s.dyn + 1
                    res.dyn = 1
                else
                    res.gain = 50 * (1 + rng:int(6))
                end
            else
                res.gain = def.value
            end
            s.money = s.money + res.gain
        end
        s.armed = false
    end
    s.time = s.time - res.cost
    return res
end

function Core.nextLevel(s, rng)
    s.level = s.level + 1
    s.dyn = s.dyn + 1
    s.time = Core.budget(s)
    s.armed = false
    s.board = Core.genBoard(rng, s.level, s.money)
end

local M = { id = "goldminer", title = T("黄金矿工"), icon = "paid", tier = "B", desc = T("选角度发射钩子，抓金子"), help = T("目标：在时间用完之前，让现金达到本关目标。\n点棋盘上的某处（或点 ◀ ▶）选择钩子的方向，小黑点是预计的路线，灰底格子是会被抓到的东西；按「发射」抓取。\n每次发射都要花时间：往返距离越远、东西越重，花得越多。大金块和石头很费时间，钻石又轻又值钱；没抓到东西也要花 3 点时间。\n「炸药」开启后，下一次抓到的东西会被炸掉，只花去程时间，适合甩掉石头。口袋（袋子）里可能是钱，也可能是一枚炸药。\n过关后现金保留，目标会提高，并奖励一枚炸药。"), core = Core }

function M.new(ctx)
    local self = {}
    local s
    local last

    local function persist() ctx:save({ state = s }) end

    local function fresh(mode)
        s = Core.fresh(ctx.rng, mode or (s and s.mode) or "normal")
        last = nil
        persist()
        self.render()
    end

    local function fire()
        local res = Core.fire(s, ctx.rng)
        if not res then return end
        if not res.hit then
            last = T("扑空了，花去 %d 时间", res.cost)
        elseif res.blown then
            last = T("炸掉了，花去 %d 时间", res.cost)
        elseif res.dyn then
            last = T("口袋里是炸药！花去 %d 时间", res.cost)
        else
            last = T("抓到 +%d，花去 %d 时间", res.gain, res.cost)
        end
        if Core.levelOver(s) and not Core.won(s) then
            s.over = true
            if ctx:record("level", s.level) then ctx:notify(T("新纪录：%d", s.level)) end
        end
        persist()
        self.render()
    end

    function self.render()
        local over = Core.levelOver(s)
        local won = over and Core.won(s)
        local aim_i, _, path = Core.ray(s, s.aim)
        local marks = {}
        for _, i in ipairs(path) do marks[i] = true end
        local status = T("第 %d 关    目标 %d    现金 %d    时间 %d    炸药 %d", s.level, Core.target(s.level), s.money, math.max(0, s.time), s.dyn)
        local best = ctx:best("level")
        if best then status = status .. T("    最高 %d 关", best) end
        local line2 = last or ""
        if over then
            line2 = won and T("过关！") or T("时间到，现金不足，游戏结束")
        end
        local mode_row = {}
        for _, m in ipairs(MODES) do
            mode_row[#mode_row + 1] = { text = T(m.label), selected = m.id == s.mode, callback = function() fresh(m.id) end }
        end
        local buttons
        if over then
            buttons = { { won and { text = T("下一关"), callback = function() Core.nextLevel(s, ctx.rng) last = nil persist() self.render() end }
                or { text = T("重新开始"), callback = function() fresh() end } } }
        else
            buttons = {
                { { text = "◀", callback = function() Core.setAim(s, s.aim - 1) self.render() end },
                    { text = T("发射"), callback = fire },
                    { text = "▶", callback = function() Core.setAim(s, s.aim + 1) self.render() end } },
                { { text = T("炸药 %d", s.dyn), selected = s.armed, enabled = s.dyn > 0, callback = function() s.armed = not s.armed persist() self.render() end } },
            }
        end
        if line2 ~= "" then table.insert(buttons, 1, { label = line2 }) end
        buttons[#buttons + 1] = { { menu = true, text = T("新游戏"), callback = function() fresh() end } }
        ctx:render({
            title = T("黄金矿工"),
            status = status,
            grid = {
                rows = ROWS, cols = COLS,
                cell = function(r, c)
                    local i = (r - 1) * COLS + c
                    if r == 1 and c == math.ceil(COLS / 2) then return { icon = "miner", icon_scale = 0.9 } end
                    local k = s.board[i]
                    if k ~= 0 then
                        return { icon = k, icon_scale = 0.85, fill = (i == aim_i and not over) and "grey" or nil }
                    end
                    if marks[i] and not over then return { mark = "black" } end
                end,
                on_tap = function(r, c)
                    local idx = Core.aimAt(r, c)
                    if idx and not Core.levelOver(s) then
                        s.aim = idx
                        self.render()
                    end
                end,
            },
            settings = { groups = { { label = T("难度"), options = mode_row } }, reset = function() fresh() end },
            buttons = buttons,
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.board and #saved.state.board == ROWS * COLS then
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
