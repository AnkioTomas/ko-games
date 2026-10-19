--[[--
泡泡龙（Bust-a-Move 经典玩法）。六边形错行网格，底部炮台发射泡泡，直线飞行、撞墙反弹，
停在最近的蜂窝格；同色 3 个以上相连消除，消除后悬空的泡泡一起掉落。连续 N 发没有消除，整体下压一行，
泡泡越过死线失败，清空过关进入下一关。核心只算落点（离散步进模拟路径），没有逐帧动画。
--]]
local T = require("kogames.l10n")

local COLS, ROWS = 8, 12
local DEAD_ROW = ROWS -- 第 12 行（1 起）出现泡泡 = 越过死线
local W, H = 100, 150
local D = W / COLS
local R = D / 2
local P = D * 0.866
local SX, SY = W / 2, 138
local MAX_ANGLE = 75
local MODES = {
    { id = "easy", colors = 4, period = 6, label = "简单" },
    { id = "normal", colors = 4, period = 5, label = "普通" },
    { id = "hard", colors = 5, period = 4, label = "困难" },
}

local Core = { COLS = COLS, ROWS = ROWS, W = W, H = H, SX = SX, SY = SY, R = R, MAX_ANGLE = MAX_ANGLE }

local function modeOf(id)
    for _, m in ipairs(MODES) do if m.id == id then return m end end
    return MODES[2]
end

local function ncols(s, r) return COLS - (r + s.par) % 2 end
local function idx(r, c) return r * COLS + c + 1 end

--- 格子中心坐标（r、c 均从 0 起）。
function Core.cellXY(s, r, c)
    return R + c * D + (((r + s.par) % 2 == 1) and R or 0), R + r * P
end

