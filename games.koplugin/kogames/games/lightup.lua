--[[--
照明（Light Up / Akari）。格子 g：-2 白格，-1 无数字黑墙，0..4 带数字黑墙。
玩家 user：0 空，1 灯，2 标记"无灯"。灯向四方照亮直到墙；
要求所有白格被照亮、灯互不照射、数字墙四周灯数恰好等于数字。
生成：随机墙 -> 求一个合法布灯 -> 按布灯写数字 -> 尽量删数字并保持解唯一。
--]]
local T = require("kogames.l10n")
local SIZES = { 7, 10 }

local Core = {}
local WHITE, WALL = -2, -1
Core.WHITE, Core.WALL = WHITE, WALL

local DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local function neighbors(n, i)
    local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
    local out = {}
    for _, d in ipairs(DIRS) do
        local rr, cc = r + d[1], c + d[2]
        if rr >= 1 and rr <= n and cc >= 1 and cc <= n then out[#out + 1] = (rr - 1) * n + cc end
    end
    return out
end

--- 每个白格能看到的白格（含自己）
local function visibility(g, n)
    local vis = {}
    for i = 1, n * n do
        if g[i] == WHITE then
            local list = { i }
            local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
            for _, d in ipairs(DIRS) do
                local rr, cc = r + d[1], c + d[2]
                while rr >= 1 and rr <= n and cc >= 1 and cc <= n and g[(rr - 1) * n + cc] == WHITE do
                    list[#list + 1] = (rr - 1) * n + cc
                    rr, cc = rr + d[1], cc + d[2]
                end
            end
            vis[i] = list
        end
    end
    return vis
end

--- 求解：返回解的个数（至多 limit）和第一个解（1 灯 2 无灯）；rng 随机分支顺序
function Core.solve(g, n, limit, rng)
    local vis = visibility(g, n)
    local nb = {}
    for i = 1, n * n do if g[i] >= 0 then nb[i] = neighbors(n, i) end end
    local count, first = 0, nil

    local function propagate(a)
        local changed = true
        while changed do
            changed = false
            for i = 1, n * n do
                if a[i] == 1 then
                    for _, j in ipairs(vis[i]) do
                        if j ~= i then
                            if a[j] == 1 then return false end
                            if a[j] == 0 then a[j] = 2 changed = true end
                        end
                    end
                end
            end
            for i = 1, n * n do
                local k = g[i]
                if k >= 0 then
                    local lamps, free = 0, 0
                    for _, j in ipairs(nb[i]) do
                        if g[j] == WHITE then
                            if a[j] == 1 then lamps = lamps + 1 elseif a[j] == 0 then free = free + 1 end
                        end
                    end
                    if lamps > k or lamps + free < k then return false end
                    if free > 0 and (lamps == k or lamps + free == k) then
                        local v = lamps == k and 2 or 1
                        for _, j in ipairs(nb[i]) do
                            if g[j] == WHITE and a[j] == 0 then a[j] = v changed = true end
                        end
                    end
                end
            end
            for i = 1, n * n do
                if g[i] == WHITE then
                    local lit, cand, last = false, 0, nil
                    for _, j in ipairs(vis[i]) do
                        if a[j] == 1 then lit = true break end
                        if a[j] == 0 then cand = cand + 1 last = j end
                    end
                    if not lit then
                        if cand == 0 then return false end
                        if cand == 1 then a[last] = 1 changed = true end
                    end
                end
            end
        end
        return true
    end

    local function go(a)
        if not propagate(a) then return end
        local pick, best = nil, 99
        for i = 1, n * n do
            if g[i] == WHITE and a[i] == 0 then
                local cand = 0
                for _, j in ipairs(vis[i]) do if a[j] == 0 then cand = cand + 1 end end
                if cand < best then best, pick = cand, i end
            end
        end
        if not pick then
            count = count + 1
            first = first or a
            return
        end
        local lamp_first = not rng or rng:int(2) == 1
        for _, v in ipairs(lamp_first and { 1, 2 } or { 2, 1 }) do
            local h = {}
            for i = 1, n * n do h[i] = a[i] end
            h[pick] = v
            go(h)
            if count >= limit then return end
        end
    end

    local a = {}
    for i = 1, n * n do a[i] = 0 end
    go(a)
    return count, first
end

--- 当前状态分析：lit 被照亮集合，badLamp 互相照射的灯，badWall 数字违规的墙
function Core.analyze(g, n, user)
    local vis = visibility(g, n)
    local lit, badLamp, badWall = {}, {}, {}
    for i = 1, n * n do
        if user[i] == 1 and vis[i] then
            for _, j in ipairs(vis[i]) do
                lit[j] = true
                if j ~= i and user[j] == 1 then badLamp[i] = true end
            end
        end
    end
    local ok = true
    for i = 1, n * n do
        if g[i] == WHITE then
            if not lit[i] then ok = false end
        elseif g[i] >= 0 then
            local lamps, free = 0, 0
            for _, j in ipairs(neighbors(n, i)) do
                if g[j] == WHITE then
                    if user[j] == 1 then lamps = lamps + 1 else free = free + 1 end
                end
            end
            if lamps ~= g[i] then ok = false end
            if lamps > g[i] then badWall[i] = true end
        end
    end
    if next(badLamp) then ok = false end
    return { lit = lit, badLamp = badLamp, badWall = badWall, solved = ok }
end

function Core.solved(g, n, user) return Core.analyze(g, n, user).solved end

local function randomWalls(rng, n)
    local g = {}
    for i = 1, n * n do g[i] = rng:float() < 0.2 and WALL or WHITE end
    return g
end

function Core.fresh(rng, n)
    n = n or 7
    local g, sol
    for _ = 1, 40 do
        local cg = randomWalls(rng, n)
        local c, a = Core.solve(cg, n, 1, rng)
        if c == 1 then
            g, sol = cg, a
            for i = 1, n * n do
                if g[i] ~= WHITE then
                    local k = 0
                    for _, j in ipairs(neighbors(n, i)) do if g[j] == WHITE and a[j] == 1 then k = k + 1 end end
                    g[i] = k
                end
            end
            if Core.solve(g, n, 2) == 1 then break end
        end
    end
    if not sol then -- 兜底：没有任何墙的盘面必有解
        g = {}
        for i = 1, n * n do g[i] = WHITE end
        local _, a = Core.solve(g, n, 1, rng)
        sol = a
    end
    local walls = {}
    for i = 1, n * n do if g[i] ~= WHITE then walls[#walls + 1] = i end end
    rng:shuffle(walls)
    for _, i in ipairs(walls) do
        local keep = g[i]
        g[i] = WALL
        if Core.solve(g, n, 2) ~= 1 then g[i] = keep end
    end
    local user = {}
    for i = 1, n * n do user[i] = 0 end
    return { n = n, g = g, sol = sol, user = user }
end

local M = { id = "lightup", title = T("照明"), icon = "grid_view", art = "icon_lightup", tier = "A", desc = T("放置灯泡照亮全部格子"), help = T("在白格里放灯泡，让所有白格都被照亮；灯向上下左右照射直到碰到黑墙，两盏灯不能互相照到。\n黑墙上的数字表示它上下左右相邻的灯泡数量。\n点按放置/取消灯泡，长按（或切换到「标记」）可标记确定没有灯的格子。\n被照亮的格子为灰底，互相照射的灯会变深，数字被超出的墙会变灰。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, started, mode, undo

    local function persist() ctx:save({ state = s, started = started, mode = mode, undo = undo }) end

    local function newGame(n)
        s, started, undo = Core.fresh(ctx.rng, n), ctx.host:now(), {}
        persist()
        self.render()
    end

    local function setCell(i, v)
        if s.done or s.g[i] ~= WHITE then return end
        local new = s.user[i] == v and 0 or v
        undo[#undo + 1] = { i, s.user[i] }
        if #undo > 200 then table.remove(undo, 1) end
        s.user[i] = new
        if Core.solved(s.g, s.n, s.user) then
            s.done = true
            s.time = math.floor(ctx.host:now() - started)
            if ctx:record("best_" .. s.n, s.time, true) then
                ctx:notify((T("新纪录：%d 分 %d 秒")):format(math.floor(s.time / 60), s.time % 60))
            end
        end
        persist()
        self.render()
    end

    function self.render()
        local n = s.n
        local an = Core.analyze(s.g, n, s.user)
        local status = T("%d×%d", n, n)
        if s.done then
            status = status .. T("    完成！") .. (T("    用时 %d:%02d")):format(math.floor(s.time / 60), s.time % 60)
        end
        local best = ctx:best("best_" .. n)
        if best then status = status .. (T("    最佳 %d:%02d")):format(math.floor(best / 60), best % 60) end
        local size_row = {}
        for _, k in ipairs(SIZES) do
            size_row[#size_row + 1] = { text = k .. "×" .. k, selected = k == n, callback = function() if k ~= n then newGame(k) end end }
        end
        ctx:render({
            title = T("照明"),
            status = status,
            grid = {
                rows = n, cols = n,
                cell = function(r, c)
                    local i = (r - 1) * n + c
                    local k = s.g[i]
                    if k ~= WHITE then
                        local cell = { fill = an.badWall[i] and "dark" or "black" }
                        if k >= 0 then cell.text, cell.scale, cell.color = tostring(k), 0.55, "white" end
                        return cell
                    end
                    local v = s.user[i]
                    local cell = { fill = an.lit[i] and "grey" or nil }
                    if v == 1 then
                        cell.shape = "black"
                        if an.badLamp[i] then cell.fill = "dark" end
                    elseif v == 2 then
                        cell.mark = "black"
                    end
                    return cell
                end,
                on_tap = function(r, c) setCell((r - 1) * n + c, mode == "dot" and 2 or 1) end,
                on_hold = function(r, c) setCell((r - 1) * n + c, 2) end,
            },
            buttons = {
                size_row,
                {
                    { text = T("灯泡"), selected = mode ~= "dot", callback = function() mode = "lamp" persist() self.render() end },
                    { text = T("标记"), selected = mode == "dot", callback = function() mode = "dot" persist() self.render() end },
                },
                {
                    { text = T("撤销"), enabled = #undo > 0 and not s.done, callback = function()
                        local u = table.remove(undo)
                        s.user[u[1]] = u[2]
                        persist()
                        self.render()
                    end },
                    { text = T("清除"), callback = function()
                        for i = 1, n * n do s.user[i] = 0 end
                        s.done, undo = nil, {}
                        persist()
                        self.render()
                    end },
                    { text = T("新游戏"), callback = function() newGame(n) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.sol then
            s, started, mode, undo = saved.state, saved.started or ctx.host:now(), saved.mode or "lamp", saved.undo or {}
        else
            mode = "lamp"
            s, started, undo = Core.fresh(ctx.rng, 7), ctx.host:now(), {}
        end
        self.render()
    end

    self.state = function() return s end
    return self
end

return M
