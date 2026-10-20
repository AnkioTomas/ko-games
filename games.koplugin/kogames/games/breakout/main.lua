--[[--
打砖块。顶部 7 行砖块、底部挡板、一个球。球每拍移动一段，内部按不超过 1 个单位的子步进逐步检测碰撞；
碰墙、砖块、挡板反弹，挡板上的击中位置决定反弹角度。3 条命，清空砖块进入下一关（图案不同、球速略增）。
--]]
local T = require("kogames.l10n")

local W, H = 100, 140
local COLS, ROWS, BW, BH, BY0 = 10, 7, 10, 5, 20
local PY, PH, PW = 126, 3, 20
local R = 1.5
local MAXANG = math.rad(60)
local INTERVAL = 0.2

local Core = { W = W, H = H, COLS = COLS, ROWS = ROWS, BW = BW, BH = BH, BY0 = BY0, PY = PY, PH = PH, PW = PW, R = R }

--- 关卡图案：循环 4 种
local PATTERNS = {
    function() return true end,
    function(r, c) return (r + c) % 2 == 0 end,
    function(r) return r % 2 == 1 end,
    function(r, c) return math.abs(c - 5.5) <= r - 0.5 end,
}

function Core.speedOf(level) return math.min(6 + 0.7 * (level - 1), 11) end

