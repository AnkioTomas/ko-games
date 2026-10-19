return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.goldminer.main").core

    local function blank(extra)
        local s = { mode = "normal", level = 1, money = 0, time = 60, dyn = 2, phase = "swing", k = 0, dir = 1,
            len = 7, ang = 0, objs = {} }
        for k, v in pairs(extra or {}) do s[k] = v end
        return s
    end

    test("goldminer: hook swings back and forth", function()
        local s, rng = blank(), Rng.new(1)
        local seen = {}
        for _ = 1, 30 do
            C.tick(s, rng)
            seen[s.k] = true
            assert(math.abs(s.k) <= C.STEPS)
        end
        assert(seen[C.STEPS] and seen[-C.STEPS])
        assert(math.abs(s.time - (60 - 30 * C.TICK)) < 1e-6)
    end)

    test("goldminer: hook hits object and retrieves by weight", function()
        local rng = Rng.new(1)
        local function run(kind)
            local K = C.KINDS[kind]
            local s = blank({ objs = { { kind = kind, x = C.AX, y = 70, r = K.r } } })
            assert(C.fire(s) and s.phase == "out")
            local ticks = 0
            while s.phase ~= "swing" and ticks < 200 do C.tick(s, rng) ticks = ticks + 1 end
            return s, ticks
        end
        local sl, tl = run("gold_l")
        local ss, ts = run("gold_s")
        local st = run("stone")
        assert(sl.money == 500 and ss.money == 100 and st.money == 20 and #sl.objs == 0)
        assert(tl > ts, "heavy gold is slower")
        local d, td = run("diamond")
        assert(d.money == 600 and td <= ts)
    end)

    test("goldminer: miss at boundary returns empty", function()
        local s, rng = blank({ k = C.STEPS }), Rng.new(1)
        C.fire(s)
        local n = 0
        while s.phase ~= "swing" and n < 100 do C.tick(s, rng) n = n + 1 end
        assert(s.phase == "swing" and s.money == 0 and n < 40)
    end)

    test("goldminer: dynamite destroys held object", function()
        local rng = Rng.new(1)
        local s = blank({ objs = { { kind = "stone", x = C.AX, y = 70, r = 6 } } })
        assert(not C.blast(s))
        C.fire(s)
        while s.phase == "out" do C.tick(s, rng) end
        assert(s.phase == "back" and s.held)
        assert(C.blast(s) and s.dyn == 1 and not s.held and #s.objs == 0)
        local n = 0
        while s.phase ~= "swing" and n < 50 do C.tick(s, rng) n = n + 1 end
        assert(s.money == 0 and s.phase == "swing")
    end)

    test("goldminer: levels have enough value and win/lose at time up", function()
        for seed = 1, 10 do
            local rng = Rng.new(seed)
            local s = C.fresh(rng, "normal")
            local v = 0
            for _, o in ipairs(s.objs) do
                if o.kind ~= "stone" and o.kind ~= "stone_s" then v = v + C.KINDS[o.kind].value end
            end
            assert(v >= C.target(1, "normal"), "level reachable")
            s.money, s.time = C.target(1, "normal"), 0.1
            assert(C.tick(s, rng) == "cleared" and s.cleared)
            assert(C.nextLevel(s, rng) and s.level == 2 and s.time == 60 and s.dyn == 2 and not s.cleared)
            assert(C.target(2, "normal") > C.target(1, "normal"))
            s.money, s.time = 0, 0.1
            assert(C.tick(s, rng) == "over" and s.over)
        end
    end)

    test("goldminer: session ticks, pauses, saves, fails and records", function()
        H.saved, H.view = {}, nil
        local def = require("kogames.games.goldminer.main")
        local g = require("kogames.registry").launch(H.host, def, nil)
        local s = g.state()
        assert(g.paused() and H.view.canvas)
        g.fire()
        assert(s.phase == "swing")
        g.toggle()
        assert(not g.paused())
        H.view.canvas.on_tap(50, 50)
        assert(s.phase == "out")
        g.toggle()
        local k = s.len
        g.tick()
        assert(s.len > k)
        g.toggle()
        s.objs, s.time, s.phase, s.len = {}, 0.2, "swing", 7
        g.tick()
        assert(s.over and H.saved["stats_goldminer"].level == 1)
        local found
        for _, row in ipairs(H.view.buttons) do
            if row[1] and row[1].text == "重新开始" then found = true end
        end
        assert(found)
        g.newGame()
        s = g.state()
        s.money = 77
        g.toggle()
        g.stop()
        assert(g.paused())
        local g2 = require("kogames.registry").launch(H.host, def, nil)
        assert(g2.state().money == 77)
    end)
end
