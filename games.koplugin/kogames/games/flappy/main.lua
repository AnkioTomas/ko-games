--[[--
像素鸟。小鸟固定在左侧，点画布向上冲，每一拍受重力下落；绿管（黑/灰矩形）从右向左移动，
每穿过一对得 1 分，碰管、落地或飞出顶部则结束。相邻两管的缺口中心落差有上限，保证一定可通过。
--]]
local T = require("kogames.l10n")

local W, H, GROUND = 100, 140, 124
local BIRD_X, BIRD_R = 30, 4
local PIPE_W, SPACING = 14, 52
local GRAVITY, MAXV, FLAP = 2, 6, -7
local MAX_SHIFT, MARGIN = 18, 12
local LEVELS = {
    { gap = 52, speed = 6 },
    { gap = 44, speed = 7 },
    { gap = 38, speed = 8 },
}
local INTERVAL = 0.22

local Core = { W = W, H = H, GROUND = GROUND, BIRD_X = BIRD_X, BIRD_R = BIRD_R, PIPE_W = PIPE_W,
    SPACING = SPACING, MAX_SHIFT = MAX_SHIFT, LEVELS = LEVELS }

local function nextCenter(prev, gap, rng)
    local lo, hi = MARGIN + gap / 2, GROUND - MARGIN - gap / 2
    local c = prev + rng:int(2 * MAX_SHIFT + 1) - MAX_SHIFT - 1
    return math.max(lo, math.min(hi, c))
end

