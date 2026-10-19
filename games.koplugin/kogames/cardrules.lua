--[[--
出牌类游戏（斗地主、跑得快）共用的牌型规则与电脑出牌。
牌 id：1–52 = 点数 3..K、A、2（每个点数 4 张，花色 1♠ 2♥ 3♣ 4♦），53 小王，54 大王。
点数值 value：3..13 = 3..K，14 = A，15 = 2，16/17 = 小/大王。
牌型 p = { type, key, len, n }：key 是主牌最小点数，len 是顺子/连对/飞机的组数。
opts.pdk = 跑得快规则（无王、无火箭、三带二、飞机可少带仅限最后一手 opts.all）。
--]]
local R = {}

local NAMES = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A", [15] = "2" }
R.SUIT_ICONS = { "spade", "heart", "club", "diamond" }

function R.value(id) return id >= 53 and id - 37 or math.floor((id - 1) / 4) + 3 end
function R.suit(id) return id <= 52 and (id - 1) % 4 + 1 or 0 end
function R.rankText(v) return NAMES[v] or tostring(v) end

local function group(hand)
    local byv, vals = {}, {}
    for _, id in ipairs(hand) do
        local v = R.value(id)
        if not byv[v] then byv[v] = {} vals[#vals + 1] = v end
        table.insert(byv[v], id)
    end
    table.sort(vals)
    return byv, vals
end

local function isRun(vals)
    for i, v in ipairs(vals) do
        if v > 14 or (i > 1 and v ~= vals[i - 1] + 1) then return false end
    end
    return true
end

--- 判定一手牌的牌型，不合法返回 nil。
function R.parse(cards, opts)
    opts = opts or {}
    local n = #cards
    if n == 0 then return nil end
    local cnt, vals = {}, {}
    for _, id in ipairs(cards) do
        local v = R.value(id)
        if not cnt[v] then vals[#vals + 1] = v end
        cnt[v] = (cnt[v] or 0) + 1
    end
    table.sort(vals)
    local nv = #vals
    local function res(t, key, len) return { type = t, key = key, len = len or 1, n = n } end

    if not opts.pdk and n == 2 and cnt[16] and cnt[17] then return res("rocket", 17) end
    if nv == 1 and n == 4 then return res("bomb", vals[1]) end
    if n == 1 then return res("single", vals[1]) end
    if n == 2 and nv == 1 then return res("pair", vals[1]) end

    local allCnt = function(c) for _, v in ipairs(vals) do if cnt[v] ~= c then return false end end return true end
    if n >= 5 and nv == n and isRun(vals) then return res("straight", vals[1], nv) end
    if nv >= (opts.pdk and 2 or 3) and n == 2 * nv and allCnt(2) and isRun(vals) then return res("pairs", vals[1], nv) end

    local trip = {}
    for _, v in ipairs(vals) do if cnt[v] == 3 then trip[#trip + 1] = v end end
    for k = #trip, 1, -1 do
        for i = 1, #trip - k + 1 do
            local run = {}
            for j = 0, k - 1 do run[#run + 1] = trip[i + j] end
            if k == 1 or isRun(run) then
                local rest = n - 3 * k
                local rem = {}
                for _, v in ipairs(vals) do rem[v] = cnt[v] end
                for _, v in ipairs(run) do rem[v] = nil end
                local evenRest = true
                for _, c in pairs(rem) do if c % 2 == 1 then evenRest = false end end
                local name
                if opts.pdk then
                    if rest == 2 * k or (opts.all and rest >= 0 and rest < 2 * k) then name = "plane" end
                else
                    local base = k == 1 and "triple" or "plane"
                    if rest == 0 then name = base
                    elseif rest == k then name = base .. "1"
                    elseif rest == 2 * k and evenRest then name = base .. "2" end
                end
                if name then
                    local t = name
                    if opts.pdk then t = "plane" end
                    return res(t, run[1], k)
                end
            end
        end
    end

    if not opts.pdk then
        for _, v in ipairs(vals) do
            if cnt[v] == 4 then
                local rest = n - 4
                local rem = {}
                for _, x in ipairs(vals) do rem[x] = cnt[x] end
                rem[v] = nil
                local evenRest = true
                for _, c in pairs(rem) do if c % 2 == 1 then evenRest = false end end
                if rest == 2 then return res("four2", v) end
                if rest == 4 and evenRest then return res("four22", v) end
            end
        end
    end
    return nil
end

--- new 能否压过 prev（prev 为 nil 表示首发）。
function R.beats(new, prev)
    if not prev then return true end
    if new.type == "rocket" then return true end
    if prev.type == "rocket" then return false end
    if new.type == "bomb" then return prev.type ~= "bomb" or new.key > prev.key end
    if prev.type == "bomb" then return false end
    return new.type == prev.type and new.len == prev.len and new.key > prev.key
end

local function pickSingles(byv, vals, excl, k)
    local out, used = {}, {}
    for depth = 1, 4 do
        for _, v in ipairs(vals) do
            local id = byv[v][depth]
            if id and not excl[v] and #out < k and not used[id] then
                out[#out + 1] = id
                used[id] = true
            end
        end
    end
    if #out == k then return out end
end

local function pickPairs(byv, vals, excl, k)
    local out = {}
    for _, v in ipairs(vals) do
        if not excl[v] and #byv[v] >= 2 and #out < 2 * k then
            out[#out + 1], out[#out + 2] = byv[v][1], byv[v][2]
        end
    end
    if #out == 2 * k then return out end
end

local function concat(a, b)
    local t = {}
    for _, x in ipairs(a) do t[#t + 1] = x end
    for _, x in ipairs(b or {}) do t[#t + 1] = x end
    return t
end

--- 枚举手牌里各牌型的出法（带牌取最小的），返回 { { cards, p } }。
function R.plays(hand, o)
    o = o or {}
    local byv, vals = group(hand)
    local out = {}
    local function add(cards)
        if not cards then return end
        table.sort(cards)
        local p = R.parse(cards, { pdk = o.pdk, all = #cards == #hand })
        if p then out[#out + 1] = { cards = cards, p = p } end
    end
    local function take(v, n)
        local t = {}
        for i = 1, n do t[i] = byv[v][i] end
        return t
    end
    for _, v in ipairs(vals) do
        local c = #byv[v]
        add(take(v, 1))
        if c >= 2 then add(take(v, 2)) end
        if c >= 3 then
            local main, excl = take(v, 3), { [v] = true }
            add(main)
            if o.pdk then
                add(concat(main, pickSingles(byv, vals, excl, 2)))
            else
                add(concat(main, pickSingles(byv, vals, excl, 1)))
                add(concat(main, pickPairs(byv, vals, excl, 1)))
            end
        end
        if c == 4 then
            add(take(v, 4))
            if not o.pdk then
                local excl = { [v] = true }
                local s2, p2 = pickSingles(byv, vals, excl, 2), pickPairs(byv, vals, excl, 2)
                if s2 then add(concat(take(v, 4), s2)) end
                if p2 then add(concat(take(v, 4), p2)) end
            end
        end
    end
    if not o.pdk and byv[16] and byv[17] then add({ byv[16][1], byv[17][1] }) end

    local function segments(minCnt)
        local segs, cur = {}, {}
        for _, v in ipairs(vals) do
            if v <= 14 and #byv[v] >= minCnt then
                if #cur > 0 and cur[#cur] ~= v - 1 then segs[#segs + 1] = cur cur = {} end
                cur[#cur + 1] = v
            end
        end
        if #cur > 0 then segs[#segs + 1] = cur end
        return segs
    end
    local function windows(minCnt, minLen, per, fn)
        for _, seg in ipairs(segments(minCnt)) do
            for i = 1, #seg do
                for j = i + minLen - 1, #seg do
                    local main, excl = {}, {}
                    for k = i, j do
                        main = concat(main, take(seg[k], per))
                        excl[seg[k]] = true
                    end
                    fn(main, excl, j - i + 1)
                end
            end
        end
    end
    windows(1, 5, 1, function(main) add(main) end)
    windows(2, o.pdk and 2 or 3, 2, function(main) add(main) end)
    windows(3, 2, 3, function(main, excl, k)
        add(main)
        if o.pdk then
            add(concat(main, pickSingles(byv, vals, excl, 2 * k)))
        else
            add(concat(main, pickSingles(byv, vals, excl, k)))
            add(concat(main, pickPairs(byv, vals, excl, k)))
        end
    end)
    return out
end

local function breaksBomb(cards, byv, p)
    if p.type == "bomb" or p.type == "four2" or p.type == "four22" or p.type == "rocket" then return false end
    for _, id in ipairs(cards) do
        if #byv[R.value(id)] == 4 then return true end
    end
    return false
end

--- 电脑选牌。o：pdk、first（必须含 id 1）、teammate（上家是队友）、oppMin（对手最少剩牌）、last（要压的牌型）。
--- 返回牌 id 列表，nil 表示不出。
function R.aiChoose(hand, o)
    local byv = group(hand)
    local plays = R.plays(hand, o)
    local last = o.last
    local list = {}
    for _, pl in ipairs(plays) do
        local ok = R.beats(pl.p, last)
        if ok and o.first then
            ok = false
            for _, id in ipairs(pl.cards) do if id == 1 then ok = true end end
        end
        if ok then list[#list + 1] = pl end
    end
    if #list == 0 then return nil end
    for _, pl in ipairs(list) do
        if #pl.cards == #hand then return pl.cards end
    end
    if last and o.teammate then return nil end

    local function pickBest(filterFn)
        local best, bs
        for _, pl in ipairs(list) do
            if filterFn(pl) then
                local sc = last and (pl.p.key * 10 + #pl.cards) or (pl.p.key * 10 - #pl.cards * 8)
                if not bs or sc < bs then best, bs = pl, sc end
            end
        end
        return best
    end
    local function plain(pl) return pl.p.type ~= "bomb" and pl.p.type ~= "rocket" end
    local best = pickBest(function(pl) return plain(pl) and not breaksBomb(pl.cards, byv, pl.p) end)
        or pickBest(plain)
    if best then
        if last and not o.pdk and best.p.key >= 16 and (o.oppMin or 20) > 5 and #hand > 5 then return nil end
        return best.cards
    end
    local urgent = o.pdk or (o.oppMin or 20) <= 4 or #hand <= 6 or not last
    if not urgent then return nil end
    local bomb = pickBest(function() return true end)
    return bomb and bomb.cards
end

--- 叫地主的牌力估计。
function R.strength(hand)
    local byv = group(hand)
    local s = 0
    if byv[17] then s = s + 3 end
    if byv[16] then s = s + 2 end
    if byv[15] then s = s + #byv[15] end
    if byv[16] and byv[17] then s = s + 2 end
    for v = 3, 15 do if byv[v] and #byv[v] == 4 then s = s + 3 end end
    if byv[14] then s = s + #byv[14] * 0.5 end
    return s
end

return R
