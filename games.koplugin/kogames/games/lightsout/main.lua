--[[--
点灯（Lights Out）。点一格会翻转它和上下左右四格的灯，目标是把所有灯熄灭。
题目由「从全灭状态随机点若干下」生成，保证有解。
--]]
local T = require("kogames.l10n")
local SIZES = { 4, 5, 6 }

local Core = {}

function Core.press(s, r, c)
    local n = s.n
    for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local rr, cc = r + d[1], c + d[2]
        if rr >= 1 and rr <= n and cc >= 1 and cc <= n then
            local i = (rr - 1) * n + cc
            s.cells[i] = not s.cells[i]
        end
    end
end

function Core.solved(s)
    for i = 1, s.n * s.n do if s.cells[i] then return false end end
    return true
end

function Core.fresh(rng, n)
    local s = { n = n, cells = {}, moves = 0 }
    for i = 1, n * n do s.cells[i] = false end
    repeat
        for _ = 1, n * n do Core.press(s, rng:int(n), rng:int(n)) end
    until not Core.solved(s)
    return s
end

local M = { id = "lightsout", title = T("点灯"), icon = "grid_view", tier = "A", desc = T("把所有的灯都熄灭"), help = T("目标：熄灭所有黑色的灯。\n点一格会翻转它和上下左右相邻格子的亮灭。\n可选 4×4、5×5、6×6 三种大小，步数越少越好。"), core = Core }

function M.new(ctx)
    local self = {}
    local s

    local function key() return "best" .. s.n end
    local function persist() ctx:save({ state = s }) end

    local function fresh(n)
        s = Core.fresh(ctx.rng, n)
        persist()
        self.render()
    end

    local function tap(r, c)
        if s.done then return end
        Core.press(s, r, c)
        s.moves = s.moves + 1
        if Core.solved(s) then
            s.done = true
            if ctx:record(key(), s.moves, true) then ctx:notify(T("新纪录：%d", s.moves)) end
        end
        persist()
        self.render()
    end

    function self.render()
        local status = T("步数 %d", s.moves)
        local best = ctx:best(key())
        if best then status = status .. T("    最少 %d", best) end
        if s.done then status = status .. T("    完成！") end
        local size_row = {}
        for _, n in ipairs(SIZES) do
            local selected = n == s.n
            size_row[#size_row + 1] = { text = n .. "×" .. n, selected = selected, callback = function()
                if not selected then fresh(n) end
            end }
        end
        ctx:render({
            title = T("点灯"),
            status = status,
            grid = {
                rows = s.n, cols = s.n, gap = true,
                cell = function(r, c) return { fill = s.cells[(r - 1) * s.n + c] and "black" or "grey" } end,
                on_tap = tap,
            },
            settings = { groups = { { label = T("大小"), options = size_row } }, reset = function() fresh(s.n) end },
            buttons = { { { menu = true, text = T("新游戏"), callback = function() fresh(s.n) end } } },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.cells then
            s = saved.state
            self.render()
        else
            fresh(5)
        end
    end

    self.state = function() return s end
    self.tap = tap
    return self
end

return M