local function addPipe(s, x, rng)
    local prev = s.pipes[#s.pipes]
    local c = nextCenter(prev and prev.cy or GROUND / 2, s.gap, rng)
    s.pipes[#s.pipes + 1] = { x = x, cy = c }
end

function Core.fresh(rng, level)
    local lv = LEVELS[level] or LEVELS[2]
    local s = { level = level or 2, gap = lv.gap, speed = lv.speed, y = 60, vy = 0,
        pipes = {}, score = 0, over = false, ticks = 0 }
    addPipe(s, W + 10, rng)
    return s
end

--- 小鸟向上冲
function Core.flap(s)
    if s.over then return false end
    s.vy = FLAP
    return true
end

local function hits(s, p)
    if BIRD_X + BIRD_R <= p.x or BIRD_X - BIRD_R >= p.x + PIPE_W then return false end
    return s.y - BIRD_R < p.cy - s.gap / 2 or s.y + BIRD_R > p.cy + s.gap / 2
end

--- 前进一拍，返回 "move" | "score" | "dead"
function Core.step(s, rng)
    if s.over then return "dead" end
    s.ticks = s.ticks + 1
    s.vy = math.min(s.vy + GRAVITY, MAXV)
    s.y = s.y + s.vy
    for _, p in ipairs(s.pipes) do p.x = p.x - s.speed end
    if s.pipes[1].x + PIPE_W < 0 then table.remove(s.pipes, 1) end
    if s.pipes[#s.pipes].x <= W + 10 - SPACING then addPipe(s, s.pipes[#s.pipes].x + SPACING, rng) end
    if s.y - BIRD_R < 0 or s.y + BIRD_R >= GROUND then s.over = true return "dead" end
    local got = false
    for _, p in ipairs(s.pipes) do
        if hits(s, p) then s.over = true return "dead" end
        if not p.passed and p.x + PIPE_W < BIRD_X - BIRD_R then
            p.passed, got = true, true
            s.score = s.score + 1
        end
    end
    return got and "score" or "move"
end

local M = { id = "flappy", title = T("像素鸟"), icon = "timeline", tier = "C",
    desc = T("点一下拍翅膀，穿过绿管"), core = Core, INTERVAL = INTERVAL,
    help = T("小鸟会不断下落，点一下屏幕让它向上冲，穿过上下两根绿管之间的缺口。\n每穿过一对管子得 1 分；碰到管子、落到地面或飞出顶部则游戏结束。\n点屏幕开始；结束后点屏幕重来。暂停、新游戏和难度（缺口越小、速度越快越难）都在设置里。\n墨水屏每一拍刷新一次，请预判下一拍的位置。") }

function M.new(ctx)
    local self = {}
    local s, level, paused, started, handle, token = nil, 2, true, false, nil, 0

    local function persist() ctx:save({ state = s, level = level, started = started }) end

    local function halt()
        token = token + 1
        if handle then ctx.host:unschedule(handle) handle = nil end
    end

    local function arm()
        halt()
        local mine = token
        handle = ctx.host:schedule(INTERVAL, function()
            if mine ~= token or paused or s.over then return end
            handle = nil
            self.tick()
        end)
    end

    local function draw(d)
        d.frame(0, 0, W, H, "black", 0.8)
        for i, cy in ipairs({ 30, 60, 90 }) do
            d.icon("cloud", (i * 53 - s.ticks * 1.5) % 130 - 15, cy, 14)
        end
        d.rect(0, GROUND, W, H - GROUND, "black")
        d.rect(0, GROUND, W, 2, "dark")
        for _, p in ipairs(s.pipes) do
            local x0, x1 = math.max(0, p.x), math.min(W, p.x + PIPE_W)
            if x1 > x0 then
                local top, bot = p.cy - s.gap / 2, p.cy + s.gap / 2
                d.rect(x0, 0, x1 - x0, top, "dark")
                d.frame(x0, 0, x1 - x0, top, "black", 1)
                d.rect(x0, bot, x1 - x0, GROUND - bot, "dark")
                d.frame(x0, bot, x1 - x0, GROUND - bot, "black", 1)
                d.rect(x0, top - 4, x1 - x0, 4, "black")
                d.rect(x0, bot, x1 - x0, 4, "black")
            end
        end
        local y = s.y
        d.icon(s.vy < 0 and "bird_up" or "bird_down", BIRD_X, y, 14)
        d.text(tostring(s.score), W / 2, 14, 9, "black")
        if s.over then
            d.rect(34, 52, 32, 24, "white")
            d.frame(34, 52, 32, 24, "black", 1)
            d.icon("restart", W / 2, 64, 16)
        end
    end

    function self.render()
        local lv = {}
        for n, name in ipairs({ T("简单"), T("普通"), T("困难") }) do
            lv[#lv + 1] = { text = name, selected = n == level, callback = function() self.setLevel(n) end }
        end
        ctx:render({
            title = T("像素鸟"),
            canvas = { w = W, h = H, draw = draw, on_tap = function() self.tap() end },
            settings = { groups = { { label = T("难度"), options = lv } }, reset = function() self.newGame() end },
            buttons = { {
                { menu = true, text = paused and started and not s.over and T("继续") or T("暂停"),
                  enabled = started and not s.over, callback = function() self.toggle() end },
                { menu = true, text = T("新游戏"), callback = function() self.newGame() end },
            } },
        })
    end

    function self.finish()
        halt()
        paused = true
        if ctx:record("best", s.score) and s.score > 0 then ctx:notify(T("新纪录：%d", s.score)) end
        persist()
    end

    function self.tick()
        local r = Core.step(s, ctx.rng)
        if s.over then self.finish() else arm() end
        self.render()
        return r
    end

    function self.tap()
        if s.over then self.newGame() return end
        Core.flap(s)
        if paused then
            paused, started = false, true
            arm()
            self.render()
        end
    end

    function self.pause()
        if paused then return end
        paused = true
        halt()
        persist()
    end

    function self.toggle()
        if s.over or not started then return end
        if paused then paused = false arm() else self.pause() end
        self.render()
    end

    function self.setLevel(n)
        level = n
        self.newGame()
    end

    function self.newGame()
        halt()
        s, paused, started = Core.fresh(ctx.rng, level), true, false
        persist()
        self.render()
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.pipes and #saved.state.pipes > 0 and not saved.state.over then
            s, level, started = saved.state, saved.level or 2, saved.started or false
            if not LEVELS[level] then level = 2 end
        else
            if saved and LEVELS[saved.level or 0] then level = saved.level end
            s = Core.fresh(ctx.rng, level)
        end
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
