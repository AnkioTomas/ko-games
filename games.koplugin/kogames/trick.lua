--[[--
出牌类游戏引擎（斗地主 / 跑得快）：一个人对两个电脑，座位 1 是玩家，2 是下家，3 是上家。
Core 只处理状态与规则，没有界面，方便离线测试；界面在 M.new 里。
mode = "ddz"（54 张，叫地主，底牌 3 张，倍数）或 "pdk"（48 张，每人 16 张，持黑桃 3 者先出且首手必带）。
--]]
local T = require("kogames.l10n")
local R = require("kogames.cardrules")

local Core = {}

local function nextSeat(seat) return seat % 3 + 1 end
Core.nextSeat = nextSeat

local function sorted(t) table.sort(t) return t end

function Core.deal(rng, mode)
    local ids = {}
    for id = 1, mode == "ddz" and 54 or 52 do
        -- 跑得快 48 张：去掉大小王外的 2♥ 2♣ 2♦ A♠（52 张里去 4 张）
        if mode == "ddz" or (id ~= 45 and id ~= 50 and id ~= 51 and id ~= 52) then ids[#ids + 1] = id end
    end
    rng:shuffle(ids)
    local per = mode == "ddz" and 17 or 16
    local s = { mode = mode, hands = { {}, {}, {} }, mult = 1, plays = { 0, 0, 0 }, shown = {}, passes = 0 }
    for i, id in ipairs(ids) do
        if i <= per * 3 then table.insert(s.hands[(i - 1) % 3 + 1], id) end
    end
    if mode == "ddz" then
        s.bottom = { ids[52], ids[53], ids[54] }
        sorted(s.bottom)
        s.phase, s.turn, s.bidn = "bid", rng:int(3), 0
    else
        s.phase, s.first = "play", true
        for seat = 1, 3 do
            for _, id in ipairs(s.hands[seat]) do if id == 1 then s.turn = seat end end
        end
    end
    for seat = 1, 3 do sorted(s.hands[seat]) end
    return s
end

function Core.opts(s) return { pdk = s.mode == "pdk" } end

--- 叫地主 / 不叫。返回 "redeal" 表示三家都不叫。
function Core.bid(s, seat, call)
    s.bidn = s.bidn + 1
    s.bids = s.bids or {}
    s.bids[seat] = call
    if call then
        s.landlord, s.phase, s.turn = seat, "play", seat
        for _, id in ipairs(s.bottom) do table.insert(s.hands[seat], id) end
        sorted(s.hands[seat])
        s.shown = {}
    elseif s.bidn >= 3 then
        return "redeal"
    else
        s.turn = nextSeat(seat)
    end
end

--- 是否有能压过上一手的牌（跑得快要得起必须出）。
function Core.canBeat(s, seat)
    if not s.last then return true end
    local o = Core.opts(s)
    for _, pl in ipairs(R.plays(s.hands[seat], o)) do
        if R.beats(pl.p, s.last.p) then return true end
    end
    return false
end

--- 跑得快：下家只剩一张（报单）时，出单张必须出最大的。
function Core.mustMax(s, seat)
    return s.mode == "pdk" and #s.hands[nextSeat(seat)] == 1
end

--- 校验并解析一手牌：返回牌型或 nil, 原因。
function Core.validate(s, seat, cards)
    if s.phase ~= "play" or s.turn ~= seat then return nil, T("还没轮到你") end
    local has = {}
    for _, id in ipairs(s.hands[seat]) do has[id] = true end
    for _, id in ipairs(cards) do if not has[id] then return nil, T("牌不在手里") end end
    local p = R.parse(cards, { pdk = s.mode == "pdk", all = #cards == #s.hands[seat] })
    if not p then return nil, T("这不是合法牌型") end
    if s.first then
        local ok
        for _, id in ipairs(cards) do if id == 1 then ok = true end end
        if not ok then return nil, T("首手必须带黑桃 3") end
    end
    if not R.beats(p, s.last and s.last.p) then return nil, T("压不过上一手") end
    if p.type == "single" and Core.mustMax(s, seat) then
        local top = 0
        for _, id in ipairs(s.hands[seat]) do top = math.max(top, R.value(id)) end
        if p.key < top then return nil, T("下家报单，单张必须出最大的") end
    end
    return p
end

local function finish(s, seat)
    s.phase, s.winner = "done", seat
    if s.mode == "ddz" then
        local spring
        if seat == s.landlord then
            spring = true
            for k = 1, 3 do if k ~= s.landlord and s.plays[k] > 0 then spring = false end end
        else
            spring = s.plays[s.landlord] <= 1
        end
        if spring then s.mult, s.spring = s.mult * 2, true end
    end
end

function Core.play(s, seat, cards)
    local p, err = Core.validate(s, seat, cards)
    if not p then return false, err end
    if not s.last then s.shown = {} end
    local drop = {}
    for _, id in ipairs(cards) do drop[id] = true end
    local keep = {}
    for _, id in ipairs(s.hands[seat]) do if not drop[id] then keep[#keep + 1] = id end end
    s.hands[seat] = keep
    local copy = {}
    for i, id in ipairs(cards) do copy[i] = id end
    sorted(copy)
    s.last = { seat = seat, p = p, cards = copy }
    s.shown[seat] = copy
    s.passes, s.first = 0, nil
    s.plays[seat] = s.plays[seat] + 1
    if p.type == "bomb" or p.type == "rocket" then s.mult = s.mult * 2 end
    if #keep == 0 then finish(s, seat) else s.turn = nextSeat(seat) end
    return true
end

function Core.pass(s, seat)
    if s.phase ~= "play" or s.turn ~= seat or not s.last then return false end
    if s.mode == "pdk" and Core.canBeat(s, seat) then return false, T("要得起必须出") end
    s.passes = s.passes + 1
    s.shown[seat] = false
    if s.passes >= 2 then
        s.turn, s.last, s.passes = s.last.seat, nil, 0
    else
        s.turn = nextSeat(seat)
    end
    return true
end

local function counts(s) return #s.hands[1], #s.hands[2], #s.hands[3] end

--- 电脑出牌的参数。
function Core.aiOpts(s, seat)
    local o = { pdk = s.mode == "pdk", last = s.last and s.last.p or nil, first = s.first }
    local oppMin = 99
    for k = 1, 3 do
        if k ~= seat and (s.mode == "pdk" or k == s.landlord or seat == s.landlord) then
            oppMin = math.min(oppMin, #s.hands[k])
        end
    end
    o.oppMin = oppMin
    o.mustMax = Core.mustMax(s, seat)
    if s.mode == "ddz" and s.last and s.last.seat ~= seat and seat ~= s.landlord and s.last.seat ~= s.landlord then
        o.teammate = true
    end
    return o
end

function Core.aiAct(s, seat)
    if s.phase == "bid" then
        local strong = R.strength(s.hands[seat])
        local last = s.bidn == 2
        return Core.bid(s, seat, strong >= (last and 3 or 4.5))
    end
    local o = Core.aiOpts(s, seat)
    local cards = R.aiChoose(s.hands[seat], o)
    if cards then
        local ok = Core.play(s, seat, cards)
        if ok then return end
    end
    if s.last then
        if not Core.pass(s, seat) then
            -- 兜底：必须出却没选出牌时，随便出一手能压的
            for _, pl in ipairs(R.plays(s.hands[seat], Core.opts(s))) do
                if Core.play(s, seat, pl.cards) then return end
            end
        end
    else
        Core.play(s, seat, { s.hands[seat][1] })
    end
end

--- 让电脑一直出到轮到玩家或结束。返回 "redeal" 表示要重新发牌。
function Core.step(s)
    local guard = 0
    while s.phase ~= "done" and s.turn ~= 1 and guard < 500 do
        guard = guard + 1
        if Core.aiAct(s, s.turn) == "redeal" then return "redeal" end
    end
end

--- 玩家（座位 1）是否获胜。
function Core.humanWon(s)
    if s.mode == "pdk" then return s.winner == 1 end
    return (s.winner == s.landlord) == (s.landlord == 1)
end

function Core.label(cards)
    local t = {}
    for i = #cards, 1, -1 do
        local v = R.value(cards[i])
        t[#t + 1] = v == 16 and T("小王") or v == 17 and T("大王") or R.rankText(v)
    end
    return table.concat(t, " ")
end

local RED = { [2] = true, [4] = true }

function Core.cardCell(id, selected)
    local v = R.value(id)
    local cell
    if v >= 16 then
        cell = { text = v == 16 and T("小王") or T("大王"), scale = 0.19, fill = "grey" }
        if selected then cell.fill, cell.color = "black", "white" end
        return cell
    end
    local su = R.suit(id)
    cell = { rank = R.rankText(v), icon = "suit_" .. R.SUIT_ICONS[su], scale = 0.2 }
    if selected then
        cell.fill, cell.color, cell.icon = "black", "white", cell.icon .. "_w"
    elseif RED[su] then
        cell.fill = "grey"
    end
    return cell
end

--- 构造一个出牌游戏的定义。
function Core.define(spec)
    local M = { id = spec.id, title = spec.title, icon = spec.icon, tier = "B", desc = spec.desc, help = spec.help, core = Core }

    function M.new(ctx)
        local self = {}
        local s, sel = nil, {}

        local function persist() ctx:save({ state = s }) end

        local function bump(key)
            local st = ctx.host:load("stats_" .. ctx.id) or {}
            st[key] = (st[key] or 0) + 1
            ctx.host:save("stats_" .. ctx.id, st)
        end

        local function advance()
            if Core.step(s) == "redeal" then
                ctx:notify(T("没人叫地主，重新发牌"))
                s = Core.deal(ctx.rng, spec.mode)
                return advance()
            end
            if s.phase == "done" and not s.counted then
                s.counted = true
                bump("games")
                if Core.humanWon(s) then bump("wins") end
            end
        end

        local function fresh()
            s, sel = Core.deal(ctx.rng, spec.mode), {}
            advance()
            persist()
            self.render()
        end

        local function selected()
            local t = {}
            for _, id in ipairs(s.hands[1]) do if sel[id] then t[#t + 1] = id end end
            return t
        end

        local function afterHuman()
            sel = {}
            advance()
            persist()
            self.render()
        end

        local function hint()
            local o = Core.aiOpts(s, 1)
            o.teammate = nil
            local cards = R.aiChoose(s.hands[1], o)
            sel = {}
            if cards then for _, id in ipairs(cards) do sel[id] = true end
            elseif s.last then ctx:notify(T("没有能压过的牌")) end
            self.render()
        end

        local CW, CH = 100, 111
        local CARD_W, CARD_H = 11, 17
        local PW, PH = 9, 13.5

        -- 一张牌：左上角是点数和花色，叠放时只露出这一角
        local function drawCard(d, id, x, y, w, h, selected)
            local v = R.value(id)
            local red = v < 16 and RED[R.suit(id)]
            d.rect(x, y, w, h, selected and "black" or red and "grey" or "white")
            d.frame(x, y, w, h, "black", 0.5)
            local ink = selected and "white" or "black"
            local cx = x + 3.3
            if v >= 16 then
                d.icon(v == 16 and "joker_small" or "joker_big", cx, y + 5.5, 5.5)
                if v == 17 then d.icon("crown", cx, y + 11, 3.4) end
                return
            end
            local rank = R.rankText(v)
            d.text(rank, cx, y + 3.2, #rank > 1 and 2.4 or 3.0, ink)
            d.icon("suit_" .. R.SUIT_ICONS[R.suit(id)] .. (selected and "_w" or ""), cx, y + 8.2, 3.2)
        end

        -- 一行打出的牌；align = "left" | "right" | "center"
        local function drawPlayed(d, cards, y, align)
            local x0, x1 = 15, CW - 2
            local n = #cards
            local step = math.min(4.4, n > 1 and (x1 - x0 - PW) / (n - 1) or 4.4)
            local width = PW + (n - 1) * step
            local x = align == "left" and x0 or align == "right" and x1 - width or x0 + (x1 - x0 - width) / 2
            for i = n, 1, -1 do drawCard(d, cards[i], x + (n - i) * step, y, PW, PH) end
        end

        local function drawBack(d, x, y, n)
            d.rect(x, y, 6, 8.5, "dark")
            d.frame(x, y, 6, 8.5, "black", 0.4)
            d.text(tostring(n), x + 10.5, y + 4.4, 3.6, "black")
        end

        local function drawSeat(d, seat, x, y)
            local turn = s.turn == seat and s.phase ~= "done"
            if turn then d.ring(x + 5, y + 6, 8, "black", 0.8) end
            d.icon("person", x + 5, y + 7, 9)
            if s.landlord == seat then d.icon("crown", x + 5, y - 1.5, 5) end
            drawBack(d, x + 15, y + 2, #s.hands[seat])
        end

        -- 手牌：不超过 10 张排一行，更多时分两行错落摆放
        local function handLayout(n)
            local pos = {}
            local rows = n > 10 and 2 or 1
            local per = math.ceil(n / rows)
            local step = math.min(9, (CW - 2 - CARD_W) / math.max(per - 1, 1))
            for i = 1, n do
                local row = rows == 1 and 1 or (i <= per and 1 or 2)
                local k = row == 1 and i or i - per
                local cnt = row == 1 and per or n - per
                local width = CARD_W + (cnt - 1) * step
                pos[i] = { x = (CW - width) / 2 + (k - 1) * step, y = rows == 1 and 91 or (row == 1 and 80 or 92) }
            end
            return pos
        end

        function self.render()
            local disp = {}
            for i = #s.hands[1], 1, -1 do disp[#disp + 1] = s.hands[1][i] end
            local pos = handLayout(#disp)
            local mine = s.turn == 1
            local pick = selected()

            local rows = {}
            if s.phase == "bid" then
                rows[#rows + 1] = { { text = T("叫地主"), enabled = mine, callback = function()
                    if Core.bid(s, 1, true) == "redeal" then return end
                    afterHuman()
                end }, { text = T("不叫"), enabled = mine, callback = function()
                    if Core.bid(s, 1, false) == "redeal" then
                        ctx:notify(T("没人叫地主，重新发牌"))
                        s = Core.deal(ctx.rng, spec.mode)
                    end
                    afterHuman()
                end } }
            elseif s.phase == "done" then
                rows[#rows + 1] = { { text = T("再来一局"), callback = fresh } }
            else
                rows[#rows + 1] = {
                    { key = "hint", icon = "bulb", enabled = mine, callback = hint },
                    { key = "pass", icon = "cross", enabled = mine and s.last ~= nil, callback = function()
                        local ok, err = Core.pass(s, 1)
                        if not ok then if err then ctx:notify(err) end return end
                        s.shown[1] = false
                        afterHuman()
                    end },
                    { key = "play", icon = "check", enabled = mine and #pick > 0, callback = function()
                        local ok, err = Core.play(s, 1, selected())
                        if not ok then ctx:notify(err) return end
                        afterHuman()
                    end },
                }
            end
            rows[#rows + 1] = { { menu = true, text = T("新游戏"), callback = fresh } }

            ctx:render({
                title = spec.title,
                canvas = {
                    w = CW, h = CH,
                    draw = function(d)
                        drawSeat(d, 3, 3, 8)
                        drawSeat(d, 2, CW - 31, 8)
                        if s.mode == "ddz" and s.landlord then
                            for i, id in ipairs(s.bottom) do drawCard(d, id, CW / 2 - 15 + (i - 1) * 10, 2, 9, 12) end
                            d.text("×" .. s.mult, CW / 2, 19, 3.8, "black")
                        elseif s.mode == "ddz" then
                            d.text("×" .. s.mult, CW / 2, 10, 3.8, "black")
                        end
                        d.frame(1, 23, CW - 2, 54, "dark", 0.4)
                        local lines = { { 3, "left" }, { 2, "right" }, { 1, "center" } }
                        for k, ln in ipairs(lines) do
                            local y = 26 + (k - 1) * 17.5
                            local seat = ln[1]
                            if seat == 1 then
                                d.icon("person", 8, y + 7, 8)
                                if s.landlord == 1 then d.icon("crown", 8, y - 0.5, 4.5) end
                            end
                            local a = s.shown[seat]
                            if a == false then d.text(T("不要"), ln[2] == "right" and CW - 12 or 22, y + 7, 4.2, "dark")
                            elseif a then drawPlayed(d, a, y, ln[2]) end
                        end
                        if s.phase == "bid" then
                            d.text(T("叫地主？"), CW / 2, 50, 6, "black")
                            for seat = 3, 2, -1 do
                                if s.bids and s.bids[seat] == false then
                                    d.text(T("不叫"), seat == 3 and 22 or CW - 12, seat == 3 and 33 or 50.5, 4.2, "dark")
                                end
                            end
                        elseif s.phase == "done" then
                            d.rect(CW / 2 - 24, 34, 48, 26, "white")
                            d.frame(CW / 2 - 24, 34, 48, 26, "black", 0.7)
                            d.text(Core.humanWon(s) and T("你赢了！") or T("你输了"), CW / 2, 43, 6.5, "black")
                            if s.mode == "ddz" then
                                d.text("×" .. s.mult .. (s.spring and T("（春天）") or ""), CW / 2, 53, 4, "black")
                            end
                        end
                        for i, id in ipairs(disp) do
                            local q = pos[i]
                            drawCard(d, id, q.x, q.y - (sel[id] and 4 or 0), CARD_W, CARD_H, sel[id])
                        end
                    end,
                    on_tap = function(x, y)
                        if s.phase ~= "play" then return end
                        for i = #disp, 1, -1 do
                            local q, id = pos[i], disp[i]
                            local top = q.y - (sel[id] and 4 or 0)
                            if x >= q.x and x < q.x + CARD_W and y >= top and y < top + CARD_H then
                                sel[id] = not sel[id] or nil
                                self.render()
                                return
                            end
                        end
                    end,
                },
                settings = { groups = {}, reset = fresh },
                buttons = rows,
            })
        end

        function self.start()
            local saved = ctx:load()
            if saved and saved.state and saved.state.hands and saved.state.mode == spec.mode and saved.state.phase ~= "done" then
                s = saved.state
                s.shown = s.shown or {}
                advance()
                self.render()
            else
                fresh()
            end
        end

        self.state = function() return s end
        self.selected = selected
        self.select = function(ids) sel = {} for _, id in ipairs(ids) do sel[id] = true end end
        self.advance = function() advance() persist() self.render() end
        return self
    end

    return M
end

return Core
