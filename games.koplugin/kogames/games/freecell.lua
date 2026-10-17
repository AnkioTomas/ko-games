--[[--
空当接龙（FreeCell）。点按操作：点牌选中（连同下面成序列的牌），再点目标列 / 空当 / 收牌位。
牌 id = (花色-1)*13 + 点数，花色 1♠ 2♥ 3♦ 4♣；空当里 0 = 空位。
--]]
local T = require("kogames.l10n")

local SUIT_ICONS = { "spade", "heart", "diamond", "club" }
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local UNDO_CAP = 200
local NCOL = 8

local Core = {}

local function rank(id) return (id - 1) % 13 + 1 end
local function suit(id) return math.floor((id - 1) / 13) + 1 end
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
    return { tab = tab, cells = copy(s.cells), found = copy(s.found), moves = s.moves }
end

local function push(s)
    s.undo[#s.undo + 1] = snapshot(s)
    if #s.undo > UNDO_CAP then table.remove(s.undo, 1) end
end

function Core.fresh(rng, limit)
    local deck = {}
    for i = 1, 52 do deck[i] = i end
    rng:shuffle(deck)
    local s = { tab = {}, cells = { 0, 0, 0, 0 }, found = { 0, 0, 0, 0 }, moves = 0, undo = {}, limit = limit ~= false }
    for c = 1, NCOL do s.tab[c] = {} end
    for i = 1, 52 do
        local col = s.tab[(i - 1) % NCOL + 1]
        col[#col + 1] = deck[i]
    end
    return s
end

local function freeCells(s)
    local n = 0
    for _, v in ipairs(s.cells) do if v == 0 then n = n + 1 end end
    return n
end

local function emptyCols(s, except)
    local n = 0
    for c = 1, NCOL do if c ~= except and #s.tab[c] == 0 then n = n + 1 end end
    return n
end

--- 从 idx 到列底是否是「红黑交替、递减」序列
function Core.isSeq(col, idx)
    if not col[idx] then return false end
    for i = idx, #col - 1 do
        if rank(col[i + 1]) ~= rank(col[i]) - 1 or red(col[i + 1]) == red(col[i]) then return false end
    end
    return true
end

function Core.maxMove(s, to)
    local e = emptyCols(s, to)
    return (freeCells(s) + 1) * (2 ^ e)
end

function Core.canTab(card, col)
    local top = col[#col]
    if not top then return true end
    return rank(top) == rank(card) + 1 and red(top) ~= red(card)
end

function Core.canFound(s, card) return s.found[suit(card)] == rank(card) - 1 end

function Core.moveTab(s, from, idx, to)
    local col, dest = s.tab[from], s.tab[to]
    if from == to or not dest or not Core.isSeq(col, idx) or not Core.canTab(col[idx], dest) then return false end
    if s.limit and #col - idx + 1 > Core.maxMove(s, to) then return false end
    push(s)
    for i = idx, #col do dest[#dest + 1] = col[i] end
    for i = #col, idx, -1 do col[i] = nil end
    s.moves = s.moves + 1
    return true
end

function Core.cellToTab(s, slot, to)
    local card = s.cells[slot]
    if not card or card == 0 or not Core.canTab(card, s.tab[to]) then return false end
    push(s)
    local dest = s.tab[to]
    dest[#dest + 1] = card
    s.cells[slot] = 0
    s.moves = s.moves + 1
    return true
end

function Core.tabToCell(s, from)
    local col = s.tab[from]
    local card = col[#col]
    if not card then return false end
    for i = 1, 4 do
        if s.cells[i] == 0 then
            push(s)
            s.cells[i] = card
            col[#col] = nil
            s.moves = s.moves + 1
            return true
        end
    end
    return false
end

--- src = "tab"（col 为列号）或 "cell"（col 为空当位）
function Core.toFound(s, src, col)
    local card
    if src == "tab" then card = s.tab[col][#s.tab[col]] else card = s.cells[col] end
    if not card or card == 0 or not Core.canFound(s, card) then return false end
    push(s)
    s.found[suit(card)] = rank(card)
    if src == "tab" then s.tab[col][#s.tab[col]] = nil else s.cells[col] = 0 end
    s.moves = s.moves + 1
    return true
end

function Core.undo(s)
    local snap = table.remove(s.undo)
    if not snap then return false end
    s.tab, s.cells, s.found, s.moves = snap.tab, snap.cells, snap.found, snap.moves
    return true
end

function Core.won(s)
    return s.found[1] + s.found[2] + s.found[3] + s.found[4] == 52
end

--- 把能收的牌都收进收牌区，整体算一步；返回收了几张
function Core.autoCollect(s)
    local snap = snapshot(s)
    local n, moved = 0, true
    while moved do
        moved = false
        local function take(card, clear)
            if card and card ~= 0 and Core.canFound(s, card) then
                s.found[suit(card)] = rank(card)
                clear()
                n, moved = n + 1, true
            end
        end
        for i = 1, 4 do take(s.cells[i], function() s.cells[i] = 0 end) end
        for c = 1, NCOL do
            local col = s.tab[c]
            take(col[#col], function() col[#col] = nil end)
        end
    end
    if n > 0 then
        s.undo[#s.undo + 1] = snap
        if #s.undo > UNDO_CAP then table.remove(s.undo, 1) end
        s.moves = s.moves + 1
    end
    return n
end

local M = { id = "freecell", title = T("空当接龙"), icon = "icon_freecell", art = "icon_freecell", tier = "B",
    desc = T("四个空当的纸牌接龙"), help = T("目标：把 52 张牌按花色从 A 到 K 依次收到右上角的四个收牌位。\n所有牌一开始都是明牌。桌面八列中，牌按「红黑交替、点数递减」叠放；空列可以放任何牌。\n左上四个空当每格可暂存一张牌。\n点按一张牌选中它（连同下面已成序列的牌），再点目标列、空当或收牌位。一次能搬的张数受空当和空列数量限制，可用「移动」按钮切换为不限制。\n「自动收牌」会把能收的牌都收走；可撤销任意多步。"), core = Core }

function M.new(ctx)
    local self = {}
    local s
    local sel -- { src = "tab", col =, idx = } | { src = "cell", slot = }

    local function persist() ctx:save({ state = s }) end

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

    local function tapColumn(c, idx)
        local col = s.tab[c]
        if sel then
            local ok
            if sel.src == "cell" then ok = Core.cellToTab(s, sel.slot, c) else ok = Core.moveTab(s, sel.col, sel.idx, c) end
            if ok then return done() end
            if sel.src == "tab" and sel.col == c and sel.idx == idx then sel = nil return self.render() end
        end
        if col[idx] and Core.isSeq(col, idx) then
            sel = { src = "tab", col = c, idx = idx }
        else
            sel = nil
        end
        self.render()
    end

    local function tapCell(slot)
        if sel then
            local ok
            if sel.src == "tab" and sel.idx == #s.tab[sel.col] and s.cells[slot] == 0 then
                ok = Core.tabToCell(s, sel.col)
            end
            if ok then return done() end
            if sel.src == "cell" and sel.slot == slot then sel = nil return self.render() end
        end
        sel = s.cells[slot] ~= 0 and { src = "cell", slot = slot } or nil
        self.render()
    end

    local function tapFoundation()
        if not sel then return end
        local ok
        if sel.src == "cell" then
            ok = Core.toFound(s, "cell", sel.slot)
        elseif sel.idx == #s.tab[sel.col] then
            ok = Core.toFound(s, "tab", sel.col)
        end
        if ok then done() else sel = nil self.render() end
    end

    local function tap(r, c)
        if Core.won(s) then return end
        if r == 1 then
            if c <= 4 then tapCell(c) else tapFoundation() end
        else
            tapColumn(c, r - 1)
        end
    end

    local function newGame()
        s, sel = Core.fresh(ctx.rng, s and s.limit), nil
        persist()
        self.render()
    end

    local function cardCell(card, selected)
        local cell = { rank = RANKS[rank(card)], icon = "suit_" .. SUIT_ICONS[suit(card)], scale = 0.4 }
        if selected then
            cell.fill, cell.color, cell.icon = "black", "white", cell.icon .. "_w"
        elseif red(card) then
            cell.fill = "grey"
        end
        return cell
    end

    local function cell(r, c)
        if r == 1 then
            if c <= 4 then
                local card = s.cells[c]
                if card == 0 then return { fill = "grey", icon = "box", icon_scale = 0.5 } end
                return cardCell(card, sel and sel.src == "cell" and sel.slot == c)
            end
            local su = c - 4
            if s.found[su] == 0 then return { icon = "suit_" .. SUIT_ICONS[su], icon_scale = 0.5, fill = "grey" } end
            return cardCell((su - 1) * 13 + s.found[su])
        end
        local col = s.tab[c]
        local idx = r - 1
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
        for c = 1, NCOL do rows = math.max(rows, #s.tab[c]) end
        ctx:render({
            title = T("空当接龙"),
            status = status,
            grid = { rows = rows + 1, cols = NCOL, ratio = 0.75, cell = cell, on_tap = tap },
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
                    { text = s.limit and T("移动：限制") or T("移动：不限"), callback = function()
                        s.limit = not s.limit
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
        if saved and saved.state and saved.state.cells then s = saved.state else s = Core.fresh(ctx.rng, true) end
        self.render()
    end

    self.tap, self.state = tap, function() return s end
    return self
end

return M
