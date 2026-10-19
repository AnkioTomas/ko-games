--[[--
黄金矿工（经典版）。钩子绕矿工的绞盘左右匀速摆动，点屏幕（或「发射」）后沿当前角度伸出，
碰到东西就抓住往回拉：金块越大、石头越重拉得越慢，钻石和小金块又快又值钱。
墨水屏用定时 tick（约 0.3 秒一拍）推进：摆动、伸缩、倒计时都按拍走。
时间到时现金达到目标就过关（现金带到下一关，目标逐关提高），否则游戏结束。
炸药：拉回途中点「炸药」，炸掉手里的东西（不得分），钩子立刻空钩收回。
--]]
local T = require("kogames.l10n")

local W, H = 100, 130
local AX, AY = 50, 17 -- 钩子锚点（绞盘）
local GROUND = 21
local TICK = 0.3
local STEPS, STEP_DEG = 6, 12 -- 摆动 ±72°，一个来回 24 拍，单程 12 拍
local OUT_SPEED = 13
local EMPTY_SPEED = 14
local HOOK_R = 1.6
local DYN = 2
local REST = 7 -- 钩子静止时的绳长

local KINDS = {
    gold_l = { r = 9, value = 500, speed = 3, odds = 14 },
    gold_m = { r = 6, value = 250, speed = 5, odds = 30 },
    gold_s = { r = 3.5, value = 100, speed = 9, odds = 40 },
    stone = { r = 6, value = 20, speed = 2.5, odds = 0 },
    stone_s = { r = 4, value = 11, speed = 4, odds = 0 },
    diamond = { r = 2.6, value = 600, speed = 10, odds = 0 },
    bag = { r = 4.6, value = 150, speed = 7, odds = 0 },
}
local GOLDS = { "gold_l", "gold_m", "gold_s" }

local MODES = {
    { id = "easy", label = "休闲", time = 75, mult = 0.75 },
    { id = "normal", label = "标准", time = 60, mult = 1 },
    { id = "hard", label = "困难", time = 50, mult = 1.3 },
}
local function modeOf(id)
    for _, m in ipairs(MODES) do if m.id == id then return m end end
    return MODES[2]
end

local Core = { W = W, H = H, AX = AX, AY = AY, GROUND = GROUND, TICK = TICK, STEPS = STEPS, STEP_DEG = STEP_DEG,
    KINDS = KINDS, MODES = MODES, DYN = DYN }

--- 到该关为止累计的目标现金（现金跨关保留）。
function Core.target(level, mode)
    local m = modeOf(mode)
    local t = 0
    for l = 1, level do t = t + 650 + (l - 1) * 450 + (l > 1 and (l - 1) * (l - 1) * 40 or 0) end
    return math.floor(t * m.mult / 10 + 0.5) * 10
