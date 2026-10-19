--[[--
小恐龙跳跳（Chrome 断网小游戏）。定时一拍一拍前进：点画布跳起，向下滑蹲躲翼龙；
世界每拍向左移动 1→2→3 格，障碍间距始终大于一次跳跃所需距离。
--]]
local T = require("kogames.l10n")

local WORLD = 30            -- 可见列数
local DX = 3                -- 恐龙所在列（占 DX、DX+1 两列）
local AIR = 5               -- 一次跳跃滞空拍数
local VY0, GRAV = 5, 2      -- 起跳初速与每拍重力：高度 5,8,9,8,5,0
local DINO_H, DUCK_H = 4, 2
local DUCK_TICKS = 2
local INTERVALS = { 0.34, 0.28, 0.24 }
local EXTRA = { { 4, 10 }, { 2, 7 }, { 0, 4 } } -- 休闲/标准/困难：额外间距范围（列）
local PTERO_FROM = 300      -- 分数到达后才出翼龙
local PTERO_BY = { 1, 3, 6 } -- 翼龙底边高度：低（必须跳）、中（蹲或跳）、高（直接跑过）

local Core = {}

--- 世界每拍移动的格数
function Core.speed(score)
    if score >= 600 then return 3 end
    if score >= 200 then return 2 end
    return 1
end

--- 一个障碍之后下一个障碍至少要隔多少列
function Core.minGap(sp)
    return (AIR + 1) * sp + 3
end

function Core.fresh(rng, level)
    level = INTERVALS[level or 2] and (level or 2) or 2
    return { level = level, dist = 0, y = 0, vy = 0, duck = 0, jumpReq = false, duckReq = false,
        obs = {}, clouds = { { x = 8, y = 14 }, { x = 22, y = 24 } }, ticks = 0, over = false, flash = 0,
        nextX = 24 }
end

function Core.height(s) return s.duck > 0 and DUCK_H or DINO_H end

function Core.jump(s)
    if s.over or s.y > 0 then return false end
    s.jumpReq, s.duckReq = true, false
    return true
end

function Core.duck(s)
    if s.over or s.y > 0 then return false end
    s.duckReq = true
    return true
end

local function hits(s, o)
    if o.x > DX + 1 or o.x + o.w - 1 < DX then return false end
    local top = s.y + Core.height(s) - 1
    if o.kind == "ptero" then return s.y <= o.by + 1 and top >= o.by end
    return s.y < o.h
end

