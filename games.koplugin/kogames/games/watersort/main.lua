--[[--
倒水排序。每行是一根试管（左边是管底），每种颜色（图案）有 4 份。点一根管选中，再点另一根，
把选中管顶上连续同色的部分倒过去：目标管必须是空的，或顶部同色且有空位。全部分拣成纯色即过关。
--]]
local T = require("kogames.l10n")
local CAP = 4
local LEVELS = { { colors = 4, label = "简单" }, { colors = 6, label = "普通" }, { colors = 8, label = "困难" } }

local Core = {}

function Core.fresh(rng, colors)
    local units = {}
    for k = 1, colors do for _ = 1, CAP do units[#units + 1] = k end end
    local tubes
    repeat
        for i = #units, 2, -1 do
            local j = rng:int(i)
            units[i], units[j] = units[j], units[i]
        end
        tubes = {}
        for t = 1, colors do
            tubes[t] = {}
            for p = 1, CAP do tubes[t][p] = units[(t - 1) * CAP + p] end
        end
        tubes[colors + 1], tubes[colors + 2] = {}, {}
        local sorted = 0
        for t = 1, colors do
            local same = true
            for p = 2, CAP do if tubes[t][p] ~= tubes[t][1] then same = false end end
            if same then sorted = sorted + 1 end
        end
    until sorted == 0
    return { colors = colors, tubes = tubes, moves = 0, hist = {} }
end

local function run(tube)
    local top = tube[#tube]
    local n = 0
    for p = #tube, 1, -1 do
        if tube[p] == top then n = n + 1 else break end
    end
    return top, n
end

function Core.canPour(s, a, b)
    if a == b then return false end
    local ta, tb = s.tubes[a], s.tubes[b]
    if #ta == 0 or #tb >= CAP then return false end
    if #tb == 0 then
        -- 倒进空管只有在能让局面前进时才有意义：源管不是纯色
        local _, n = run(ta)
        return n < #ta
    end
    return run(ta) == tb[#tb]
end

function Core.pour(s, a, b)
    if not Core.canPour(s, a, b) then return false end
    local ta, tb = s.tubes[a], s.tubes[b]
    local top, n = run(ta)
    local moved = 0
    while moved < n and #tb < CAP do
        ta[#ta] = nil
        tb[#tb + 1] = top
        moved = moved + 1
    end
    s.moves = s.moves + 1
    s.hist[#s.hist + 1] = { a, b, moved }
    return true
end

function Core.undo(s)
    local h = table.remove(s.hist)
    if not h then return false end
    local a, b, n = h[1], h[2], h[3]
    for _ = 1, n do
        local v = s.tubes[b][#s.tubes[b]]
        s.tubes[b][#s.tubes[b]] = nil
        s.tubes[a][#s.tubes[a] + 1] = v
    end
    s.moves = s.moves - 1
    return true
end

function Core.solved(s)
    for _, t in ipairs(s.tubes) do
        if #t > 0 then
            if #t ~= CAP then return false end
            for p = 2, CAP do if t[p] ~= t[1] then return false end end
        end
    end
    return true
end

local M = { id = "watersort", title = T("倒水排序"), icon = "apps", tier = "A", desc = T("把相同图案倒进同一根管"), help = T("目标：让每根试管里只有同一种图案（并且装满 4 份）。\n每行是一根试管，左边是管底。点一根管选中，再点另一根管，把选中管顶上连续相同的图案倒过去。\n目标管必须是空的，或者最上面的图案相同且还有空位。\n倒错了可以撤销。图案种类越多越难。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, sel

    local function key() return "best" .. s.colors end
    local function persist() ctx:save({ state = s }) end

    local function fresh(colors)
        s = Core.fresh(ctx.rng, colors or (s and s.colors) or 6)
        sel = nil
        persist()
        self.render()
    end

    local function tap(r)
        if s.done then return end
        if not sel then
            if #s.tubes[r] > 0 then sel = r end
        elseif sel == r then
            sel = nil
        elseif Core.pour(s, sel, r) then
            sel = nil
            if Core.solved(s) then
                s.done = true
                if ctx:record(key(), s.moves, true) then ctx:notify(T("新纪录：%d", s.moves)) end
            end
        elseif #s.tubes[r] > 0 then
            sel = r
        else
            sel = nil
        end
        persist()
        self.render()
    end

    function self.render()
        local status = T("步数 %d", s.moves)
        local best = ctx:best(key())
        if best then status = status .. T("    最少 %d", best) end
        if s.done then status = status .. T("    完成！") end
        local lv_row = {}
        for _, lv in ipairs(LEVELS) do
            local selected = lv.colors == s.colors
            lv_row[#lv_row + 1] = { text = T(lv.label), selected = selected, callback = function()
                if not selected then fresh(lv.colors) end
            end }
        end
        ctx:render({
            title = T("倒水排序"),
            status = status,
            grid = {
                rows = #s.tubes, cols = CAP, gap = true, ratio = 0.8,
                cell = function(r, c)
                    local v = s.tubes[r][c]
                    if not v then return r == sel and { fill = "dark" } or nil end
                    local name = string.format("sym_%02d", v)
                    if r == sel then return { icon = name .. "_w", fill = "black", icon_scale = 0.7 } end
                    return { icon = name, fill = "grey", icon_scale = 0.7 }
                end,
                on_tap = tap,
            },
            settings = { groups = { { label = T("难度"), options = lv_row } }, reset = function() fresh() end },
            buttons = {
                { { menu = true, text = T("撤销"), enabled = #s.hist > 0, callback = function()
                    if Core.undo(s) then s.done = nil sel = nil persist() self.render() end
                end },
                    { menu = true, text = T("新游戏"), callback = function() fresh() end } },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.tubes and saved.state.hist then
            s = saved.state
            self.render()
        else
            fresh(6)
        end
    end

    self.state = function() return s end
    self.tap = tap
    return self
end

return M
