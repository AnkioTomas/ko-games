return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.lightsout.main").core

    test("lightsout: press is an involution, fresh is unsolved", function()
        for _, n in ipairs({ 4, 5, 6 }) do
            local s = C.fresh(Rng.new(n), n)
            assert(not C.solved(s))
            local before = {}
            for i, v in ipairs(s.cells) do before[i] = v end
            C.press(s, 2, 3) C.press(s, 2, 3)
            for i, v in ipairs(before) do assert(s.cells[i] == v) end
        end
    end)

    test("lightsout: replaying the generating presses wins and records", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.lightsout.main"), nil)
        local s = g.state()
        s.n, s.cells, s.moves, s.done = 3, { false, false, false, false, false, false, false, false, false }, 0, nil
        C.press(s, 2, 2)
        g.tap(2, 2)
        assert(s.done and s.moves == 1 and H.saved["stats_lightsout"].best3 == 1)
    end)
end