local function spawn(s, rng)
    local sp = Core.speed(s.dist + WORLD)
    local r = rng:int(100)
    local o
    if s.dist >= PTERO_FROM and r <= 25 then
        o = { kind = "ptero", w = 2, h = 2, by = PTERO_BY[rng:int(#PTERO_BY)] }
    elseif r <= 60 then o = { kind = "small", w = 1, h = 3 }
    elseif r <= 85 or sp < 2 then o = { kind = "big", w = 2, h = 4 }
    else o = { kind = "group", w = 3, h = 3 } end
    local ex = EXTRA[s.level]
    o.x = s.nextX
    s.obs[#s.obs + 1] = o
    s.nextX = o.x + o.w + Core.minGap(sp) + ex[1] + rng:int(ex[2] - ex[1] + 1) - 1
end

--- 前进一拍：返回 "run" | "milestone" | "dead"
function Core.step(s, rng)
    if s.over then return "dead" end
    s.ticks = s.ticks + 1
    if s.y > 0 or s.jumpReq then
        if s.y == 0 then s.vy = VY0 end
        s.y = math.max(0, s.y + s.vy)
        s.vy = s.vy - GRAV
        if s.y == 0 then s.vy = 0 end
        s.duck = 0
    elseif s.duckReq then
        s.duck = DUCK_TICKS
    end
    s.jumpReq, s.duckReq = false, false

    local sp = Core.speed(s.dist)
    local before = math.floor(s.dist / 100)
    for _ = 1, sp do
        for _, o in ipairs(s.obs) do
            o.x = o.x - 1
            if hits(s, o) then s.over = true end
        end
    end
    s.nextX = s.nextX - sp
    for i = #s.obs, 1, -1 do
        if s.obs[i].x + s.obs[i].w < 1 then table.remove(s.obs, i) end
    end
    if s.over then return "dead" end
    if s.duck > 0 then s.duck = s.duck - 1 end

    s.dist = s.dist + sp
    if s.nextX <= WORLD + 2 then spawn(s, rng) end
    for _, c in ipairs(s.clouds) do
        c.x = c.x - 1
        if c.x < -6 then c.x = WORLD + rng:int(10) c.y = 8 + rng:int(5) * 5 end
    end
    if s.flash > 0 then s.flash = s.flash - 1 end
    if math.floor(s.dist / 100) > before then s.flash = 3 return "milestone" end
    return "run"
end

-- 画面 ---------------------------------------------------------------------

local CW = 100 / WORLD      -- 每列宽（虚拟单位）
local RU = 3                -- 每行高
local GY = 72               -- 地面线
local DINO_SZ, PTERO_SZ, CLOUD_SZ = 14, 9, 10
local CACTUS_SZ = { small = 9, big = 12, group = 12 }

local function cactus(d, left, o)
    local sz = CACTUS_SZ[o.kind]
    d.icon("cactus_" .. o.kind, left + o.w * CW / 2, GY - sz / 2, sz)
end

local function ptero(d, left, by, flap)
    d.icon(flap and "ptero1" or "ptero2", left + CW, GY - by * RU - 3, PTERO_SZ)
end

local function pad5(n) return ("%05d"):format(math.min(n, 99999)) end

function Core.draw(s, d, hi)
    d.rect(0, GY + 1, 100, 0.6, "black")
    for c = 0, WORLD + 1 do
        local h = ((c + s.dist) * 37 + 11) % 13
        if h == 0 then d.rect(c * CW, GY + 3, 1.6, 0.6, "dark")
        elseif h == 5 then d.rect(c * CW, GY + 5.5, 3, 0.6, "dark")
        elseif h == 9 then d.rect(c * CW, GY + 2, 1, 0.6, "dark") end
    end
    for _, c in ipairs(s.clouds) do d.icon("cloud", c.x * CW + CLOUD_SZ / 2, c.y, CLOUD_SZ) end
    local flap = s.ticks % 2 == 0
    for _, o in ipairs(s.obs) do
        local left = (o.x - 1) * CW
        if o.kind == "ptero" then ptero(d, left, o.by, flap)
        else cactus(d, left, o) end
    end
    local name
    if s.over then name = "dino_dead"
    elseif s.duck > 0 then name = flap and "dino_duck1" or "dino_duck2"
    elseif s.y > 0 then name = "dino_jump"
    else name = flap and "dino_run1" or "dino_run2" end
    d.icon(name, DX * CW + CW - 1, GY - s.y * RU - DINO_SZ / 2 + 0.6, DINO_SZ)
    if s.flash > 0 and s.flash % 2 == 0 then
        d.text(pad5(hi or 0), 86, 8, 3.6, "grey")
    else
        d.text(pad5(hi or 0), 62, 8, 3.6, "grey")
        d.text(pad5(s.dist), 86, 8, 3.6, "black")
    end
end

local M = { id = "dino", title = T("小恐龙跳跳"), icon = "timeline", tier = "C",
    desc = T("跳过仙人掌，蹲过翼龙"), core = Core, INTERVALS = INTERVALS, WORLD = WORLD, DX = DX, AIR = AIR,
    help = T("小恐龙自动向前跑，障碍从右边冲来。\n点画布起跳（滞空约 5 拍），翼龙飞得低时可跳过，飞得居中时向下滑动蹲下（下一拍起蹲 2 拍）躲过，飞得高时直接跑过去。\n分数随距离增加，每 100 分提示一次，速度也会越来越快。撞上障碍就游戏结束。\n点画布开始；撞上后点画布重来。暂停、新游戏和难度（休闲 / 标准 / 困难）都在设置里。") }

function M.new(ctx)
    local self = {}
    local s, paused, handle, token = nil, true, nil, 0

    local function persist() ctx:save({ state = s }) end

    local function halt()
        token = token + 1
        if handle then ctx.host:unschedule(handle) handle = nil end
    end

    local function arm()
        halt()
        local mine = token
        handle = ctx.host:schedule(INTERVALS[s.level], function()
            if mine ~= token or paused or s.over then return end
            handle = nil
            self.tick()
        end)
    end

    local function hi() return math.max(ctx:best("best") or 0, s.dist) end

    function self.render()
        local fresh = s.dist == 0 and s.ticks == 0
        local lv = {}
        for n, name in ipairs({ T("休闲"), T("标准"), T("困难") }) do
            lv[#lv + 1] = { text = name, selected = n == s.level, callback = function() self.setLevel(n) end }
        end
        ctx:render({
            title = T("小恐龙跳跳"),
            canvas = {
                w = 100, h = 100,
                draw = function(d)
                    Core.draw(s, d, hi())
                    if s.over then d.icon("restart", 50, 42, 16) end
                end,
                on_tap = function()
                    if s.over then self.newGame() else self.jump() end
                end,
            },
            on_swipe = function(dir)
                if dir == "south" then self.duck() elseif dir == "north" then self.jump() end
            end,
            settings = { groups = { { label = T("难度"), options = lv } }, reset = function() self.newGame() end },
            buttons = {
                {
                    { menu = true, text = paused and not s.over and (fresh and T("开始") or T("继续")) or T("暂停"),
                      enabled = not s.over, callback = function() self.toggle() end },
                    { menu = true, text = T("新游戏"), callback = function() self.newGame() end },
                },
            },
        })
    end

    function self.finish()
        halt()
        paused = true
        if ctx:record("best", s.dist) and s.dist > 0 then ctx:notify(T("新纪录：%d", s.dist)) end
        persist()
    end

    function self.tick()
        local r = Core.step(s, ctx.rng)
        if s.over then self.finish() else arm() end
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
        if s.over or not paused then return end
        paused = false
        arm()
    end

    function self.toggle()
        if s.over then return end
        if paused then self.resume() else self.pause() end
        self.render()
    end

    function self.jump()
        if s.over then return end
        Core.jump(s)
        if paused then self.resume() end
        self.render()
    end

    function self.duck()
        if s.over then return end
        Core.duck(s)
        if paused then self.resume() end
        self.render()
    end

    function self.setLevel(n)
        if not INTERVALS[n] then return end
        s.level = n
        if not paused and not s.over then arm() end
        persist()
        self.render()
    end

    function self.newGame()
        halt()
        s, paused = Core.fresh(ctx.rng, s and s.level), true
        persist()
        self.render()
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.obs and INTERVALS[saved.state.level] then
            s = saved.state
        else s = Core.fresh(ctx.rng) end
        paused = true
        self.render()
    end

    function self.stop()
        if s and not s.over then self.pause() else halt() end
    end

    self.state = function() return s end
    self.paused = function() return paused end
    return self
end

return M
