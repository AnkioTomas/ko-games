--[[--
Klondike 接龙。点按操作：点牌选中（连同下面的牌），再点目标列/收牌区。
牌用整数表示：id = (花色-1)*13 + 点数，花色 1♠ 2♥ 3♦ 4♣；负数 = 背面朝上。
--]]
local T = require("kogames.l10n")

local SUITS = { "♠", "♥", "♦", "♣" }
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local UNDO_CAP = 200

local Core = {}

local function rank(id) return (math.abs(id) - 1) % 13 + 1 end
local function suit(id) return math.floor((math.abs(id) - 1) / 13) + 1 end
local function red(id) local s = suit(id) return s == 2 or s == 3 end
Core.rank, Core.suit, Core.red = rank, suit, red

function Core.label(id) return RANKS[rank(id)] .. SUITS[suit(id)] end

local function copy(t)
    local o = {}
    for i, v in ipairs(t) do o[i] = v end
    return o
end

local function snapshot(s)
    local tab = {}
    for c = 1, 7 do tab[c] = copy(s.tab[c]) end
    return { tab = tab, found = copy(s.found), stock = copy(s.stock), waste = copy(s.waste), moves = s.moves }
end

local function push(s)
    s.undo[#s.undo + 1] = snapshot(s)
    if #s.undo > UNDO_CAP then table.remove(s.undo, 1) end
end

function Core.fresh(rng, draw)
    local deck = {}
    for i = 1, 52 do deck[i] = i end
    rng:shuffle(deck)
    local s = { tab = {}, found = { 0, 0, 0, 0 }, stock = {}, waste = {}, moves = 0, undo = {}, draw = draw or 1 }
    local n = 0
    for c = 1, 7 do
        s.tab[c] = {}
        for i = 1, c do
            n = n + 1
            s.tab[c][i] = i == c and deck[n] or -deck[n]
        end
    end
    for i = n + 1, 52 do s.stock[#s.stock + 1] = deck[i] end
    return s
end

--- 第一张面朝上的位置（整列朝下不会出现，空列返回 nil）
function Core.firstUp(col)
    for i, v in ipairs(col) do if v > 0 then return i end end
end

function Core.canFound(s, card) return s.found[suit(card)] == rank(card) - 1 end

function Core.canTab(s, card, to)
    local col = s.tab[to]
    local top = col[#col]
    if not top then return rank(card) == 13 end
    return top > 0 and rank(top) == rank(card) + 1 and red(top) ~= red(card)
end

local function flip(col)
    local n = #col
    if n > 0 and col[n] < 0 then col[n] = -col[n] end
end

--- 把 from 列第 idx 张起的牌移到 to 列
function Core.moveTab(s, from, idx, to)
    local col = s.tab[from]
    local card = col[idx]
    if from == to or not card or card < 0 or not Core.canTab(s, card, to) then return false end
    push(s)
    local dest = s.tab[to]
    for i = idx, #col do dest[#dest + 1] = col[i] end
    for i = #col, idx, -1 do col[i] = nil end
    flip(col)
    s.moves = s.moves + 1
    return true
end

function Core.moveWaste(s, to)
    local card = s.waste[#s.waste]
    if not card or not Core.canTab(s, card, to) then return false end
    push(s)
    local dest = s.tab[to]
    dest[#dest + 1] = card
    s.waste[#s.waste] = nil
    s.moves = s.moves + 1
    return true
end

--- 从 "waste" 或某列栈顶收牌
function Core.toFound(s, src, col)
    local pile = src == "waste" and s.waste or s.tab[col]
    local card = pile[#pile]
    if not card or card < 0 or not Core.canFound(s, card) then return false end
    push(s)
    s.found[suit(card)] = rank(card)
    pile[#pile] = nil
    if src == "tab" then flip(pile) end
    s.moves = s.moves + 1
    return true
end

function Core.draw(s)
    if #s.stock == 0 and #s.waste == 0 then return false end
    push(s)
    if #s.stock == 0 then
        for i = #s.waste, 1, -1 do s.stock[#s.stock + 1] = s.waste[i] end
        s.waste = {}
    else
        for _ = 1, math.min(s.draw, #s.stock) do
            s.waste[#s.waste + 1] = s.stock[#s.stock]
            s.stock[#s.stock] = nil
        end
    end
    s.moves = s.moves + 1
    return true
end

function Core.undo(s)
    local snap = table.remove(s.undo)
    if not snap then return false end
    s.tab, s.found, s.stock, s.waste, s.moves = snap.tab, snap.found, snap.stock, snap.waste, snap.moves
    return true
end

function Core.won(s)
    return s.found[1] + s.found[2] + s.found[3] + s.found[4] == 52
end

--- 反复把能收的牌收进收牌区，整体算一步；返回收了几张
function Core.autoCollect(s)
    local snap = snapshot(s)
    local n = 0
    local moved = true
    while moved do
        moved = false
        local function try(src, col)
            local pile = src == "waste" and s.waste or s.tab[col]
            local card = pile[#pile]
            if card and card > 0 and Core.canFound(s, card) then
                s.found[suit(card)] = rank(card)
                pile[#pile] = nil
                if src == "tab" then flip(pile) end
                n = n + 1
                moved = true
            end
        end
        try("waste")
        for c = 1, 7 do try("tab", c) end
    end
    if n > 0 then
        s.undo[#s.undo + 1] = snap
        if #s.undo > UNDO_CAP then table.remove(s.undo, 1) end
        s.moves = s.moves + 1
    end
    return n
end

local M = { id = "klondike", title = T("接龙"), icon = "icon_klondike", art = "icon_klondike", tier = "A",
    desc = T("经典 Klondike 纸牌接龙"), core = Core }

function M.new(ctx)
    local self = {}
    local s
    local sel -- { src = "waste" } | { src = "tab", col =, idx = }

    local function persist() ctx:save({ state = s }) end

    local function hiddenCount(col)
        local h = 0
        for _, v in ipairs(col) do if v < 0 then h = h + 1 end end
        return h
    end

    local function finish()
        if Core.won(s) and ctx:record("best_moves", s.moves, true) then
            ctx:notify(T("新纪录：%d 步", s.moves))
        end
    end

    local function done()
        sel = nil
        finish()
        persist()
        self.render()
    end

    local function select(v)
        sel = v
        self.render()
    end

    local function tapColumn(c, k)
        local col = s.tab[c]
        local h = hiddenCount(col)
        local idx = k - (h > 0 and 1 or 0) + h
        local card = col[idx]
        if sel then
            local ok
            if sel.src == "waste" then ok = Core.moveWaste(s, c) else ok = Core.moveTab(s, sel.col, sel.idx, c) end
            if ok then return done() end
            if sel.src == "tab" and sel.col == c and sel.idx == idx then sel = nil return self.render() end
        end
        if card and card > 0 and k >= (h > 0 and 2 or 1) then
            select({ src = "tab", col = c, idx = idx })
        else
            sel = nil
            self.render()
        end
    end

    local function tapFoundation()
        if not sel then return end
        local ok
        if sel.src == "waste" then
            ok = Core.toFound(s, "waste")
        elseif sel.idx == #s.tab[sel.col] then
            ok = Core.toFound(s, "tab", sel.col)
        end
        if ok then done() else sel = nil self.render() end
    end

    local function tap(r, c)
        if Core.won(s) then return end
        if r == 1 then
            if c == 1 then
                sel = nil
                if Core.draw(s) then persist() end
                self.render()
            elseif c == 2 then
                if #s.waste == 0 then sel = nil return self.render() end
                if sel and sel.src == "waste" then sel = nil return self.render() end
                select({ src = "waste" })
            elseif c == 3 then
                sel = nil
                self.render()
            else
                tapFoundation()
            end
        else
            tapColumn(c, r - 1)
        end
    end

    local function newGame()
        s, sel = Core.fresh(ctx.rng, s and s.draw or 1), nil
        persist()
        self.render()
    end

    local function cardCell(card, selected)
        local cell = { text = Core.label(card), scale = 0.55 }
        if selected then
            cell.fill, cell.color = "black", "white"
        elseif red(card) then
            cell.fill = "grey" -- 红花色用浅灰底，灰度屏上与黑花色区分
        end
        return cell
    end

    local function cell(r, c)
        if r == 1 then
            if c == 1 then
                if #s.stock > 0 then return { text = tostring(#s.stock), fill = "dark", color = "white", scale = 0.5 } end
                return { text = #s.waste > 0 and "↺" or "", color = "grey" }
            elseif c == 2 then
                local top = s.waste[#s.waste]
                if not top then return {} end
                return cardCell(top, sel and sel.src == "waste")
            elseif c >= 4 then
                local su = c - 3
                if s.found[su] == 0 then return { text = SUITS[su], color = "grey", scale = 0.55 } end
                return cardCell((su - 1) * 13 + s.found[su])
            end
            return nil
        end
        local col = s.tab[c]
        local k = r - 1
        if #col == 0 then return k == 1 and { text = "—", color = "grey" } or nil end
        local h = hiddenCount(col)
        if h > 0 then
            if k == 1 then return { text = "×" .. h, fill = "dark", color = "white", scale = 0.5 } end
            k = k - 1
        end
        local idx = h + k
        local card = col[idx]
        if not card then return nil end
        return cardCell(card, sel and sel.src == "tab" and sel.col == c and idx >= sel.idx)
    end

    function self.render()
        local found = s.found[1] + s.found[2] + s.found[3] + s.found[4]
        local status = T("移动 %d    已收 %d/52", s.moves, found)
        if Core.won(s) then status = status .. T("    通关！") end
        local best = ctx:best("best_moves")
        if best then status = status .. T("    最佳 %d 步", best) end
        local rows = 7
        for c = 1, 7 do
            local col = s.tab[c]
            local h = hiddenCount(col)
            rows = math.max(rows, math.max(1, #col - h + (h > 0 and 1 or 0)))
        end
        ctx:render({
            title = T("接龙"),
            status = status,
            grid = { rows = rows + 1, cols = 7, ratio = 0.7, cell = cell, on_tap = tap },
            buttons = {
                {
                    { text = T("撤销"), enabled = #s.undo > 0, callback = function()
                        if Core.undo(s) then sel = nil persist() self.render() end
                    end },
                    { text = T("自动收牌"), callback = function()
                        sel = nil
                        if Core.autoCollect(s) > 0 then finish() persist() end
                        self.render()
                    end },
                    { text = T("抽 %d 张", s.draw), callback = function()
                        s.draw = s.draw == 1 and 3 or 1
                        persist()
                        self.render()
                    end },
                    { text = T("新游戏"), callback = newGame },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.tab then s = saved.state else s = Core.fresh(ctx.rng, 1) end
        self.render()
    end

    self.tap, self.state = tap, function() return s end
    return self
end

return M
