--[[--
跳跳冒险（横版闯关）。每一拍按格推进：方向键粘性，每拍走一格；跳跃上升 3 格、滞空约 5 拍。
关卡为字符地图：# 地面  B 砖  ? 问号砖  X 空砖  P 水管  o 金币  g 栗子怪  S 出生点  F 旗杆
--]]
local T = require("kogames.l10n")
local LEVELS = require("kogames.games.mario.levels")

local COLS, ROWS, TILE = 9, 9, 8
local INTERVAL = 0.3
local SOLID = { ["#"] = true, B = true, ["?"] = true, X = true, P = true }
local LIVES = 3

local Core = { LEVELS = LEVELS, COLS = COLS, ROWS = ROWS }

function Core.width(s) return #s.map[1] end

function Core.at(s, x, y)
    if x < 1 or x > #s.map[1] then return "#" end
    if y < 1 then return "#" end
    if y > ROWS then return " " end
    return s.map[y]:sub(x, x)
end

function Core.solid(s, x, y) return SOLID[Core.at(s, x, y)] == true end

local function setTile(s, x, y, ch)
    local row = s.map[y]
    s.map[y] = row:sub(1, x - 1) .. ch .. row:sub(x + 1)
end

function Core.loadLevel(s, n)
    s.level = n
    s.map, s.enemies = {}, {}
    local sx, sy = 2, ROWS - 2
    for y, row in ipairs(LEVELS[n]) do
        for x = 1, #row do
            local ch = row:sub(x, x)
            if ch == "g" then s.enemies[#s.enemies + 1] = { x = x, y = y, d = -1 }
            elseif ch == "S" then sx, sy = x, y end
        end
        s.map[y] = (row:gsub("[gS]", " "))
    end
    s.x, s.y, s.vy, s.dir = sx, sy, 0, 0
    s.jump, s.grounded, s.t = false, true, 0
end

function Core.fresh()
    local s = { lives = LIVES, score = 0, coins = 0, over = false, won = false, msg = "" }
    Core.loadLevel(s, 1)
    return s
end

local function enemyAt(s, x, y)
    for i, e in ipairs(s.enemies) do
        if e.x == x and e.y == y then return i end
    end
end

function Core.setDir(s, d) s.dir = d end
function Core.requestJump(s) s.jump = true end

local function die(s)
    s.lives = s.lives - 1
    s.msg = "dead"
    if s.lives <= 0 then s.over = true return "over" end
    Core.loadLevel(s, s.level)
    return "dead"
end

local function collect(s)
    local ch = Core.at(s, s.x, s.y)
    if ch == "o" then
        setTile(s, s.x, s.y, " ")
        s.coins, s.score = s.coins + 1, s.score + 50
    elseif ch == "F" then
        s.score = s.score + 1000 + (ROWS - s.y) * 100
        s.msg = "clear"
        if s.level >= #LEVELS then s.won, s.over = true, true return "win" end
        Core.loadLevel(s, s.level + 1)
        return "clear"
    end
end

local function bump(s, x, y)
    if Core.at(s, x, y) == "?" then
        setTile(s, x, y, "X")
        s.coins, s.score = s.coins + 1, s.score + 100
    end
    local i = enemyAt(s, x, y - 1)
    if i then table.remove(s.enemies, i) s.score = s.score + 100 end
end

--- 推进一拍，返回 nil | "dead" | "over" | "clear" | "win"
function Core.step(s)
    if s.over then return "over" end
    s.t = s.t + 1
    s.msg = ""
    local r
    if s.dir ~= 0 and not Core.solid(s, s.x + s.dir, s.y) then s.x = s.x + s.dir end
    r = collect(s)
    if r then return r end
    if enemyAt(s, s.x, s.y) then return die(s) end

    if s.jump and s.grounded then s.vy, s.grounded = 2, false end
    s.jump = false
    if s.grounded and not Core.solid(s, s.x, s.y + 1) then s.grounded, s.vy = false, -1 end

    if not s.grounded then
        local dy = s.vy
        s.vy = math.max(s.vy - 1, -2)
        if dy > 0 then
            for _ = 1, dy do
                if Core.solid(s, s.x, s.y - 1) then
                    bump(s, s.x, s.y - 1)
                    s.vy = -1
                    break
                end
                s.y = s.y - 1
                r = collect(s)
                if r then return r end
            end
        elseif dy < 0 then
            for _ = 1, -dy do
                local i = enemyAt(s, s.x, s.y + 1)
                if i then
                    table.remove(s.enemies, i)
                    s.score = s.score + 100
                    s.vy = 1
                    break
                end
                if Core.solid(s, s.x, s.y + 1) then
                    s.grounded, s.vy = true, 0
                    break
                end
                s.y = s.y + 1
                if s.y > ROWS then return die(s) end
                r = collect(s)
                if r then return r end
            end
            if s.vy <= 0 and Core.solid(s, s.x, s.y + 1) then s.grounded, s.vy = true, 0 end
        end
        if enemyAt(s, s.x, s.y) then return die(s) end
    end

    if s.t % 2 == 0 then
        for _, e in ipairs(s.enemies) do
            local nx = e.x + e.d
            if Core.solid(s, nx, e.y) or not Core.solid(s, nx, e.y + 1) or enemyAt(s, nx, e.y) then
                e.d = -e.d
            else
                e.x = nx
            end
        end
        if enemyAt(s, s.x, s.y) then return die(s) end
    end
end

local M = { id = "mario", title = T("跳跳冒险"), icon = "timeline", tier = "C",
    desc = T("横版闯关，跳过坑和敌人"), core = Core, INTERVAL = INTERVAL,
    help = T("横版闯关：到达终点旗杆即过关，共 3 关。\n点 ◀ ▶ 后角色每拍自动朝该方向走一格，再点同一方向就站住；点 ↑ 起跳（上升 3 格，滞空时可前进）。\n也可以点画面：左边 = 向左，右边 = 向右，中间 = 跳。暂停、继续、新游戏在右上角设置里。\n顶问号砖得金币；踩敌人头顶可消灭，从侧面碰到会失去一条命；掉进坑里也会失去一条命，共 3 条命。") }

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

    local function camera()
        local w = Core.width(s)
        return math.max(1, math.min(w - COLS + 1, s.x - 3))
    end

    local face = 1

    local function drawTile(d, ch, x, y, above)
        local cx, cy = x + TILE / 2, y + TILE / 2
        if ch == "#" then d.icon(above == "#" and "dirt" or "ground", cx, cy, TILE)
        elseif ch == "B" then d.icon("brick", cx, cy, TILE)
        elseif ch == "?" then d.icon("qblock", cx, cy, TILE)
        elseif ch == "X" then d.icon("qblock_used", cx, cy, TILE)
        elseif ch == "P" then d.icon(above == "P" and "pipe_body" or "pipe_top", cx, cy, TILE)
        elseif ch == "o" then d.icon("coin", cx, cy, TILE)
        elseif ch == "F" then d.icon(above == "F" and "flag_pole" or "flag_top", cx, cy, TILE)
        end
    end

    local function drawBackdrop(d, cx)
        local span = 24 * TILE
        for k = 0, 3 do
            local hx = ((k * 17 + 3) * TILE - (cx - 1) * TILE * 0.5) % (span * 2) - TILE * 3
            d.icon("cloud", hx, TILE * (2.5 + k % 2), TILE * 2)
        end
        for k = 0, math.floor(Core.width(s) / 18) do
            local hx = (k * 18 + 8 - cx + 1.5) * TILE
            if hx > -TILE * 2 and hx < (COLS + 2) * TILE then d.icon("hill", hx, (ROWS - 2) * TILE - TILE * 1.5, TILE * 3) end
        end
    end

    local function drawHud(d)
        for i = 1, s.lives do d.icon("heart", TILE * 0.7 + (i - 1) * TILE * 0.6, TILE * 0.55, TILE * 0.5) end
        d.icon("coin_hud", TILE * 3.9, TILE * 0.55, TILE * 0.55)
        d.text(tostring(s.coins), TILE * 4.6, TILE * 0.55, TILE * 0.45, "black")
        d.text(tostring(s.score), COLS * TILE - TILE * 0.4, TILE * 0.55, TILE * 0.45, "black")
        d.text(tostring(s.level), TILE * 6.4, TILE * 0.55, TILE * 0.45, "dark")
    end

    local function drawZones(d)
        local W, y0 = COLS * TILE, TILE * 1.2
        d.line(W / 3, y0, W / 3, y0 + TILE, "grey", 0.5)
        d.line(W * 2 / 3, y0, W * 2 / 3, y0 + TILE, "grey", 0.5)
        d.icon("left", W / 6, y0 + TILE / 2, TILE * 0.6)
        d.icon("jump", W / 2, y0 + TILE / 2, TILE * 0.6)
        d.icon("right", W * 5 / 6, y0 + TILE / 2, TILE * 0.6)
    end

    local function draw(d)
        local cx = camera()
        d.rect(0, 0, COLS * TILE, ROWS * TILE, "white")
        drawBackdrop(d, cx)
        local fx, fy
        for r = 1, ROWS do
            for c = 1, COLS do
                local mx = cx + c - 1
                local ch = Core.at(s, mx, r)
                if mx <= Core.width(s) and ch ~= " " then
                    drawTile(d, ch, (c - 1) * TILE, (r - 1) * TILE, Core.at(s, mx, r - 1))
                    if ch == "F" then fx, fy = c, r end
                end
            end
        end
        if fx and fx < COLS and Core.at(s, cx + fx, fy) == " " then
            d.icon("castle", fx * TILE + TILE / 2, (fy - 1) * TILE + TILE / 2, TILE)
        end
        for _, e in ipairs(s.enemies) do
            local c = e.x - cx + 1
            if c >= 1 and c <= COLS then
                d.icon("goomba", (c - 0.5) * TILE, (e.y - 0.5) * TILE, TILE)
            end
        end
        if s.dir ~= 0 then face = s.dir end
        local pose = not s.grounded and "player_jump" or (s.dir ~= 0 and s.t % 2 == 1 and "player_walk" or "player_stand")
        d.icon(pose .. (face < 0 and "_l" or ""), (s.x - cx + 0.5) * TILE, (s.y - 0.5) * TILE, TILE)
        drawHud(d)
        if s.over then
            d.rect(10, 26, COLS * TILE - 20, 16, "white")
            d.frame(10, 26, COLS * TILE - 20, 16, "black", 0.8)
            if s.won then d.icon("flag_top", COLS * TILE / 2, 34, 12)
            else d.text(T("游戏结束"), COLS * TILE / 2, 34, 3, "black") end
        elseif s.msg == "clear" then d.icon("flag_top", COLS * TILE / 2, 30, 16)
        elseif s.msg == "dead" then d.icon("heart", COLS * TILE / 2, 30, 14) end
        if paused and not s.over then drawZones(d) end
    end

    function self.render()
        ctx:render({
            title = T("跳跳冒险"),
            canvas = { w = COLS * TILE, h = ROWS * TILE, draw = draw,
                on_tap = function(x) self.tap(x) end },
            settings = { reset = function() self.newGame() end, groups = {} },
            buttons = {
                {
                    { icon = "left", selected = s.dir == -1, callback = function() self.input("left") end },
                    { icon = "right", selected = s.dir == 1, callback = function() self.input("right") end },
                    { icon = "jump", callback = function() self.input("jump") end },
                },
                { { menu = true, enabled = not s.over, text = paused and (s.t == 0 and T("开始") or T("继续")) or T("暂停"),
                    callback = function() self.toggle() end },
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
        local r = Core.step(s)
        if s.over then self.finish()
        elseif r == "dead" or r == "clear" then
            halt()
            paused = true
            s.msg = r
            persist()
        else arm() end
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
        s.msg = ""
        arm()
    end

    function self.toggle()
        if s.over then return end
        if paused then self.resume() else self.pause() end
        self.render()
    end

    function self.input(k)
        if s.over then return end
        if k == "left" then Core.setDir(s, s.dir == -1 and 0 or -1)
        elseif k == "right" then Core.setDir(s, s.dir == 1 and 0 or 1)
        elseif k == "stop" then Core.setDir(s, 0)
        elseif k == "jump" then Core.requestJump(s) end
        if paused then self.resume() end
        self.render()
    end

    function self.tap(x)
        if x < COLS * TILE / 3 then self.input("left")
        elseif x > COLS * TILE * 2 / 3 then self.input("right")
        else self.input("jump") end
    end

    function self.newGame()
        halt()
        s, paused = Core.fresh(), true
        persist()
        self.render()
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.map and not saved.state.over then s = saved.state
        else s = Core.fresh() end
        s.dir = 0
        s.jump = false
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
