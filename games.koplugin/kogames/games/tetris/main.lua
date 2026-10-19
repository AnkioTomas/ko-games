--[[--
俄罗斯方块。慢速重力，按钮/滑动控制；只在每一拍/操作时刷新，暂停或退出即停表。
--]]
local T = require("kogames.l10n")

local W, H = 10, 18
local KINDS = { "I", "O", "T", "S", "Z", "J", "L" }
local BASE = {
    I = { n = 4, { 1, 0 }, { 1, 1 }, { 1, 2 }, { 1, 3 } },
    O = { n = 2, { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } },
    T = { n = 3, { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, 2 } },
    S = { n = 3, { 0, 1 }, { 0, 2 }, { 1, 0 }, { 1, 1 } },
    Z = { n = 3, { 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 2 } },
    J = { n = 3, { 0, 0 }, { 1, 0 }, { 1, 1 }, { 1, 2 } },
    L = { n = 3, { 0, 2 }, { 1, 0 }, { 1, 1 }, { 1, 2 } },
}
local LINE_SCORE = { 100, 300, 500, 800 }
local MAX_LEVEL = 5

local Core = {}

--- 某形状某旋转（0..3，顺时针）下的 4 个格子 {行, 列}，从 0 起。
function Core.cells(kind, rot)
    local b = BASE[kind]
    local cur = {}
    for i = 1, 4 do cur[i] = { b[i][1], b[i][2] } end
    for _ = 1, rot % 4 do
        for i = 1, 4 do cur[i] = { cur[i][2], b.n - 1 - cur[i][1] } end
    end
    return cur
end

local function fits(s, kind, rot, r, c)
    for _, p in ipairs(Core.cells(kind, rot)) do
        local rr, cc = r + p[1], c + p[2]
        if rr < 1 or rr > s.h or cc < 1 or cc > s.w then return false end
        if s.board[(rr - 1) * s.w + cc] ~= 0 then return false end
    end
    return true
end
Core.fits = fits

local function nextKind(s, rng)
    if #s.bag == 0 then
        for i, k in ipairs(KINDS) do s.bag[i] = k end
        rng:shuffle(s.bag)
    end
    return table.remove(s.bag)
end

local function spawn(s, rng)
    local kind = s.next or nextKind(s, rng)
    s.next = nextKind(s, rng)
    s.cur = { kind = kind, rot = 0, r = 1, c = math.floor((s.w - BASE[kind].n) / 2) + 1 }
    if not fits(s, kind, 0, s.cur.r, s.cur.c) then s.over = true end
end

function Core.fresh(rng, base_level, w, h)
    w, h = w or W, h or H
    local s = { w = w, h = h, board = {}, bag = {}, score = 0, lines = 0, base = base_level or 1, over = false }
    for i = 1, w * h do s.board[i] = 0 end
    spawn(s, rng)
    return s
end

function Core.level(s) return math.min(MAX_LEVEL, s.base + math.floor(s.lines / 10)) end

function Core.interval(s) return math.max(0.5, 1.0 - 0.1 * (Core.level(s) - 1)) end

function Core.move(s, dc)
    if s.over then return false end
    local p = s.cur
    if not fits(s, p.kind, p.rot, p.r, p.c + dc) then return false end
    p.c = p.c + dc
    return true
end

function Core.rotate(s)
    if s.over then return false end
    local p = s.cur
    local rot = (p.rot + 1) % 4
    for _, kick in ipairs({ 0, -1, 1, -2, 2 }) do
        if fits(s, p.kind, rot, p.r, p.c + kick) then
            p.rot, p.c = rot, p.c + kick
            return true
        end
    end
    return false
end

