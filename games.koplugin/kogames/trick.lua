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
        Core.pass(s, seat)
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
        local cols = 9

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

        local function who(seat)
            if seat == 1 then return T("你") end
            return seat == 2 and T("下家") or T("上家")
        end

        -- 桌面一行：座位名、剩余张数、这一手打出的牌（或「不要」）
        local function tableRow(seat, c)
            local a = s.shown[seat]
            local slots = cols - 2
            if c == 1 then
                local cell = { text = who(seat), scale = 0.2, fill = "grey" }
                if s.landlord == seat then cell.fill, cell.color = "black", "white" end
                return cell
            elseif c == 2 then
                return { text = tostring(#s.hands[seat]), scale = 0.34, fill = (s.turn == seat and s.phase == "play") and "dark" or nil }
            end
            local i = c - 2
            if a == false then return i == 1 and { text = T("不要"), scale = 0.2 } or nil end
            if not a then return nil end
            if #a > slots and i == slots then return { text = "+" .. (#a - slots + 1), scale = 0.26 } end
            local id = a[#a - i + 1]
            return id and Core.cardCell(id) or nil
        end

        function self.render()
            local rows, cols_ = {}, cols
            local status
            if s.phase == "bid" then
                status = T("叫地主？")
            elseif s.phase == "done" then
                local won = Core.humanWon(s)
                status = won and T("你赢了！") or T("你输了")
                if s.mode == "ddz" then status = status .. T("    倍数 ×%d", s.mult) .. (s.spring and T("（春天）") or "") end
            else
                status = s.turn == 1 and (s.last and T("轮到你出牌（压过上一手）") or T("轮到你出牌（任意牌型）")) or T("等待…")
                if s.mode == "ddz" then status = status .. T("    倍数 ×%d", s.mult) end
            end
            local st = ctx.host:load("stats_" .. ctx.id)
            if st and st.games then status = status .. T("    胜 %d / %d", st.wins or 0, st.games) end

            if s.mode == "ddz" and s.landlord then
                rows[#rows + 1] = { label = T("底牌：%s", Core.label(s.bottom)) .. T("　黑底是地主") }
            end

            if s.phase == "bid" then
                rows[#rows + 1] = { { text = T("叫地主"), enabled = s.turn == 1, callback = function()
                    if Core.bid(s, 1, true) == "redeal" then return end
                    afterHuman()
                end }, { text = T("不叫"), enabled = s.turn == 1, callback = function()
                    if Core.bid(s, 1, false) == "redeal" then
                        ctx:notify(T("没人叫地主，重新发牌"))
                        s = Core.deal(ctx.rng, spec.mode)
                    end
                    afterHuman()
                end } }
            elseif s.phase == "done" then
                rows[#rows + 1] = { { text = T("再来一局"), callback = fresh } }
            else
                local mine = s.turn == 1
                local pick = selected()
                rows[#rows + 1] = {
                    { text = T("提示"), enabled = mine, callback = hint },
                    { text = T("不要"), enabled = mine and s.last ~= nil, callback = function()
                        local ok, err = Core.pass(s, 1)
                        if not ok then if err then ctx:notify(err) end return end
                        s.shown[1] = false
                        afterHuman()
                    end },
                    { text = T("出牌"), enabled = mine and #pick > 0, callback = function()
                        local ok, err = Core.play(s, 1, selected())
                        if not ok then ctx:notify(err) return end
                        afterHuman()
                    end },
                }
            end
            rows[#rows + 1] = { { menu = true, text = T("新游戏"), callback = fresh } }

            local disp = {}
            for i = #s.hands[1], 1, -1 do disp[#disp + 1] = s.hands[1][i] end
            ctx:render({
                title = spec.title,
                status = status,
                grid = {
                    rows = 5, cols = cols_, gap = true, ratio = 1.35,
                    cell = function(r, c)
                        if r <= 3 then return tableRow(r == 1 and 3 or r == 2 and 2 or 1, c) end
                        local id = disp[(r - 4) * cols_ + c]
                        return id and Core.cardCell(id, sel[id]) or nil
                    end,
                    on_tap = function(r, c)
                        local id = r > 3 and disp[(r - 4) * cols_ + c]
                        if not id or s.phase ~= "play" then return end
                        sel[id] = not sel[id] or nil
                        self.render()
                    end,
                },
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
        self.select = function(ids) sel = {} for _, id in ipairs(ids) do sel[id] = true end end
        self.advance = function() advance() persist() self.render() end
        return self
    end

    return M
end

return Core