--- 相邻的 6 个格子，返回 { {r,c}, ... }。
function Core.neighbors(s, r, c)
    local out = {}
    local function add(rr, cc)
        if rr >= 0 and rr < ROWS and cc >= 0 and cc < ncols(s, rr) then out[#out + 1] = { rr, cc } end
    end
    add(r, c - 1) add(r, c + 1)
    local lo = ((r + s.par) % 2 == 1) and c or c - 1
    add(r - 1, lo) add(r - 1, lo + 1)
    add(r + 1, lo) add(r + 1, lo + 1)
    return out
end

local function levelColors(m, level) return math.min(5, m.colors + math.floor((level - 1) / 2)) end

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

local function fillRows(s, rng, n)
    for r = 0, n - 1 do
        for c = 0, ncols(s, r) - 1 do s.board[idx(r, c)] = rng:int(s.colors) end
    end
end

function Core.fresh(rng, mode, level, score)
    local m = modeOf(mode)
    level = level or 1
    local s = { mode = m.id, level = level, colors = levelColors(m, level), period = m.period, par = 0,
        board = {}, score = score or 0, misses = 0, aim = 0 }
    for i = 1, ROWS * COLS do s.board[i] = 0 end
    fillRows(s, rng, math.min(8, 5 + math.floor((level - 1) / 2)))
    s.cur, s.nxt = draw(s, rng), draw(s, rng)
    return s
end

function Core.clampAngle(a) return math.max(-MAX_ANGLE, math.min(MAX_ANGLE, a)) end

--- 点 (x,y) 对应的发射角（度，0 = 正上方，正为向右），限制在 ±75°。
function Core.angleTo(x, y)
    local dy = SY - y
    if dy < 1 then return x < SX and -MAX_ANGLE or MAX_ANGLE end
    return Core.clampAngle(math.deg(math.atan2(x - SX, dy)))
end

--- 模拟飞行：返回 { r=, c=, path={ {x,y}... } }（r、c 从 0 起），path 含起点、每次反弹点与停点。
function Core.trace(s, angle)
    local a = math.rad(Core.clampAngle(angle))
    local vx, vy = math.sin(a), -math.cos(a)
    local x, y = SX, SY
    local path = { { x, y } }
    local occ = {}
    for r = 0, ROWS - 1 do
        for c = 0, ncols(s, r) - 1 do
            if s.board[idx(r, c)] ~= 0 then
                local cx, cy = Core.cellXY(s, r, c)
                occ[#occ + 1] = { cx, cy }
            end
        end
    end
    local lim = (D * 0.9) ^ 2
    for _ = 1, 4000 do
        x, y = x + vx, y + vy
        if x < R then x, vx = 2 * R - x, -vx path[#path + 1] = { R, y }
        elseif x > W - R then x, vx = 2 * (W - R) - x, -vx path[#path + 1] = { W - R, y } end
        if y <= R then break end
        local hit = false
        for _, o in ipairs(occ) do
            local dx, dy = o[1] - x, o[2] - y
            if dx * dx + dy * dy < lim then hit = true break end
        end
        if hit then break end
    end
    path[#path + 1] = { x, y }
    local best, br, bc = nil, nil, nil
    for r = 0, ROWS - 1 do
        for c = 0, ncols(s, r) - 1 do
            if s.board[idx(r, c)] == 0 then
                local ok = r == 0
                if not ok then
                    for _, n in ipairs(Core.neighbors(s, r, c)) do
                        if s.board[idx(n[1], n[2])] ~= 0 then ok = true break end
                    end
                end
                if ok then
                    local cx, cy = Core.cellXY(s, r, c)
                    local d2 = (cx - x) ^ 2 + (cy - y) ^ 2
                    if not best or d2 < best then best, br, bc = d2, r, c end
                end
            end
        end
    end
    if not br then return nil end
    local cx, cy = Core.cellXY(s, br, bc)
    path[#path] = { cx, cy }
    return { r = br, c = bc, path = path }
end

local function group(s, r, c)
    local color = s.board[idx(r, c)]
    local seen, stack, list = { [idx(r, c)] = true }, { { r, c } }, {}
    while #stack > 0 do
        local k = table.remove(stack)
        list[#list + 1] = k
        for _, n in ipairs(Core.neighbors(s, k[1], k[2])) do
            local i = idx(n[1], n[2])
            if not seen[i] and s.board[i] == color then seen[i] = true stack[#stack + 1] = n end
        end
    end
    return list
end

--- 掉落所有不与顶行相连的泡泡，返回个数。
local function dropFloating(s)
    local seen, stack = {}, {}
    for c = 0, ncols(s, 0) - 1 do
        if s.board[idx(0, c)] ~= 0 then seen[idx(0, c)] = true stack[#stack + 1] = { 0, c } end
    end
    while #stack > 0 do
        local k = table.remove(stack)
        for _, n in ipairs(Core.neighbors(s, k[1], k[2])) do
            local i = idx(n[1], n[2])
            if not seen[i] and s.board[i] ~= 0 then seen[i] = true stack[#stack + 1] = n end
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
    s.par = 1 - s.par
    for i = 1, COLS do s.board[i] = 0 end
    for c = 0, ncols(s, 0) - 1 do s.board[idx(0, c)] = rng:int(s.colors) end
end
Core.descend = descend

function Core.over(s)
    for r = DEAD_ROW - 1, ROWS - 1 do
        for c = 0, COLS - 1 do if s.board[idx(r, c)] ~= 0 then return true end end
    end
    return false
end

function Core.cleared(s)
    for i = 1, ROWS * COLS do if s.board[i] ~= 0 then return false end end
    return true
end

--- 过关：保留分数，进入下一关（更多颜色、更多行）。
function Core.nextLevel(s, rng)
    local n = Core.fresh(rng, s.mode, s.level + 1, s.score + 200)
    for k, v in pairs(n) do s[k] = v end
end

--- 发射。返回 { r,c,path,popped,fell,descended,cleared } 或 nil。
function Core.fire(s, rng, angle)
    if Core.over(s) or Core.cleared(s) then return nil end
    local t = Core.trace(s, angle)
    if not t then return nil end
    s.aim = Core.clampAngle(angle)
    s.board[idx(t.r, t.c)] = s.cur
    local res = { r = t.r, c = t.c, path = t.path, popped = 0, fell = 0 }
    local g = group(s, t.r, t.c)
    if #g >= 3 then
        for _, k in ipairs(g) do s.board[idx(k[1], k[2])] = 0 end
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
        res.cleared = true
        return res
    end
    s.cur = s.nxt
    s.nxt = draw(s, rng)
    return res
end

function Core.swap(s) s.cur, s.nxt = s.nxt, s.cur end

local function bubble(d, x, y, k, r)
    r = r or R - 0.5
    if k == 1 then
        d.circle(x, y, r, "black")
    elseif k == 2 then
        d.ring(x, y, r, "black", 1.4)
    elseif k == 3 then
        d.circle(x, y, r, "black") d.circle(x, y, r - 1, "grey")
    elseif k == 4 then
        d.circle(x, y, r, "black") d.circle(x, y, r - 1, "dark")
    else
        d.ring(x, y, r, "black", 1.4) d.circle(x, y, r * 0.4, "black")
    end
end

local M = { id = "bubbleshooter", title = T("泡泡龙"), icon = "bubble_chart", tier = "B", desc = T("经典泡泡龙：瞄准发射，三个同色相连即消除"), core = Core,
    help = T("目标：消除全部泡泡过关，别让泡泡越过底部的死线。\n点画面任意位置会朝那里立即发射；也可用 ◀ ▶ 每次微调 5°，再点「发射」。虚线是飞行路径，碰到左右墙会反弹。\n泡泡停在最近的蜂窝格，同色 3 个以上相连就消除；消除后不再与顶部相连的泡泡会一起掉落，得分更高。\n连续几发没有消除，整体会下压一行（画面会显示还剩几发）。点「换泡」或点左下角的泡泡交换当前与下一个。\n每过一关颜色和行数会增加，不同颜色用不同的图案区分：实心、空心、浅灰、深灰、同心圆。") }

function M.new(ctx)
    local self = {}
    local s, last

    local function persist() ctx:save({ state = s }) end

    local function fresh(mode)
        s, last = Core.fresh(ctx.rng, mode or (s and s.mode) or "normal"), nil
        persist()
        self.render()
    end

    function self.fire(angle)
        if Core.over(s) then return end
        local res = Core.fire(s, ctx.rng, angle or s.aim)
        if not res then return end
        if res.cleared then
            Core.nextLevel(s, ctx.rng)
            ctx:record("score_" .. s.mode, s.score)
            last = T("过关！进入第 %d 关", s.level)
        elseif res.popped > 0 then
            last = T("消除 %d 个，掉落 %d 个", res.popped, res.fell)
        elseif res.descended then
            last = T("泡泡下压一行")
        else
            last = nil
        end
        if Core.over(s) then
            last = nil
            if ctx:record("score_" .. s.mode, s.score) then ctx:notify(T("新纪录：%d", s.score)) end
        end
        persist()
        self.render()
        return res
    end

    function self.nudge(delta)
        s.aim = Core.clampAngle(s.aim + delta)
        self.render()
    end

    function self.tap(x, y)
        if Core.over(s) then return end
        if (x - 20) ^ 2 + (y - (SY + 4)) ^ 2 < 64 then
            Core.swap(s) persist() self.render() return
        end
        self.fire(Core.angleTo(x, y))
    end

    function self.render()
        local over = Core.over(s)
        local status = T("得分 %d    第 %d 关    再 %d 发下压", s.score, s.level, s.period - s.misses)
        local best = ctx:best("score_" .. s.mode)
        if best then status = status .. T("    最高 %d", best) end
        local mode_row = {}
        for _, m in ipairs(MODES) do
            mode_row[#mode_row + 1] = { text = T(m.label), selected = m.id == s.mode, callback = function() fresh(m.id) end }
        end
        local buttons
        if over then
            buttons = { { label = T("泡泡越过死线，游戏结束") }, { { text = T("重新开始"), callback = function() fresh() end } } }
        else
            buttons = {
                { { text = "◀", callback = function() self.nudge(-5) end },
                    { text = T("发射"), callback = function() self.fire() end },
                    { text = "▶", callback = function() self.nudge(5) end },
                    { text = T("换泡"), callback = function() Core.swap(s) persist() self.render() end } },
            }
            if last then table.insert(buttons, 1, { label = last }) end
        end
        buttons[#buttons + 1] = { { menu = true, text = T("新游戏"), callback = function() fresh() end } }
        local path = (not over) and Core.trace(s, s.aim) or nil
        ctx:render({
            title = T("泡泡龙"),
            status = status,
            canvas = {
                w = W, h = H,
                draw = function(d)
                    d.frame(0, 0, W, H, "black", 0.8)
                    for r = 0, ROWS - 1 do
                        for c = 0, ncols(s, r) - 1 do
                            local v = s.board[idx(r, c)]
                            if v ~= 0 then
                                local x, y = Core.cellXY(s, r, c)
                                bubble(d, x, y, v)
                            end
                        end
                    end
                    local dy = R + (DEAD_ROW - 2) * P + R + 1
                    for x = 2, W - 4, 6 do d.line(x, dy, x + 3, dy, "dark", 0.6) end
                    if over then
                        d.text(T("游戏结束"), W / 2, dy + 8, 8, "black")
                        return
                    end
                    if path then
                        local pts, left, step = path.path, 0, 4.5
                        for i = 1, #pts - 1 do
                            local a, b = pts[i], pts[i + 1]
                            local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
                            local p = left
                            while p < len do
                                d.circle(a[1] + (b[1] - a[1]) * p / len, a[2] + (b[2] - a[2]) * p / len, 0.7, "dark")
                                p = p + step
                            end
                            left = p - len
                        end
                        local gx, gy = Core.cellXY(s, path.r, path.c)
                        d.ring(gx, gy, R - 0.5, "dark", 0.5)
                    end
                    local a = math.rad(s.aim)
                    d.line(SX, SY, SX + math.sin(a) * 11, SY - math.cos(a) * 11, "black", 2.2)
                    bubble(d, SX, SY, s.cur)
                    bubble(d, 20, SY + 4, s.nxt, R * 0.8)
                    for i = 1, s.period do
                        local x = W - 6 - (s.period - i) * 3.4
                        if i <= s.misses then d.circle(x, SY + 4, 1.2, "black") else d.ring(x, SY + 4, 1.4, "black", 0.5) end
                    end
                end,
                on_tap = function(x, y) self.tap(x, y) end,
            },
            settings = { groups = { { label = T("难度"), options = mode_row } }, reset = function() fresh() end },
            buttons = buttons,
        })
    end

    function self.start()
        local saved = ctx:load()
        local st = saved and saved.state
        if st and st.board and #st.board == ROWS * COLS and st.cur and st.nxt and st.par and st.level then
            s = st
            self.render()
        else
            fresh("normal")
        end
    end

    self.state = function() return s end
    return self
end

return M