end

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function place(s, rng, kind)
    local r = KINDS[kind].r
    for _ = 1, 50 do
        local x = 6 + r + rng:float() * (W - 12 - 2 * r)
        local y = 36 + r + rng:float() * (H - 40 - 2 * r)
        local ok = true
        for _, o in ipairs(s) do
            if dist(x, y, o.x, o.y) < o.r + r + 2 then ok = false break end
        end
        if ok then
            s[#s + 1] = { kind = kind, x = x, y = y, r = r }
            return true
        end
    end
    return false
end

--- 生成物品，保证总价值足够超过 need。
function Core.genObjs(rng, level, need)
    local objs = {}
    for _ = 1, math.min(5, 2 + math.floor(level / 2) + rng:int(2)) do
        place(objs, rng, rng:int(3) == 1 and "stone_s" or "stone")
    end
    for _ = 1, rng:int(2) do place(objs, rng, "bag") end
    for _ = 1, rng:int(3) do place(objs, rng, "diamond") end
    local function total()
        local v = 0
        for _, o in ipairs(objs) do
            if o.kind ~= "stone" and o.kind ~= "stone_s" then v = v + KINDS[o.kind].value end
        end
        return v
    end
    local sum_odds = 0
    for _, k in ipairs(GOLDS) do sum_odds = sum_odds + KINDS[k].odds end
    local guard = 0
    while (total() < need * 1.7 or #objs < 12) and guard < 60 and #objs < 24 do
        guard = guard + 1
        local roll, pick = rng:float() * sum_odds, GOLDS[3]
        for _, k in ipairs(GOLDS) do
            roll = roll - KINDS[k].odds
            if roll <= 0 then pick = k break end
        end
        place(objs, rng, pick)
    end
    return objs
end

local function setupLevel(s, rng)
    local m = modeOf(s.mode)
    s.time = m.time
    s.dyn = DYN
    s.phase, s.k, s.dir, s.len, s.ang, s.held = "swing", 0, 1, REST, 0, nil
    s.cleared, s.over, s.event = false, false, nil
    s.objs = Core.genObjs(rng, s.level, math.max(400, Core.target(s.level, s.mode) - s.money))
end

function Core.fresh(rng, mode)
    local s = { mode = modeOf(mode).id, level = 1, money = 0 }
    setupLevel(s, rng)
    return s
end

function Core.nextLevel(s, rng)
    if not s.cleared then return false end
    s.level = s.level + 1
    setupLevel(s, rng)
    return true
end

--- 当前钩子角度（弧度，0 为正下方，正为向右）。
function Core.angle(s)
    local deg = s.phase == "swing" and s.k * STEP_DEG or (s.ang or 0)
    return math.rad(deg)
end

function Core.tip(s)
    local a = Core.angle(s)
    return AX + s.len * math.sin(a), AY + s.len * math.cos(a)
end

function Core.won(s) return s.money >= Core.target(s.level, s.mode) end

--- 发射：只有摆动中才能发射。
function Core.fire(s)
    if s.over or s.cleared or s.phase ~= "swing" then return false end
    s.phase, s.ang, s.len, s.event = "out", s.k * STEP_DEG, REST, nil
    return true
end

--- 炸掉手里的东西，钩子空钩收回。
function Core.blast(s)
    if s.phase ~= "back" or not s.held or s.dyn <= 0 then return false end
    s.dyn = s.dyn - 1
    for i, o in ipairs(s.objs) do
        if o == s.held then table.remove(s.objs, i) break end
    end
    s.held = nil
    s.event = { kind = "blast" }
    return true
end

local function hit(s)
    local tx, ty = Core.tip(s)
    local best, bd
    for _, o in ipairs(s.objs) do
        local d = dist(tx, ty, o.x, o.y)
        if d <= o.r + HOOK_R and (not bd or d < bd) then best, bd = o, d end
    end
    return best
end

local function carry(s)
    local o = s.held
    if not o then return end
    local a = Core.angle(s)
    local tx, ty = Core.tip(s)
    o.x, o.y = tx + math.sin(a) * o.r * 0.8, ty + math.cos(a) * o.r * 0.8
end

local function settle(s, rng)
    s.phase, s.len = "swing", REST
    s.k = math.max(-STEPS, math.min(STEPS, math.floor((s.ang or 0) / STEP_DEG + 0.5)))
    local o = s.held
    s.held = nil
    if not o then return end
    for i, x in ipairs(s.objs) do
        if x == o then table.remove(s.objs, i) break end
    end
    local gain = KINDS[o.kind].value
    if o.kind == "bag" then gain = 50 + 50 * rng:int(8) end
    s.money = s.money + gain
    s.event = { kind = "gain", value = gain, item = o.kind }
end

--- 前进一拍。返回 "swing" | "out" | "back" | "gain" | "miss" | "over" | "cleared" | "idle"
function Core.tick(s, rng)
    if s.over or s.cleared then return "idle" end
    s.time = math.max(0, s.time - TICK)
    local r = s.phase
    if s.phase == "swing" then
        s.k = s.k + s.dir
        if s.k >= STEPS then s.k, s.dir = STEPS, -1
        elseif s.k <= -STEPS then s.k, s.dir = -STEPS, 1 end
    elseif s.phase == "out" then
        for _ = 1, OUT_SPEED do
            s.len = s.len + 1
            local tx, ty = Core.tip(s)
            local o = hit(s)
            if o then
                s.held, s.phase = o, "back"
                carry(s)
                break
            end
            if tx < 2 or tx > W - 2 or ty > H - 2 then s.phase = "back" break end
        end
        if s.phase == "back" then r = "back" end
    else
        local speed = s.held and KINDS[s.held.kind].speed or EMPTY_SPEED
        s.len = s.len - speed
        if s.len <= REST then
            local had = s.held
            settle(s, rng)
            r = had and "gain" or "miss"
        else
            carry(s)
        end
    end
    if s.time <= 0 and s.phase == "swing" then
        if Core.won(s) then s.cleared = true r = "cleared" else s.over = true r = "over" end
    end
    return r
end

local M = { id = "goldminer", title = T("黄金矿工"), icon = "paid", tier = "C", desc = T("摆动的钩子，抓金子"),
    help = T("经典黄金矿工：钩子会在矿工下方左右摆动，点画布任意处放出钩子，沿当前方向直线伸出。\n钩子碰到金块、钻石、钱袋或石头就抓住并拉回：大金块和石头很重，拉得很慢；小金块、钻石、钱袋拉得快。没抓到东西钩子会空收回。\n画布左上是现金/目标，右上是剩余时间，下面的炸药图标是剩余炸药数。时间到时现金达到目标就过关（现金会带到下一关，目标逐关提高），否则游戏结束。\n拉着东西往回收时点底部炸药按钮，炸掉手里的东西（不得分）并立刻空钩收回，适合甩掉石头。\n开局、暂停、过关、失败时点画布继续；暂停、新游戏和难度（休闲/标准/困难）在右上角设置里。"),
    core = Core }

function M.new(ctx)
    local self = {}
    local s
    local paused, handle, token = true, nil, 0

    local function persist() ctx:save({ state = s }) end

    local function halt()
        token = token + 1
        if handle then ctx.host:unschedule(handle) handle = nil end
    end

    local function arm()
        halt()
        local mine = token
        handle = ctx.host:schedule(TICK, function()
            if mine ~= token or paused or s.over or s.cleared then return end
            handle = nil
            self.tick()
        end)
    end

    local function finish()
        halt()
        paused = true
        if s.over and ctx:record("level", s.level) then ctx:notify(T("新纪录：%d", s.level)) end
        persist()
    end

    function self.render()
        local target = Core.target(s.level, s.mode)
        local status = T("第 %d 关", s.level)
        local best = ctx:best("level")
        if best then status = status .. T("    最高 %d 关", math.max(best, s.level)) end

        local mode_row = {}
        for _, m in ipairs(MODES) do
            mode_row[#mode_row + 1] = { text = T(m.label), selected = m.id == s.mode, callback = function() self.newGame(m.id) end }
        end
        local buttons = {
            { { icon = "dynamite", enabled = not paused and s.phase == "back" and s.held ~= nil and s.dyn > 0,
                callback = function() self.blast() end },
              { menu = true, text = paused and not (s.over or s.cleared) and T("继续") or T("暂停"),
                enabled = not (s.over or s.cleared), callback = function() self.toggle() end },
              { menu = true, text = T("新游戏"), callback = function() self.newGame() end } },
        }

        ctx:render({
            title = T("黄金矿工"),
            status = status,
            canvas = {
                w = W, h = H,
                draw = function(d) self.draw(d, target) end,
                on_tap = function() self.tap() end,
            },
            settings = { groups = { { label = T("难度"), options = mode_row } }, reset = function() self.newGame() end },
            buttons = buttons,
        })
    end

    function self.draw(d, target)
        d.rect(0, GROUND, W, H - GROUND, "grey")
        d.rect(0, GROUND - 0.8, W, 1.6, "black")
        d.icon("miner", 70, 11, 18)
        d.icon("winch", AX, AY - 1, 13)
        d.icon("coin", 6, 5, 6)
        d.text(s.money .. "/" .. target, 24, 5, 3.2, "black")
        d.icon("clock", 84, 5, 6)
        d.text(tostring(math.ceil(s.time)), 93, 5, 3.6, "black")
        for i = 1, s.dyn do d.icon("dynamite", 3 + i * 7, 14, 7) end
        for _, o in ipairs(s.objs) do
            d.icon(o.kind == "stone_s" and "stone" or o.kind, o.x, o.y, (o.kind == "diamond" and 3.4 or 2.5) * o.r)
        end
        local tx, ty = Core.tip(s)
        d.line(AX, AY, tx, ty, "black", 0.5)
        d.icon("hook", tx, ty + 1.5, 6)
        local ev = s.event
        if ev and ev.kind == "gain" and not s.over and not s.cleared then
            d.text("+" .. ev.value, AX, 27, 3.6, "black")
        end
        local mark = s.over and "retry" or s.cleared and "next" or paused and "play"
        if mark then
            d.rect(30, 52, 40, 26, "white")
            d.frame(30, 52, 40, 26, "black", 0.8)
            d.icon(mark, 50, 65, 20)
        end
    end

    --- 点画布：暂停/过关/失败时继续，否则放钩。
    function self.tap()
        if s.over then self.newGame() self.resume()
        elseif s.cleared then self.nextLevel() self.resume()
        elseif paused then self.resume() self.render()
        else self.fire() end
    end

    function self.tick()
        local r = Core.tick(s, ctx.rng)
        if s.over or s.cleared then finish() else arm() end
        self.render()
        return r
    end

    function self.pause()
        if paused then return end
        paused = true
        halt()
        persist()
    end

    function self.resume()
        if s.over or s.cleared or not paused then return end
        paused = false
        arm()
    end

    function self.toggle()
        if s.over or s.cleared then return end
        if paused then self.resume() else self.pause() end
        self.render()
    end

    function self.fire()
        if paused or not Core.fire(s) then return false end
        persist()
        self.render()
        return true
    end

    function self.blast()
        if paused or not Core.blast(s) then return false end
        persist()
        self.render()
        return true
    end

    function self.nextLevel()
        if Core.nextLevel(s, ctx.rng) then
            paused = true
            persist()
            self.render()
        end
    end

    function self.newGame(mode)
        halt()
        paused = true
        s = Core.fresh(ctx.rng, mode or (s and s.mode) or "normal")
        persist()
        self.render()
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.objs and saved.state.phase then
            s = saved.state
            paused = true
            self.render()
        else
            self.newGame("normal")
        end
    end

    function self.stop()
        if s and not s.over and not s.cleared then self.pause() else halt() end
    end

    self.state = function() return s end
    self.paused = function() return paused end
    return self
end

return M
