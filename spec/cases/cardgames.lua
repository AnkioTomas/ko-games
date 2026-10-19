return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local R = require("kogames.cardrules")
    local Trick = require("kogames.trick")

    -- 用点数值造牌：vals = { 3, 3, 4 }，同点数依次取不同花色
    local function cards(vals)
        local used, out = {}, {}
        for _, v in ipairs(vals) do
            used[v] = (used[v] or 0) + 1
            out[#out + 1] = v >= 16 and v + 37 or (v - 3) * 4 + used[v]
        end
        return out
    end
    local function parse(vals, o) return R.parse(cards(vals), o) end

    test("cardrules: ddz combo types", function()
        local function ty(vals) local p = parse(vals) return p and p.type end
        assert(ty({ 5 }) == "single" and ty({ 5, 5 }) == "pair" and ty({ 5, 5, 5 }) == "triple")
        assert(ty({ 5, 5, 5, 9 }) == "triple1" and ty({ 5, 5, 5, 9, 9 }) == "triple2")
        assert(ty({ 3, 4, 5, 6, 7 }) == "straight" and ty({ 3, 4, 5, 6 }) == nil)
        assert(ty({ 10, 11, 12, 13, 14 }) == "straight" and ty({ 11, 12, 13, 14, 15 }) == nil)
        assert(ty({ 3, 3, 4, 4, 5, 5 }) == "pairs" and ty({ 3, 3, 4, 4 }) == nil)
        assert(ty({ 3, 3, 3, 4, 4, 4 }) == "plane" and ty({ 3, 3, 3, 4, 4, 4, 7, 8 }) == "plane1")
        assert(ty({ 3, 3, 3, 4, 4, 4, 7, 7, 9, 9 }) == "plane2")
        assert(ty({ 7, 7, 7, 7 }) == "bomb" and ty({ 16, 17 }) == "rocket")
        assert(ty({ 7, 7, 7, 7, 3, 4 }) == "four2" and ty({ 7, 7, 7, 7, 3, 3, 9, 9 }) == "four22")
        assert(ty({ 3, 5 }) == nil and ty({ 3, 3, 3, 3, 3 }) == nil)
    end)

    test("cardrules: beats", function()
        local function p(vals) return parse(vals) end
        assert(R.beats(p({ 6 }), p({ 5 })) and not R.beats(p({ 5 }), p({ 5 })))
        assert(not R.beats(p({ 6, 6 }), p({ 5 })))
        assert(R.beats(p({ 3, 3, 3, 3 }), p({ 15, 15 })) and not R.beats(p({ 15, 15 }), p({ 3, 3, 3, 3 })))
        assert(R.beats(p({ 4, 4, 4, 4 }), p({ 3, 3, 3, 3 })) and R.beats(p({ 16, 17 }), p({ 15, 15, 15, 15 })))
        assert(R.beats(p({ 4, 5, 6, 7, 8 }), p({ 3, 4, 5, 6, 7 })) and not R.beats(p({ 4, 5, 6, 7, 8, 9 }), p({ 3, 4, 5, 6, 7 })))
    end)

    test("cardrules: pdk combos", function()
        local o = { pdk = true }
        assert(parse({ 5, 5, 5, 9, 9 }, o).type == "plane" and not parse({ 5, 5, 5, 9 }, o))
        assert(R.parse(cards({ 5, 5, 5, 9 }), { pdk = true, all = true }))
        assert(parse({ 3, 3, 4, 4 }, o).type == "pairs" and not parse({ 16, 17 }, o))
        assert(parse({ 7, 7, 7, 7 }, o).type == "bomb")
    end)

    test("cardrules: enumerated plays are all legal and cover hint", function()
        for seed = 1, 20 do
            local s = Trick.deal(Rng.new(seed), "ddz")
            local hand = s.hands[1]
            for _, pl in ipairs(R.plays(hand, {})) do
                assert(R.parse(pl.cards, {}), "plays produced an illegal hand")
            end
            assert(R.aiChoose(hand, {}), "ai must lead")
        end
    end)

    test("trick: deal sizes", function()
        local d = Trick.deal(Rng.new(3), "ddz")
        assert(#d.hands[1] == 17 and #d.hands[2] == 17 and #d.hands[3] == 17 and #d.bottom == 3)
        local seen = {}
        for k = 1, 3 do for _, id in ipairs(d.hands[k]) do seen[id] = true end end
        for _, id in ipairs(d.bottom) do seen[id] = true end
        for id = 1, 54 do assert(seen[id]) end
        local p = Trick.deal(Rng.new(3), "pdk")
        assert(#p.hands[1] == 16 and #p.hands[2] == 16 and #p.hands[3] == 16)
        local holder
        for k = 1, 3 do for _, id in ipairs(p.hands[k]) do assert(id ~= 45 and id ~= 50) if id == 1 then holder = k end end end
        assert(p.turn == holder and p.first)
    end)

    local function simulate(mode, seed)
        local rng = Rng.new(seed)
        local s = Trick.deal(rng, mode)
        local guard = 0
        while s.phase ~= "done" do
            guard = guard + 1
            assert(guard < 2000, "game did not finish")
            if s.phase == "bid" then
                if Trick.aiAct(s, s.turn) == "redeal" then s = Trick.deal(rng, mode) end
            else
                Trick.aiAct(s, s.turn)
            end
        end
        assert(#s.hands[s.winner] == 0)
        return s
    end

    test("trick: AI-only games finish for both modes", function()
        for seed = 1, 60 do
            local d = simulate("ddz", seed)
            assert(d.landlord and d.mult >= 1)
            simulate("pdk", seed)
        end
    end)

    test("trick: pdk forces play when a beat exists, ddz allows pass", function()
        local s = Trick.deal(Rng.new(1), "pdk")
        s.turn, s.first = 1, nil
        s.hands[1] = { 40 }
        s.last = { seat = 3, p = R.parse({ 8 }, { pdk = true }), cards = { 8 } }
        s.passes = 0
        assert(not Trick.pass(s, 1))
        s.last.p = R.parse({ 52 }, { pdk = true })
        assert(Trick.pass(s, 1))
        local d = Trick.deal(Rng.new(1), "ddz")
        d.phase, d.landlord, d.turn = "play", 1, 1
        d.last = { seat = 2, p = R.parse({ 8 }, {}), cards = { 8 } }
        assert(Trick.pass(d, 1))
    end)

    test("cardrules: four-with-two rejects rocket wings; pdk short last plane is enumerated", function()
        assert(not parse({ 7, 7, 7, 7, 16, 17 }))
        local hand = cards({ 5, 5, 5, 9 })
        local found
        for _, pl in ipairs(R.plays(hand, { pdk = true })) do if #pl.cards == 4 then found = true end end
        assert(found)
        local s = Trick.deal(Rng.new(1), "pdk")
        s.turn, s.first, s.passes = 1, nil, 0
        s.hands[1] = hand
        s.last = { seat = 3, p = R.parse(cards({ 4, 4, 4, 8, 8 }), { pdk = true }), cards = cards({ 4, 4, 4, 8, 8 }) }
        assert(Trick.canBeat(s, 1) and not Trick.pass(s, 1) and Trick.play(s, 1, hand))
    end)

    test("trick: pdk single must be the biggest when next player has one card", function()
        local s = Trick.deal(Rng.new(1), "pdk")
        s.turn, s.first, s.last = 1, nil, nil
        s.hands[1] = cards({ 4, 9, 13 })
        s.hands[2] = cards({ 6 })
        local ok, err = Trick.play(s, 1, { cards({ 4 })[1] })
        assert(not ok and err)
        assert(Trick.play(s, 1, { cards({ 13 })[1] }))
        s.turn, s.last = 1, nil
        s.hands[1] = cards({ 4, 4, 9 })
        assert(Trick.play(s, 1, cards({ 4, 4 })))
        local o = Trick.aiOpts(s, 3)
        s.hands[3] = cards({ 4, 9, 13 })
        s.hands[1] = cards({ 6 })
        s.turn, s.last = 3, nil
        o = Trick.aiOpts(s, 3)
        assert(o.mustMax)
        local pick = R.aiChoose(s.hands[3], o)
        assert(#pick == 1 and R.value(pick[1]) == 13)
    end)

    test("trick: landlord's 20 cards are all all tappable on the table", function()
        H.saved, H.view = {}, nil
        local def = require("kogames.games.doudizhu.main")
        local g = require("kogames.registry").launch(H.host, def, nil)
        local s = g.state()
        s.phase, s.landlord, s.turn, s.last, s.bottom = "play", 1, 1, nil, s.bottom or {}
        local all = {}
        for i = 1, 20 do all[i] = i end
        s.hands[1] = all
        g.render()
        local seen, count = {}, 0
        for x = 1, 99, 0.5 do
            for y = 70, 106, 1 do
                H.view.canvas.on_tap(x, y)
                for _, id in ipairs(g.selected()) do
                    if not seen[id] then seen[id], count = true, count + 1 end
                end
                g.select({})
            end
        end
        assert(count == 20, count)
    end)

    test("trick: grabbing the landlord role and doubling", function()
        local s = Trick.deal(Rng.new(1), "ddz")
        s.turn, s.bidn = 1, 0
        Trick.bid(s, 1, true) -- 叫
        Trick.bid(s, 2, true) -- 抢
        assert(s.mult == 2 and s.cand == 2)
        Trick.bid(s, 3, false)
        assert(s.extra and s.turn == 1, "caller gets a last chance")
        Trick.bid(s, 1, true)
        assert(s.phase == "double" and s.landlord == 1 and s.mult == 4 and s.turn == 2)
        Trick.double(s, 2, true)
        Trick.double(s, 3, false)
        assert(s.phase == "double" and s.turn == 1)
        Trick.double(s, 1, false)
        assert(s.phase == "play" and s.turn == 1 and #s.hands[1] == 20 and s.mult == 8)
        local r = Trick.deal(Rng.new(2), "ddz")
        r.turn, r.bidn = 1, 0
        Trick.bid(r, 1, false) Trick.bid(r, 2, false)
        assert(Trick.bid(r, 3, false) == "redeal")
    end)

    test("trick: sessions render and complete via hint", function()
        for _, id in ipairs({ "doudizhu", "paodekuai" }) do
            H.saved, H.view = {}, nil
            local def = require("kogames.games." .. id .. ".main")
            local g = require("kogames.registry").launch(H.host, def, nil)
            local guard = 0
            while g.state().phase ~= "done" and guard < 300 do
                guard = guard + 1
                local s = g.state()
                local function find(text)
                    for _, row in ipairs(H.view.buttons) do
                        for _, b in ipairs(row) do if (b.text == text or b.key == text) and b.enabled ~= false then return b end end
                    end
                end
                if s.phase == "bid" then
                    (find("叫地主") or find("抢地主") or find("不叫")).callback()
                elseif s.phase == "double" then
                    (find("不加倍")).callback()
                else
                    find("hint").callback()
                    local play, pass = find("play"), find("pass")
                    if play then play.callback() elseif pass then pass.callback() end
                end
            end
            assert(g.state().phase == "done", id .. " did not finish")
            assert(H.saved["stats_" .. id].games == 1)
        end
    end)
end
