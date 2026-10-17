return function(t)
    local test, H = t.test, t.H
    local function launch()
        H.saved, H.view = {}, nil
        return require("kogames.registry").launch(H.host, require("kogames.games.hanoi"), nil)
    end

    test("hanoi: move rules", function()
        local C = require("kogames.games.hanoi").core
        local s = C.fresh(3)
        assert(not C.move(s, 2, 3) and not C.move(s, 1, 1))
        assert(C.move(s, 1, 2) and C.move(s, 1, 3))
        assert(not C.canMove(s, 1, 3))
        assert(s.moves == 2)
    end)

    test("hanoi: hint solves optimally from the start", function()
        local C = require("kogames.games.hanoi").core
        for n = 1, 7 do
            local s = C.fresh(n)
            local count = 0
            while not C.solved(s) do
                local f, to = C.hint(s, 3)
                assert(f and C.move(s, f, to))
                count = count + 1
            end
            assert(count == 2 ^ n - 1, "n=" .. n)
        end
    end)

    test("hanoi: session tap flow, win and record", function()
        local g = launch()
        local C = require("kogames.games.hanoi").core
        local s = g.state()
        s.n, s.pegs, s.moves, s.done = 1, { { 1 }, {}, {} }, 0, nil
        g.render()
        H.view.grid.on_tap(1, 1)
        H.view.grid.on_tap(1, 3)
        assert(s.done and C.solved(s) and s.moves == 1)
        assert(H.saved["stats_hanoi"].best1 == 1)
    end)
end
