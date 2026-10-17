--[[--
蜘蛛纸牌。十列；同花色、点数递减的牌才能整段搬动；凑齐 K→A 的同花色整组自动移走。
牌 id = (花色-1)*13 + 点数（1♠ 2♥ 3♦ 4♣，按难度只取前 1/2/4 种，每种重复补足 104 张）；负数 = 背面朝上。
--]]
local T = require("kogames.l10n")

local SUIT_ICONS = { "spade", "heart", "diamond", "club" }
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local UNDO_CAP = 100
local NCOL = 10

local Core = {}

local function rank(id) return (math.abs(id) - 1) % 13 + 1 end
local function suit(id) return math.floor((math.abs(id) - 1) / 13) + 1 end
local function red(id) local s = suit(id) return s == 2 or s == 3 end
Core.rank, Core.suit, Core.red = rank, suit, red

local function copy(t)
    local o = {}
    for i, v in ipairs(t) do o[i] = v end
    return o
end

local function snapshot(s)
    local tab = {}
    for c = 1, NCOL do tab[c] = copy(s.tab[c]) end
    return { tab = tab, stock = copy(s.stock), done = s.done, moves = s.moves }
end

local function push(s)
    s.undo[#s.undo + 1] = snapshot(s)
    if #s.undo > UNDO_CAP then table.remove(s.undo, 1) end
end

function Core.fresh(rng, suits)
    suits = suits or 1
    local deck = {}
    for set = 1, 8 do
        local su = (set - 1) % suits + 1
        for r = 1, 13 do deck[#deck + 1] = (su - 1) * 13 + r end
    end
    rng:shuffle(deck)
    local s = { tab = {}, stock = {}, done = 0, moves = 0, undo = {}, suits = suits }
    local n = 0
    for c = 1, NCOL do
        s.tab[c] = {}
        for i = 1, c <= 4 and 6 or 5 do
            n = n + 1
            local last = i == (c <= 4 and 6 or 5)
            s.tab[c][i] = last and deck[n] or -deck[n]
        end
    end
    for i = n + 1, #deck do s.stock[#s.stock + 1] = deck[i] end
    return s
end

local function flip(col)
    local n = #col
    if n > 0 and col[n] < 0 then col[n] = -col[n] end
end

--- 从 idx 到列底是否同花色、递减且全部朝上
function Core.isRun(col, idx)
    local card = col[idx]
    if not card or card < 0 then return false end
    for i = idx, #col - 1 do
        if col[i + 1] < 0 or suit(col[i + 1]) ~= suit(col[i]) or rank(col[i + 1]) ~= rank(col[i]) - 1 then return false end
    end
    return true
end

function Core.canPlace(card, col)
    local top = col[#col]
    if not top then return true end
    return top > 0 and rank(top) == rank(card) + 1
end

--- 列尾若是同花色 K..A 则移走，返回是否移走
local function collect(s, col)
    local n = #col
    if n < 13 or rank(col[n]) ~= 1 then return false end
    local first = n - 12
    if rank(col[first]) ~= 13 or not Core.isRun(col, first) then return false end
    for i = n, first, -1 do col[i] = nil end
    flip(col)
    s.done = s.done + 1
    return true
end

function Core.moveTab(s, from, idx, to)
    local col, dest = s.tab[from], s.tab[to]
    if from == to or not dest or not Core.isRun(col, idx) or not Core.canPlace(col[idx], dest) then return false end
    push(s)
    for i = idx, #col do dest[#dest + 1] = col[i] end
    for i = #col, idx, -1 do col[i] = nil end
    flip(col)
    collect(s, dest)
    s.moves = s.moves + 1
    return true
end

--- 发牌：每列一张；有空列时不能发
function Core.canDeal(s)
    if #s.stock < NCOL then return false end
    for c = 1, NCOL do if #s.tab[c] == 0 then return false end end
    return true
end

function Core.deal(s)
    if not Core.canDeal(s) then return false end
    push(s)
    for c = 1, NCOL do
        local col = s.tab[c]
        col[#col + 1] = s.stock[#s.stock]
        s.stock[#s.stock] = nil
    end
    for c = 1, NCOL do collect(s, s.tab[c]) end
    s.moves = s.moves + 1
    return true
end

function Core.undo(s)
    local snap = table.remove(s.undo)
    if not snap then return false end
    s.tab, s.stock, s.done, s.moves = snap.tab, snap.stock, snap.done, snap.moves
    return true
end

function Core.won(s) return s.done == 8 end

local M = { id = "spider", title = T("蜘蛛纸牌"), icon = "icon_spider", tier = "B",
    desc = T("十列纸牌，凑齐 K 到 A 即可消除"), help = T("目标：把十列牌里的 8 组「同花色 K 到 A」整列凑齐并移走。\n牌可以叠在点数大 1 的牌上（花色不限），但只有同花色、点数连续递减的牌才能一起搬动；空列可以放任何牌。\n点按一张牌选中它（连同下面的牌），再点目标列。\n没有可走的步时点「发牌」，每列会各发一张；有空列时不能发牌。\n在设置里选 1 / 2 / 4 种花色调整难度（会开始新局）。可撤销多步。"), core = Core }

function M.new(ctx)
    local self = {}
    local s
    local sel -- { col =, idx = }

    local function persist() ctx:save({ state = s }) end

    local function hiddenCount(col)
        local h = 0
        for _, v in ipairs(col) do if v < 0 then h = h + 1 end end
        return h
    end

    local function finish()
        if Core.won(s) and ctx:record("best_moves_" .. s.suits, s.moves, true) then
            ctx:notify(T("新纪录：%d 步", s.moves))
        end
    end

    local function done()
        sel = nil
        finish()
        persist()
        self.render()
    end

    -- 第 k 行（1 起）对应的牌下标；背面牌折叠成一格
    local function rowIndex(col, k)
        local h = hiddenCount(col)
        return k - (h > 0 and 1 or 0) + h, h
    end

    local function tap(r, c)
        if Core.won(s) then return end
        local col = s.tab[c]
        local idx, h = rowIndex(col, r)
        if sel then
            if Core.moveTab(s, sel.col, sel.idx, c) then return done() end
            if sel.col == c and sel.idx == idx then sel = nil return self.render() end
        end
        if col[idx] and col[idx] > 0 and r >= (h > 0 and 2 or 1) and Core.isRun(col, idx) then
            sel = { col = c, idx = idx }
        else
            sel = nil
        end
        self.render()
    end

    local function newGame(suits)
        s, sel = Core.fresh(ctx.rng, suits or (s and s.suits) or 1), nil
        persist()
        self.render()
    end

    local function cardCell(card, selected)
        local cell = { rank = RANKS[rank(card)], icon = "suit_" .. SUIT_ICONS[suit(card)], scale = 0.42 }
        if selected then
            cell.fill, cell.color, cell.icon = "black", "white", cell.icon .. "_w"
        elseif red(card) then
            cell.fill = "grey"
        end
        return cell
    end

    local function cell(r, c)
        local col = s.tab[c]
        if #col == 0 then return r == 1 and { fill = "grey" } or nil end
        local idx, h = rowIndex(col, r)
        if h > 0 and r == 1 then return { text = "×" .. h, fill = "dark", color = "white", scale = 0.36 } end
        local card = col[idx]
        if not card then return nil end
        return cardCell(card, sel and sel.col == c and idx >= sel.idx)
    end

    function self.render()
        local status = T("移动 %d    已完成 %d/8    剩余发牌 %d", s.moves, s.done, math.floor(#s.stock / NCOL))
        if Core.won(s) then status = status .. T("    通关！") end
        local best = ctx:best("best_moves_" .. s.suits)
        if best then status = status .. T("    最佳 %d 步", best) end
        local rows = 8
        for c = 1, NCOL do
            local col = s.tab[c]
            local h = hiddenCount(col)
            rows = math.max(rows, #col - h + (h > 0 and 1 or 0))
        end
        ctx:render({
            title = T("蜘蛛纸牌"),
            status = status,
            grid = { rows = rows, cols = NCOL, ratio = 0.8, cell = cell, on_tap = tap },
            settings = { groups = { { label = T("难度"), options = {
                { text = T("%d 种花色", 1), selected = s.suits == 1, callback = function() newGame(1) end },
                { text = T("%d 种花色", 2), selected = s.suits == 2, callback = function() newGame(2) end },
                { text = T("%d 种花色", 4), selected = s.suits == 4, callback = function() newGame(4) end },
            } } }, reset = function() newGame() end },
            buttons = {
                {
                    { menu = true, text = T("撤销"), enabled = #s.undo > 0, callback = function()
                        if Core.undo(s) then sel = nil persist() self.render() end
                    end },
                    { text = T("发牌"), enabled = #s.stock > 0, callback = function()
                        sel = nil
                        if Core.deal(s) then persist() else ctx:notify(T("有空列时不能发牌")) end
                        self.render()
                    end },
                    { menu = true, text = T("新游戏"), callback = function() newGame() end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.stock then s = saved.state else s = Core.fresh(ctx.rng, 1) end
        self.render()
    end

    self.tap, self.state = tap, function() return s end
    return self
end

return M
