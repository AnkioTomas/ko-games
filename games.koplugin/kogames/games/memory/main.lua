--[[--
记忆翻牌。翻开两张牌，相同则保持翻开，不同则保持亮着，直到下一次点击才盖回去并翻开所点的牌
（不使用计时器，适合墨水屏）。符号选用几何图形和字母，字体里基本都有。
--]]
local T = require("kogames.l10n")
local SIZES = { { 4, 4 }, { 5, 4 }, { 6, 6 } } -- { 行, 列 }

local Core = {}

function Core.fresh(rng, rows, cols)
    local total = rows * cols
    local cards = {}
    for i = 1, total / 2 do cards[2 * i - 1], cards[2 * i] = i, i end
    for i = total, 2, -1 do
        local j = rng:int(i)
        cards[i], cards[j] = cards[j], cards[i]
    end
    return { rows = rows, cols = cols, cards = cards, matched = {}, up = {}, moves = 0, pairs = 0 }
end

function Core.solved(s) return s.pairs * 2 == #s.cards end

--- 点击第 i 张牌，返回是否有效。
function Core.flip(s, i)
    if s.matched[i] or not s.cards[i] then return false end
    for _, u in ipairs(s.up) do if u == i then return false end end
    if #s.up == 2 then s.up = {} end
    s.up[#s.up + 1] = i
    if #s.up == 2 then
        s.moves = s.moves + 1
        local a, b = s.up[1], s.up[2]
        if s.cards[a] == s.cards[b] then
            s.matched[a], s.matched[b] = true, true
            s.pairs = s.pairs + 1
            s.up = {}
        end
    end
    return true
end

local M = { id = "memory", title = T("记忆翻牌"), icon = "grid_view", tier = "A", desc = T("翻牌找出相同的一对"), help = T("目标：找出所有相同的牌对。\n每次点两张牌翻开，相同的保持翻开，不同的会在下一次点击时盖回去。\n牌越多越难，步数（每翻两张算一步）和用时越少越好。\n可选 4×4、4×5、6×6 三种大小。"), core = Core }

function M.new(ctx)
    local self = {}
    local s

    local function key() return "best" .. s.rows .. "x" .. s.cols end
    local function persist() ctx:save({ state = s }) end

    local function fresh(rows, cols)
        s = Core.fresh(ctx.rng, rows, cols)
        s.t0 = ctx.host:now()
        persist()
        self.render()
    end

    local function tapCell(r, c)
        if s.done then return end
        if not Core.flip(s, (r - 1) * s.cols + c) then return end
        if Core.solved(s) then
            s.done = true
            s.elapsed = math.floor(ctx.host:now() - (s.t0 or ctx.host:now()))
            if ctx:record(key(), s.moves, true) then ctx:notify(T("新纪录：%d", s.moves)) end
        end
        persist()
        self.render()
    end

    function self.render()
        local rows, cols = s.rows, s.cols
        local status = T("步数 %d", s.moves)
        local best = ctx:best(key())
        if best then status = status .. T("    最少 %d", best) end
        if s.done then
            status = status .. T("    用时 %d 秒", s.elapsed or 0) .. T("    完成！")
        end
        local up = {}
        for _, i in ipairs(s.up) do up[i] = true end
        local size_row = {}
        for _, sz in ipairs(SIZES) do
            local selected = sz[1] == rows and sz[2] == cols
            size_row[#size_row + 1] = { text = sz[2] .. "×" .. sz[1], selected = selected, callback = function()
                if not selected then fresh(sz[1], sz[2]) end
            end }
        end
        ctx:render({
            title = T("记忆翻牌"),
            status = status,
            grid = {
                rows = rows, cols = cols, gap = true,
                cell = function(r, c)
                    local i = (r - 1) * cols + c
                    if s.matched[i] then return { icon = string.format("sym_%02d", s.cards[i]), fill = "grey", icon_scale = 0.55 } end
                    if up[i] then return { icon = string.format("sym_%02d", s.cards[i]), icon_scale = 0.7 } end
                    return { fill = "dark" }
                end,
                on_tap = tapCell,
            },
            settings = { groups = { { label = T("大小"), options = size_row } }, reset = function() fresh(s.rows, s.cols) end },
            buttons = {
                { { text = T("新游戏"), callback = function() fresh(s.rows, s.cols) end } },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.cards then
            s = saved.state
        else
            fresh(4, 4)
            return
        end
        self.render()
    end

    self.state = function() return s end
    self.tap = tapCell
    return self
end

return M
