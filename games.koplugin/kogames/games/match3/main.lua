--[[--
消消乐（三消）。点一个方块再点相邻方块交换，交换后能连成三个或以上同图案的横/竖线才算有效，
消除后上方方块落下、顶部补新方块，连锁消除得分翻倍。步数用完结束，没有可走的步时自动洗牌。
没有动画，一步直接结算，适合墨水屏。
--]]
local T = require("kogames.l10n")

local N, KINDS = 8, 6
local LEVELS = { { moves = 20, label = "20 步" }, { moves = 30, label = "30 步" }, { moves = 50, label = "50 步" } }

local Core = {}

--- 找出所有横/竖三连以上的格子，返回 set。
function Core.matches(b)
    local hit, any = {}, false
    local function run(first, step, len)
        local i = 1
        while i <= len do
            local v = b[first + (i - 1) * step]
            local j = i
            while j < len and b[first + j * step] == v do j = j + 1 end
            if v ~= 0 and j - i + 1 >= 3 then
                for k = i, j do hit[first + (k - 1) * step] = true end
                any = true
            end
            i = j + 1
        end
    end
    for r = 1, N do run((r - 1) * N + 1, 1, N) end
    for c = 1, N do run(c, N, N) end
    return hit, any
end

local function swap(b, i, j) b[i], b[j] = b[j], b[i] end

function Core.adjacent(i, j)
    local ri, ci, rj, cj = math.floor((i - 1) / N), (i - 1) % N, math.floor((j - 1) / N), (j - 1) % N
    return math.abs(ri - rj) + math.abs(ci - cj) == 1
end

--- 是否还有能消除的交换。
function Core.hasMove(b)
    for i = 1, N * N do
        local c = (i - 1) % N
        for k = 1, 2 do
            local j = k == 1 and i + 1 or i + N
            if (k == 1 and c < N - 1) or (k == 2 and j <= N * N) then
                swap(b, i, j)
                local _, any = Core.matches(b)
                swap(b, i, j)
                if any then return true, i, j end
            end
        end
    end
    return false
end

function Core.deal(rng)
    for _ = 1, 100 do
        local b = {}
        for i = 1, N * N do b[i] = rng:int(KINDS) end
        -- 初始不允许有现成的三连：把冲突的格子换成不同图案
        for _ = 1, 20 do
            local hit, any = Core.matches(b)
            if not any then break end
            for i in pairs(hit) do b[i] = rng:int(KINDS) end
        end
        local _, any = Core.matches(b)
        if not any and Core.hasMove(b) then return b end
    end
    error("deal failed")
end

--- 消除所有三连并下落补充，返回得分与连锁次数。
local function resolve(s, rng)
    local total, chain = 0, 0
    while true do
        local hit, any = Core.matches(s.board)
        if not any then break end
        chain = chain + 1
        local n = 0
        for i in pairs(hit) do s.board[i] = 0 n = n + 1 end
        total = total + n * 10 * chain
        for c = 1, N do
            local w = N
            for r = N, 1, -1 do
                local v = s.board[(r - 1) * N + c]
                if v ~= 0 then
                    s.board[(w - 1) * N + c] = v
                    if w ~= r then s.board[(r - 1) * N + c] = 0 end
                    w = w - 1
                end
            end
            for r = w, 1, -1 do s.board[(r - 1) * N + c] = rng:int(KINDS) end
        end
    end
    return total, chain
end

function Core.fresh(rng, moves)
    return { board = Core.deal(rng), score = 0, moves = moves, total = moves }
end

--- 交换 i、j：返回 nil（无效）或 得分、连锁数、是否洗牌。
function Core.swapTiles(s, i, j, rng)
    if s.moves <= 0 or not Core.adjacent(i, j) then return nil end
    swap(s.board, i, j)
    local _, any = Core.matches(s.board)
    if not any then swap(s.board, i, j) return nil end
    local gain, chain = resolve(s, rng)
    s.score = s.score + gain
    s.moves = s.moves - 1
    local reshuffled
    if s.moves > 0 and not Core.hasMove(s.board) then
        s.board = Core.deal(rng)
        reshuffled = true
    end
    return gain, chain, reshuffled
end

local M = { id = "match3", title = T("消消乐"), icon = "view_module", tier = "A", desc = T("交换相邻方块，三个相同即消除"), help = T("目标：在限定步数内拿到尽可能高的分数。\n点一个方块选中，再点它上下左右相邻的方块交换。交换后能让三个及以上相同图案连成横线或竖线才有效，否则会弹回。\n消除后上方的方块落下并补充新的，连锁消除每一层分数翻倍。\n看不出下一步？点「提示」会指出一个可以交换的位置。没有可走的步时会自动重新洗牌。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, sel, hint

    local function key() return "best" .. s.total end
    local function persist() ctx:save({ state = s }) end

    local function fresh(moves)
        s = Core.fresh(ctx.rng, moves or (s and s.total) or 30)
        sel, hint = nil, nil
        persist()
        self.render()
    end

    local function tap(r, c)
        if s.moves <= 0 then return end
        local i = (r - 1) * N + c
        hint = nil
        if not sel or sel == i then
            sel = (sel ~= i) and i or nil
        elseif Core.adjacent(sel, i) then
            local gain, chain, reshuffled = Core.swapTiles(s, sel, i, ctx.rng)
            if gain then
                sel = nil
                if chain > 1 then ctx:notify(T("连锁 ×%d  +%d", chain, gain)) end
                if reshuffled then ctx:notify(T("没有可走的步，已重新洗牌")) end
                if s.moves <= 0 then
                    s.over = true
                    if ctx:record(key(), s.score) then ctx:notify(T("新纪录：%d", s.score)) end
                end
            else
                sel = i
            end
        else
            sel = i
        end
        persist()
        self.render()
    end

    function self.render()
        local status = T("得分 %d    剩余 %d 步", s.score, s.moves)
        local best = ctx:best(key())
        if best then status = status .. T("    最高 %d", best) end
        if s.moves <= 0 then status = status .. T("    结束") end
        local size_row = {}
        for _, lv in ipairs(LEVELS) do
            local selected = lv.moves == s.total
            size_row[#size_row + 1] = { text = T(lv.label), selected = selected, callback = function()
                if not selected then fresh(lv.moves) end
            end }
        end
        ctx:render({
            title = T("消消乐"),
            status = status,
            grid = {
                rows = N, cols = N, gap = true,
                cell = function(r, c)
                    local i = (r - 1) * N + c
                    local name = string.format("sym_%02d", s.board[i])
                    if i == sel then return { icon = name .. "_w", fill = "black", icon_scale = 0.7 } end
                    if hint and (i == hint[1] or i == hint[2]) then return { icon = name, fill = "dark", icon_scale = 0.7 } end
                    return { icon = name, fill = "grey", icon_scale = 0.7 }
                end,
                on_tap = tap,
            },
            settings = { groups = { { label = T("步数"), options = size_row } }, reset = function() fresh() end },
            buttons = {
                { { text = T("提示"), enabled = s.moves > 0, callback = function()
                    local ok, a, b = Core.hasMove(s.board)
                    if ok then hint = { a, b } sel = nil end
                    self.render()
                end } },
                { { menu = true, text = T("新游戏"), callback = function() fresh() end } },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.board and #saved.state.board == N * N then
            s = saved.state
            self.render()
        else
            fresh(30)
        end
    end

    self.state = function() return s end
    self.tap = tap
    return self
end

return M