function Core.layout(level)
    local f = PATTERNS[(level - 1) % #PATTERNS + 1]
    local b = {}
    for r = 1, ROWS do for c = 1, COLS do b[(r - 1) * COLS + c] = f(r, c) and 1 or 0 end end
    return b
end

function Core.remaining(s)
    local n = 0
    for _, v in ipairs(s.bricks) do n = n + v end
    return n
end

local function park(s)
    s.stuck = true
    s.bx, s.by, s.vx, s.vy = s.px + PW / 2, PY - R, 0, 0
end

function Core.fresh(level)
    level = level or 1
    local s = { level = level, bricks = Core.layout(level), px = 40, lives = 3, score = 0, over = false }
    park(s)
    return s
end

function Core.nextLevel(s)
    s.level = s.level + 1
    s.bricks = Core.layout(s.level)
    park(s)
end

--- 挡板瞬移，整格吸附，球在挡板上时跟随
function Core.movePaddle(s, x)
    s.px = math.max(0, math.min(W - PW, math.floor(x + 0.5)))
    if s.stuck then s.bx = s.px + PW / 2 end
end

function Core.shiftPaddle(s, dx) Core.movePaddle(s, s.px + dx) end

--- 发球
function Core.serve(s, rng)
    if not s.stuck or s.over then return false end
    local ang = math.rad(rng:int(41) - 21)
    local sp = Core.speedOf(s.level)
    s.vx, s.vy = sp * math.sin(ang), -sp * math.cos(ang)
    s.stuck = false
    return true
end

local function brickAt(s, x, y)
    local c, r = math.floor(x / BW) + 1, math.floor((y - BY0) / BH) + 1
    if c < 1 or c > COLS or r < 1 or r > ROWS then return nil end
    local i = (r - 1) * COLS + c
    if s.bricks[i] == 1 then return i, r end
end

local function sgn(v) return v < 0 and -1 or 1 end

local function hitBrick(s, i, r)
    s.bricks[i] = 0
    s.score = s.score + (ROWS - r + 1)
    return "brick"
end

--- 前进一拍，返回事件列表；末项可能是 "lost" | "over" | "clear"
function Core.step(s)
    local ev = {}
    if s.over or s.stuck then return ev end
    local n = math.max(1, math.ceil(math.max(math.abs(s.vx), math.abs(s.vy))))
    local dx, dy = s.vx / n, s.vy / n
    for _ = 1, n do
        s.bx = s.bx + dx
        if s.bx < R then s.bx = R s.vx, dx = -s.vx, -dx ev[#ev + 1] = "wall"
        elseif s.bx > W - R then s.bx = W - R s.vx, dx = -s.vx, -dx ev[#ev + 1] = "wall" end
        local i, r = brickAt(s, s.bx + sgn(dx) * R, s.by)
        if i then
            ev[#ev + 1] = hitBrick(s, i, r)
            s.vx, dx = -s.vx, -dx
            s.bx = s.bx + dx
        end
        s.by = s.by + dy
        if s.by < R then s.by = R s.vy, dy = -s.vy, -dy ev[#ev + 1] = "wall" end
        i, r = brickAt(s, s.bx, s.by + sgn(dy) * R)
        if i then
            ev[#ev + 1] = hitBrick(s, i, r)
            s.vy, dy = -s.vy, -dy
            s.by = s.by + dy
        end
        if dy > 0 and s.by + R >= PY and s.by - dy + R <= PY + 0.01 and s.by - R <= PY + PH
            and s.bx >= s.px - R and s.bx <= s.px + PW + R then
            local t = math.max(-1, math.min(1, (s.bx - (s.px + PW / 2)) / (PW / 2 + R)))
            local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy)
            local ang = t * MAXANG
            s.vx, s.vy = sp * math.sin(ang), -sp * math.cos(ang)
            dx, dy = s.vx / n, s.vy / n
            s.by = PY - R
            ev[#ev + 1] = "paddle"
        end
        if Core.remaining(s) == 0 then
            ev[#ev + 1] = "clear"
            return ev
        end
        if s.by - R > H then
            s.lives = s.lives - 1
            if s.lives <= 0 then s.over = true ev[#ev + 1] = "over" else park(s) ev[#ev + 1] = "lost" end
            return ev
        end
    end
    return ev
end

local M = { id = "breakout", title = T("打砖块"), icon = "timeline", tier = "C",
    desc = T("接球打砖块，清空过关"), core = Core, INTERVAL = INTERVAL,
    help = T("用底部挡板接住小球，把上面的砖块全部打掉。\n点画布任意位置，挡板会瞬移到那里。\n球落到底部扣 1 条命（共 3 条），打中挡板中间会垂直弹起，越靠边角度越斜。\n球在挡板上时点画布即发球；暂停、重来在右上角设置里。清空砖块进入下一关，图案不同、球速略快。") }

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
        handle = ctx.host:schedule(INTERVAL, function()
            if mine ~= token or paused or s.over then return end
            handle = nil
            self.tick()
        end)
    end

    local SHADE = { "black", "dark", "grey" }

    local function draw(d)
        d.frame(0, 0, W, H, "black", 0.8)
        for i = 1, s.lives do d.icon("heart", 5 + (i - 1) * 6, 8, 5) end
        d.text(tostring(s.score), 56, 8, 5, "black")
        d.text(tostring(s.level), 90, 8, 5, "dark")
        for r = 1, ROWS do
            local shade = SHADE[(r - 1) % #SHADE + 1]
            for c = 1, COLS do
                if s.bricks[(r - 1) * COLS + c] == 1 then
                    local x, y = (c - 1) * BW, BY0 + (r - 1) * BH
                    d.rect(x + 0.5, y + 0.5, BW - 1, BH - 1, shade)
                    d.frame(x + 0.5, y + 0.5, BW - 1, BH - 1, "black", 0.6)
                end
            end
        end
        d.icon("paddle", s.px + PW / 2, PY + PH / 2, PW)
        d.icon("ball", s.bx, s.by, 2 * R + 1)
        if s.over then
            d.rect(20, 76, 60, 24, "white")
            d.frame(20, 76, 60, 24, "black", 1)
            d.text(T("游戏结束"), W / 2, 88, 5, "black")
        elseif s.stuck then
            d.icon("serve", s.bx, PY - 14, 8)
        end
    end

    function self.render()
        ctx:render({
            title = T("打砖块"),
            canvas = { w = W, h = H, draw = draw, on_tap = function(x) self.moveTo(x) end },
            settings = { reset = function() self.newGame() end, groups = {} },
            buttons = { {
                { menu = true, enabled = not s.over and not s.stuck, text = paused and T("继续") or T("暂停"),
                    callback = function() self.toggle() end },
                { menu = true, text = T("重来"), callback = function() self.newGame() end },
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
        local ev = Core.step(s)
        local last = ev[#ev]
        if last == "over" then self.finish()
        elseif last == "lost" then
            halt()
            paused = true
            persist()
        elseif last == "clear" then
            Core.nextLevel(s)
            halt()
            paused = true
            persist()
            ctx:notify(T("过关！第 %d 关", s.level))
        else arm() end
        self.render()
        return ev
    end

    function self.moveTo(x)
        if s.over then return end
        Core.movePaddle(s, x - PW / 2)
        if s.stuck then
            Core.serve(s, ctx.rng)
            paused = false
            arm()
        elseif paused then
            paused = false
            arm()
        end
        self.render()
    end

    function self.toggle()
        if s.over then return end
        if s.stuck then
            Core.serve(s, ctx.rng)
            paused = false
            arm()
        elseif paused then
            paused = false
            arm()
        else
            self.pause()
        end
        self.render()
    end

    function self.pause()
        if paused then return end
        paused = true
        halt()
        persist()
    end

    function self.newGame()
        halt()
        s, paused = Core.fresh(1), true
        persist()
        self.render()
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.bricks and not saved.state.over then s = saved.state
        else s = Core.fresh(1) end
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
