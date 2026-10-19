return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.goldminer.main").core

    local function empty()
        local b = {}
        for i = 1, 99 do b[i] = 0 end
        return b
    end

    test("goldminer: ray hits first object, blocked by earlier ones", function()
        local s = { board = empty(), aim = 6, money = 0, dyn = 0, time = 60, level = 1, shots = 0 }
        s.board[(8 - 1) * 9 + 5] = "gold_s"
        s.board[(5 - 1) * 9 + 5] = "stone"
        local i = C.ray(s, 6)
        assert(i == (5 - 1) * 9 + 5)
        assert(C.aimAt(8, 5) == 6 and C.aimAt(8, 9) > 6 and C.aimAt(8, 1) < 6)
    end)

    test("goldminer: costs by weight, miss costs, dynamite", function()
        local rng = Rng.new(2)
        local s = { board = empty(), aim = 6, money = 0, dyn = 1, time = 60, level = 1, shots = 0 }
        s.board[(6 - 1) * 9 + 5] = "stone"
        s.board[(10 - 1) * 9 + 5] = "diamond"
        s.board[(11 - 1) * 9 + 9] = "gold_s"
        s.armed = true
        local r = C.fire(s, rng)
        assert(r.blown and r.gain == 0 and s.money == 0 and s.dyn == 0 and not s.armed)
        local after_blow = s.time
        assert(after_blow == 60 - r.cost and r.cost < 6)
        r = C.fire(s, rng)
        assert(r.hit == "diamond" and s.money == 600)
        C.setAim(s, 1)
        r = C.fire(s, rng)
        assert(not r.hit and r.cost == 3)
    end)

    test("goldminer: levels are generated with enough value and clear", function()
        for seed = 1, 10 do
            local rng = Rng.new(seed)
            local s = C.fresh(rng, "normal")
            assert(C.remaining(s) > 0 and not C.levelOver(s))
            s.money = C.target(1)
            s.time = 0
            assert(C.levelOver(s) and C.won(s))
            C.nextLevel(s, rng)
            assert(s.level == 2 and s.dyn == 2 and s.time == 60 and not C.levelOver(s))
        end
    end)

    test("goldminer: session fires, loses and records level", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.goldminer.main"), nil)
        local s = g.state()
        s.time = 1
        s.aim = 1
        g.fire()
        assert(s.time <= 0 and s.over and H.saved["stats_goldminer"].level == 1)
        local found
        for _, row in ipairs(H.view.buttons) do
            if row[1] and row[1].text == "重新开始" then found = true end
        end
        assert(found)
    end)

    test("goldminer: armed dynamite survives a miss", function()
        local s = { board = empty(), aim = 6, money = 0, dyn = 1, armed = true, time = 60, level = 1, shots = 0, mode = "normal" }
        s.board[1] = "gold_s"
        local res = C.fire(s, Rng.new(1))
        assert(not res.hit and s.armed and s.dyn == 1)
    end)
end
