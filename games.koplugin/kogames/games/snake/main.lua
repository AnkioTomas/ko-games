--[[--
贪吃蛇。定时前进，滑动或方向按钮转向；可调速度、暂停；只在每一拍/操作时刷新。
--]]
local T = require("kogames.l10n")

local W, H = 12, 16
local INTERVALS = { 1.0, 0.9, 0.8, 0.7, 0.6 }
local VEC = { north = { -1, 0 }, south = { 1, 0 }, west = { 0, -1 }, east = { 0, 1 } }
local OPPOSITE = { north = "south", south = "north", west = "east", east = "west" }

local Core = {}

function Core.placeFood(s, rng)
    local used = {}
    for _, p in ipairs(s.body) do used[(p[1] - 1) * s.w + p[2]] = true end
    local free = {}
    for i = 1, s.w * s.h do if not used[i] then free[#free + 1] = i end end
    if #free == 0 then s.food = nil return end
    local i = free[rng:int(#free)]
    s.food = { math.floor((i - 1) / s.w) + 1, (i - 1) % s.w + 1 }
end

function Core.fresh(rng, w, h)
    w, h = w or W, h or H
    local r, c = math.floor(h / 2), math.floor(w / 2)
    local s = { w = w, h = h, body = { { r, c }, { r, c - 1 }, { r, c - 2 } },
        dir = "east", moved = "east", score = 0, over = false, won = false }
    Core.placeFood(s, rng)
    return s
end

--- 记录下一步方向；不能直接掉头。
function Core.turn(s, dir)
    if not VEC[dir] or dir == OPPOSITE[s.moved] then return false end
    s.dir = dir
    return true
end

--- 前进一步，返回 "move" | "eat" | "dead" | "win"
function Core.step(s, rng)
    if s.over then return "dead" end
    local v = VEC[s.dir]
    local head = s.body[1]
    local nr, nc = head[1] + v[1], head[2] + v[2]
    if nr < 1 or nr > s.h or nc < 1 or nc > s.w then s.over = true return "dead" end
    local eat = s.food and s.food[1] == nr and s.food[2] == nc
    local last = #s.body
    for i = 1, eat and last or last - 1 do -- 不吃食物时尾巴会让出，可以追尾
        local p = s.body[i]
        if p[1] == nr and p[2] == nc then s.over = true return "dead" end
    end
    table.insert(s.body, 1, { nr, nc })
    s.moved = s.dir
    if eat then
        s.score = s.score + 1
        Core.placeFood(s, rng)
        if not s.food then s.over, s.won = true, true return "win" end
        return "eat"
    end
    table.remove(s.body)
    return "move"
end

local M = { id = "snake", title = T("贪吃蛇"), icon = "timeline", tier = "C",
    desc = T("吃苹果，别撞墙"), core = Core, INTERVALS = INTERVALS,
    help = T("蛇会自动向前爬，滑动屏幕或点方向按钮控制转向，不能直接掉头。\n吃到苹果身体变长、得 1 分；撞到边界或自己的身体则游戏结束。\n点「开始」或任意方向开始，随时可暂停；可在设置中选择速度（越大越快）。\n墨水屏每一拍都会刷新一次，建议用较慢的速度。") }

function M.new(ctx)
    local self = {}
    local s, speed, paused, handle, token = nil, 2, true, nil, 0

    local function persist() ctx:save({ state = s, speed = speed }) end

    local function halt()
        token = token + 1
        if handle then ctx.host:unschedule(handle) handle = nil end
    end

    local function arm()
        halt()
        local mine = token
        handle = ctx.host:schedule(INTERVALS[speed], function()
            if mine ~= token or paused or s.over then return end
            handle = nil
            self.tick()
        end)
    end

    function self.render()
        local best = math.max(ctx:best("best") or 0, s.score)
        local status = (T("得分 %d    最高 %d")):format(s.score, best)
        if s.over then status = status .. (s.won and T("    通关！") or T("    游戏结束"))
        elseif paused then status = status .. T("    已暂停") end
        local cells = {}
        for i, p in ipairs(s.body) do cells[(p[1] - 1) * s.w + p[2]] = i == 1 and "head" or "body" end
        local sp = {}
        for n = 1, #INTERVALS do
            sp[#sp + 1] = { text = tostring(n), selected = n == speed, callback = function() self.setSpeed(n) end }
        end
        ctx:render({
            title = T("贪吃蛇"),
            status = status,
            grid = {
                rows = s.h, cols = s.w, gap = true, slots = true,
                cell = function(r, c)
                    local k = cells[(r - 1) * s.w + c]
                    if k == "head" then return { fill = "black", mark = "white" } end
                    if k == "body" then return { fill = "dark" } end
                    if s.food and s.food[1] == r and s.food[2] == c then return { icon = "apple", icon_scale = 0.8 } end
                end,
            },
            on_swipe = function(d) self.input(d) end,
            settings = { groups = { { label = T("速度"), options = sp } }, reset = function() self.newGame() end },
            buttons = {
                {
                    { text = "←", callback = function() self.input("west") end },
                    { text = "↑", callback = function() self.input("north") end },
                    { text = "↓", callback = function() self.input("south") end },
                    { text = "→", callback = function() self.input("east") end },
                },
                { { text = s.over and T("再来一局") or (paused and (s.score == 0 and #s.body == 3 and T("开始") or T("继续")) or T("暂停")),
                    callback = s.over and function() self.newGame() end or function() self.toggle() end },
                  { menu = true, text = T("新游戏"), callback = function() self.newGame() end } },
            },
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

    function self.input(dir)
        if s.over then return end
        local was = paused
        if Core.turn(s, dir) and was then self.resume() self.render() end
    end

    function self.setSpeed(n)
        speed = n
        if not paused and not s.over then arm() end
        persist()
        self.render()
    end

    function self.newGame()
        halt()
        s, paused = Core.fresh(ctx.rng), true
        persist()
        self.render()
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.body then
            s, speed = saved.state, saved.speed or 2
            if not INTERVALS[speed] then speed = 2 end
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
