--[[--
连连看。点两个相同的图案，如果它们之间能用不超过两个拐弯的线连起来（线只能走空格，可以绕到棋盘外侧），
两个都会消掉。全部消完即过关。没有可连的对时自动洗牌，也可以手动洗牌或点「提示」。
--]]
local T = require("kogames.l10n")

local SIZES = { { 8, 6, 12 }, { 10, 7, 14 }, { 12, 8, 16 } } -- { 行, 列, 图案种类 }
local DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local Core = {}

function Core.fresh(rng, rows, cols, kinds)
    local total = rows * cols
    local cells = {}
    for k = 1, total / 2 do
        local v = (k - 1) % kinds + 1
        cells[2 * k - 1], cells[2 * k] = v, v
    end
    for i = total, 2, -1 do
        local j = rng:int(i)
        cells[i], cells[j] = cells[j], cells[i]
    end
    return { rows = rows, cols = cols, kinds = kinds, cells = cells, left = total, shuffles = 0 }
end

local function at(s, r, c)
    if r < 1 or c < 1 or r > s.rows or c > s.cols then return 0 end -- 棋盘外一圈视为空，线可以绕外侧
    return s.cells[(r - 1) * s.cols + c]
end

--- a、b 两格（序号）能否用不超过两个拐弯的线连接。
function Core.connect(s, a, b)
    if a == b or s.cells[a] == 0 or s.cells[a] ~= s.cells[b] then return false end
    local ra, ca = math.floor((a - 1) / s.cols) + 1, (a - 1) % s.cols + 1
    local rb, cb = math.floor((b - 1) / s.cols) + 1, (b - 1) % s.cols + 1
    local function walk(r, c, d, turns)
        local dr, dc = DIRS[d][1], DIRS[d][2]
        while true do
            r, c = r + dr, c + dc
            if r < 0 or c < 0 or r > s.rows + 1 or c > s.cols + 1 then return false end
            if r == rb and c == cb then return true end
            if at(s, r, c) ~= 0 then return false end
            if turns < 2 then
                local sides = d <= 2 and { 3, 4 } or { 1, 2 }
                for _, nd in ipairs(sides) do
                    if walk(r, c, nd, turns + 1) then return true end
                end
            end
        end
    end
    for d = 1, 4 do
        if walk(ra, ca, d, 0) then return true end
    end
    return false
end

--- 找一对可消除的牌。
function Core.findPair(s)
    local by = {}
    for i, v in ipairs(s.cells) do
        if v ~= 0 then
            by[v] = by[v] or {}
            table.insert(by[v], i)
        end
    end
    for _, list in pairs(by) do
        for x = 1, #list - 1 do
            for y = x + 1, #list do
                if Core.connect(s, list[x], list[y]) then return list[x], list[y] end
            end
        end
    end
end

--- 消除一对；返回是否成功。
function Core.remove(s, a, b)
    if not Core.connect(s, a, b) then return false end
    s.cells[a], s.cells[b] = 0, 0
    s.left = s.left - 2
    return true
end

--- 把剩余的牌重新排列（保证有解，最多重试若干次）。
function Core.shuffle(s, rng)
    local pos, vals = {}, {}
    for i, v in ipairs(s.cells) do
        if v ~= 0 then pos[#pos + 1] = i vals[#vals + 1] = v end
    end
    for _ = 1, 50 do
        rng:shuffle(vals)
        for k, i in ipairs(pos) do s.cells[i] = vals[k] end
        if Core.findPair(s) then break end
    end
    s.shuffles = s.shuffles + 1
end

local M = { id = "lianliankan", title = T("连连看"), icon = "extension", tier = "A", desc = T("连线消除相同的图案"), help = T("目标：消掉所有图案。\n点两个相同的图案，如果能用不超过两个拐弯的线把它们连起来（线只能走空格，也可以绕到棋盘外侧），两个就会消失。\n点错或连不通时，第二次点的图案会变成新的选中项。\n没有可连的图案时会自动洗牌；也可以点「洗牌」，或点「提示」标出一对可消的图案。用时越短越好。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, sel, hint

    local function key() return "best" .. s.rows .. "x" .. s.cols end
    local function persist() ctx:save({ state = s }) end

    local function fresh(rows, cols, kinds)
        s = Core.fresh(ctx.rng, rows, cols, kinds)
        s.t0 = ctx.host:now()
        sel, hint = nil, nil
        persist()
        self.render()
    end

    local function tap(r, c)
        if s.done then return end
        local i = (r - 1) * s.cols + c
        if s.cells[i] == 0 then return end
        hint = nil
        if not sel or sel == i then
            sel = (sel ~= i) and i or nil
        elseif Core.remove(s, sel, i) then
            sel = nil
            if s.left == 0 then
                s.done = true
                s.elapsed = math.floor(ctx.host:now() - (s.t0 or ctx.host:now()))
                if ctx:record(key(), s.elapsed, true) then ctx:notify(T("新纪录：%d 秒", s.elapsed)) end
            elseif not Core.findPair(s) then
                Core.shuffle(s, ctx.rng)
                ctx:notify(T("没有可连的牌，已重新洗牌"))
            end
        else
            sel = i
        end
        persist()
        self.render()
    end

    function self.render()
        local status = T("剩余 %d 张", s.left)
        local best = ctx:best(key())
        if best then status = status .. T("    最快 %d 秒", best) end
        if s.done then status = status .. T("    用时 %d 秒", s.elapsed or 0) .. T("    完成！") end
        local size_row = {}
        for _, sz in ipairs(SIZES) do
            local selected = sz[1] == s.rows and sz[2] == s.cols
            size_row[#size_row + 1] = { text = sz[2] .. "×" .. sz[1], selected = selected, callback = function()
                if not selected then fresh(sz[1], sz[2], sz[3]) end
            end }
        end
        ctx:render({
            title = T("连连看"),
            status = status,
            grid = {
                rows = s.rows, cols = s.cols, gap = true,
                cell = function(r, c)
                    local i = (r - 1) * s.cols + c
                    local v = s.cells[i]
                    if v == 0 then return nil end
                    local name = string.format("sym_%02d", v)
                    if i == sel then return { icon = name .. "_w", fill = "black", icon_scale = 0.7 } end
                    if hint and (i == hint[1] or i == hint[2]) then return { icon = name, fill = "dark", icon_scale = 0.7 } end
                    return { icon = name, fill = "grey", icon_scale = 0.7 }
                end,
                on_tap = tap,
            },
            settings = { groups = { { label = T("大小"), options = size_row } }, reset = function() fresh(s.rows, s.cols, s.kinds) end },
            buttons = {
                { { text = T("提示"), enabled = not s.done, callback = function()
                    local a, b = Core.findPair(s)
                    if a then hint = { a, b } sel = nil end
                    self.render()
                end },
                    { text = T("洗牌"), enabled = not s.done, callback = function()
                        Core.shuffle(s, ctx.rng) sel, hint = nil, nil persist() self.render()
                    end } },
                { { menu = true, text = T("新游戏"), callback = function() fresh(s.rows, s.cols, s.kinds) end } },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.cells then
            s = saved.state
            self.render()
        else
            fresh(8, 6, 12)
        end
    end

    self.state = function() return s end
    self.tap = tap
    return self
end

return M
