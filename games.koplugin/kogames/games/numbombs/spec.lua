return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.numbombs.main").core

    test("numbombs: range narrows, bomb ends game, ai stays in range", function()
        local s = { bomb = 50, lo = 0, hi = 100, turn = 1, rounds = 0 }
        assert(C.guess(s, 30) == "ok" and s.lo == 30 and s.turn == 2)
        assert(C.guess(s, 20) == nil)
        assert(C.guess(s, 70) == "ok" and s.hi == 70)
        for seed = 1, 30 do
            local n = C.aiPick(s, Rng.new(seed))
            assert(n > 30 and n < 70)
        end
        assert(C.guess(s, 50) == "boom" and s.over and s.loser == 1)
    end)

    test("numbombs: session plays to the end", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.numbombs.main"), nil)
        local s = g.state()
        local guard = 0
        while not s.over and guard < 200 do
            guard = guard + 1
            for n = s.lo + 1, s.hi - 1 do
                if n ~= s.bomb then g.tap(math.floor((n - 1) / 10) + 1, (n - 1) % 10 + 1) break end
            end
            if s.hi - s.lo == 2 then g.tap(math.floor((s.bomb - 1) / 10) + 1, (s.bomb - 1) % 10 + 1) end
        end
        assert(s.over)
    end)
end