local function clearLines(s)
    local kept, cleared = {}, 0
    for r = s.h, 1, -1 do
        local full = true
        for c = 1, s.w do if s.board[(r - 1) * s.w + c] == 0 then full = false break end end
        if full then cleared = cleared + 1
        else kept[#kept + 1] = r end
    end
    if cleared == 0 then return 0 end
    local nb = {}
    for i = 1, s.w * s.h do nb[i] = 0 end
    for i, r in ipairs(kept) do
        local dst = s.h - i + 1
        for c = 1, s.w do nb[(dst - 1) * s.w + c] = s.board[(r - 1) * s.w + c] end
    end
    s.board = nb
    return cleared
end

local function lock(s, rng)
    local p = s.cur
    for _, q in ipairs(Core.cells(p.kind, p.rot)) do
        s.board[(p.r + q[1] - 1) * s.w + p.c + q[2]] = 1
    end
    local n = clearLines(s)
    if n > 0 then
        s.score = s.score + LINE_SCORE[n] * Core.level(s)
        s.lines = s.lines + n
    end
    spawn(s, rng)
    return n
end

--- 下落一格；落地则锁定并生成新方块。返回 "fall" | "lock"
function Core.drop(s, rng)
    local p = s.cur
    if fits(s, p.kind, p.rot, p.r + 1, p.c) then p.r = p.r + 1 return "fall" end
    lock(s, rng)
    return "lock"
end

--- 直接落到底并锁定，每落一格加 1 分。
function Core.hardDrop(s, rng)
    local p = s.cur
    local n = 0
    while fits(s, p.kind, p.rot, p.r + 1, p.c) do p.r = p.r + 1 n = n + 1 end
    s.score = s.score + n
    lock(s, rng)
    return n
end

function Core.ghostRow(s)
    local p = s.cur
    local r = p.r
    while fits(s, p.kind, p.rot, r + 1, p.c) do r = r + 1 end
    return r
end

local M = { id = "tetris", title = T("俄罗斯方块"), icon = "view_module", tier = "C",
    desc = T("消行得分，慢速下落"), core = Core,
    help = T("方块从顶部缓慢下落，用按钮或滑动移动、旋转，铺满一整行即可消除得分；消得越多一次得分越高。\n按钮：← → 左右移动，旋转，下移一格，落底（直接落到底）。滑动：左右移动，向上旋转，向下落底。\n新方块无处放置则游戏结束。每消 10 行速度加快一级，也可手动选择速度（1~5）。\n浅灰色格子是落点提示。墨水屏每一拍都会刷新，建议使用较慢的速度。") }

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
        handle = ctx.host:schedule(Core.interval(s), function()
            if mine ~= token or paused or s.over then return end
            handle = nil
            self.tick()
        end)
    end

    function self.render()
        local best = math.max(ctx:best("best") or 0, s.score)
        local status = (T("得分 %d  最高 %d  等级 %d  行 %d")):format(s.score, best, Core.level(s), s.lines)
        if s.over then status = status .. T("  游戏结束") elseif paused then status = status .. T("  已暂停") end
        local cur, ghost = {}, {}
        if not s.over then
            local p = s.cur
            local gr = Core.ghostRow(s)
            for _, q in ipairs(Core.cells(p.kind, p.rot)) do
                ghost[(gr + q[1] - 1) * s.w + p.c + q[2]] = true
                cur[(p.r + q[1] - 1) * s.w + p.c + q[2]] = true
            end
        end
        local sp = {}
        for n = 1, MAX_LEVEL do
            sp[#sp + 1] = { text = tostring(n), selected = n == s.base, callback = function() self.setBase(n) end }
        end
        local live = not paused and not s.over
        ctx:render({
            title = T("俄罗斯方块"),
            status = status,
            grid = {
                rows = s.h, cols = s.w, gap = true, slots = true,
                cell = function(r, c)
                    local i = (r - 1) * s.w + c
                    if cur[i] then return { fill = "black" } end
                    if s.board[i] ~= 0 then return { fill = "raised" } end
                    if ghost[i] then return { fill = "grey" } end
                end,
            },
            on_swipe = function(d)
                if d == "west" then self.left() elseif d == "east" then self.right()
                elseif d == "north" then self.rotate() elseif d == "south" then self.hard() end
            end,
            settings = { groups = { { label = T("速度"), options = sp } }, reset = function() self.newGame() end },
            buttons = {
                { label = T("下一个：%s", s.next or "") },
                {
                    { text = "←", enabled = live, callback = function() self.left() end },
                    { text = T("旋转"), enabled = live, callback = function() self.rotate() end },
                    { text = "→", enabled = live, callback = function() self.right() end },
                },
                {
                    { text = T("下移"), enabled = live, callback = function() self.soft() end },
                    { text = T("落底"), enabled = live, callback = function() self.hard() end },
                },
                {
                    { text = s.over and T("再来一局") or (paused and (s.lines == 0 and s.score == 0 and T("开始") or T("继续")) or T("暂停")),
                        callback = s.over and function() self.newGame() end or function() self.toggle() end },
                    { menu = true, text = T("新游戏"), callback = function() self.newGame() end },
                },
            },
        })
    end

    function self.finish()
        halt()
        paused = true
        if ctx:record("best", s.score) and s.score > 0 then ctx:notify(T("新纪录：%d", s.score)) end
        persist()
    end

    -- 落地/结束要刷新并重新定时；纯移动只刷新
    function self.tick()
        Core.drop(s, ctx.rng)
        if s.over then self.finish() else arm() end
        self.render()
    end

    local function act(fn)
        if paused or s.over then return end
        if fn() then self.render() end
    end

    function self.left() act(function() return Core.move(s, -1) end) end
    function self.right() act(function() return Core.move(s, 1) end) end
    function self.rotate() act(function() return Core.rotate(s) end) end
    function self.soft()
        act(function()
            Core.drop(s, ctx.rng)
            if s.over then self.finish() else arm() end
            return true
        end)
    end
    function self.hard()
        act(function()
            Core.hardDrop(s, ctx.rng)
            if s.over then self.finish() else arm() end
            return true
        end)
    end

    function self.pause()
        if paused then return end
        paused = true
        halt()
        persist()
    end

    function self.toggle()
        if s.over then return end
        if paused then paused = false arm() else self.pause() end
        self.render()
    end

    function self.setBase(n)
        s.base = n
        if not paused and not s.over then arm() end
        persist()
        self.render()
    end

    function self.newGame()
        halt()
        s, paused = Core.fresh(ctx.rng, s and s.base or 1), true
        persist()
        self.render()
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.board and saved.state.cur then s = saved.state
        else s = Core.fresh(ctx.rng, 1) end
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
