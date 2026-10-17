--[[--
接线（Net）。每格是一段线路（线头、直线、拐角、三通、十字），旋转格子让所有格子连到中央服务器，且没有环路。
格子用位掩码表示接口：1 上，2 右，4 下，8 左；点按顺时针转 90°，长按逆时针。
棋盘上的线路用 assets/net_<掩码>.svg 绘制（服务器格用 net_s<掩码>.svg），不依赖字体里的制表符。
--]]
local T = require("kogames.l10n")
local SIZES = { 5, 7 }
local DX = { [1] = 0, [2] = 1, [4] = 0, [8] = -1 }
local DY = { [1] = -1, [2] = 0, [4] = 1, [8] = 0 }
local OPP = { [1] = 4, [2] = 8, [4] = 1, [8] = 2 }
local DIRS = { 1, 2, 4, 8 }

local Core = {}

function Core.rotCW(m) return (m * 2) % 16 + math.floor(m / 8) end
function Core.rotCCW(m) return math.floor(m / 2) + (m % 2) * 8 end

--- 随机生成树：返回 n*n 的接口掩码数组（Prim 式随机生长，从中心出发）。
function Core.tree(rng, n)
    local mask, inTree = {}, {}
    for i = 1, n * n do mask[i] = 0 end
    local centre = (math.floor(n / 2)) * n + math.floor(n / 2) + 1
    inTree[centre] = true
    local frontier = {}
    local function addEdges(i)
        local x, y = (i - 1) % n, math.floor((i - 1) / n)
        for _, d in ipairs(DIRS) do
            local nx, ny = x + DX[d], y + DY[d]
            if nx >= 0 and nx < n and ny >= 0 and ny < n then
                local j = ny * n + nx + 1
                if not inTree[j] then frontier[#frontier + 1] = { i, j, d } end
            end
        end
    end
    addEdges(centre)
    while #frontier > 0 do
        local k = rng:int(#frontier)
        local e = frontier[k]
        frontier[k] = frontier[#frontier]
        frontier[#frontier] = nil
        if not inTree[e[2]] then
            inTree[e[2]] = true
            mask[e[1]] = mask[e[1]] + e[3]
            mask[e[2]] = mask[e[2]] + OPP[e[3]]
            addEdges(e[2])
        end
    end
    return mask, centre
end

--- 从服务器出发沿双向对接的接口搜索，返回已连通格子的集合。
function Core.connected(cur, n, server)
    local seen, stack = { [server] = true }, { server }
    while #stack > 0 do
        local i = table.remove(stack)
        local x, y = (i - 1) % n, math.floor((i - 1) / n)
        for _, d in ipairs(DIRS) do
            if cur[i] % (d * 2) >= d then
                local nx, ny = x + DX[d], y + DY[d]
                if nx >= 0 and nx < n and ny >= 0 and ny < n then
                    local j = ny * n + nx + 1
                    if not seen[j] and cur[j] % (OPP[d] * 2) >= OPP[d] then
                        seen[j] = true
                        stack[#stack + 1] = j
                    end
                end
            end
        end
    end
    return seen
end

function Core.count(seen)
    local c = 0
    for _ in pairs(seen) do c = c + 1 end
    return c
end

function Core.solved(s)
    return Core.count(Core.connected(s.cur, s.n, s.server)) == s.n * s.n
end

function Core.fresh(rng, n)
    n = n or 5
    local sol, server = Core.tree(rng, n)
    local cur = {}
    local s = { n = n, sol = sol, cur = cur, server = server, moves = 0 }
    repeat
        for i = 1, n * n do
            local m = sol[i]
            for _ = 1, rng:int(4) - 1 do m = Core.rotCW(m) end
            cur[i] = m
        end
    until not Core.solved(s)
    return s
end

local M = { id = "net", title = T("接线"), icon = "apps", art = "icon_net", tier = "A", desc = T("转动线路接通所有终端"), help = T("每个格子是一段线路。转动格子，让所有线路都连到中央的服务器，并且不能有环路。\n点按格子顺时针转 90°，长按逆时针转 90°。\n已接通服务器的格子会变灰；全部接通即完成。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, started

    local function persist() ctx:save({ state = s, started = started }) end

    local function newGame(n)
        s, started = Core.fresh(ctx.rng, n), ctx.host:now()
        persist()
        self.render()
    end

    local function check()
        if s.done or not Core.solved(s) then return end
        s.done = true
        s.time = math.floor(ctx.host:now() - started)
        if ctx:record("best_" .. s.n, s.time, true) then
            ctx:notify((T("新纪录：%d 分 %d 秒")):format(math.floor(s.time / 60), s.time % 60))
        end
    end

    local function rotate(r, c, ccw)
        if s.done then return end
        local i = (r - 1) * s.n + c
        s.cur[i] = (ccw and Core.rotCCW or Core.rotCW)(s.cur[i])
        s.moves = s.moves + 1
        check()
        persist()
        self.render()
    end

    function self.render()
        local n = s.n
        local seen = Core.connected(s.cur, n, s.server)
        local status = T("%d×%d", n, n) .. (T("    已接通 %d/%d")):format(Core.count(seen), n * n) .. (T("    步数 %d")):format(s.moves)
        if s.done then status = status .. T("    完成！") .. (T("    用时 %d:%02d")):format(math.floor(s.time / 60), s.time % 60) end
        local best = ctx:best("best_" .. n)
        if best then status = status .. (T("    最佳 %d:%02d")):format(math.floor(best / 60), best % 60) end
        local size_row = {}
        for _, k in ipairs(SIZES) do
            size_row[#size_row + 1] = { text = k .. "×" .. k, selected = k == n, callback = function() if k ~= n then newGame(k) end end }
        end
        ctx:render({
            title = T("接线"),
            status = status,
            grid = {
                rows = n, cols = n,
                cell = function(r, c)
                    local i = (r - 1) * n + c
                    local m = s.cur[i]
                    if i == s.server then return { icon = "net_s" .. m, icon_scale = 1, fill = "dark" } end
                    return { icon = "net_" .. m, icon_scale = 1, fill = seen[i] and "grey" or nil }
                end,
                on_tap = function(r, c) rotate(r, c, false) end,
                on_hold = function(r, c) rotate(r, c, true) end,
            },
            buttons = {
                size_row,
                { { text = T("新游戏"), callback = function() newGame(s.n) end } },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.sol then
            s, started = saved.state, saved.started or ctx.host:now()
        else
            s, started = Core.fresh(ctx.rng, 5), ctx.host:now()
        end
        self.render()
    end

    self.state = function() return s end
    return self
end

return M
