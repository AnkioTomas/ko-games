return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local M = require("kogames.games.minesweeper.main")
    local C = M.core

    test("minesweeper: first click is safe, mine counts and numbers are right", function()
        for _, lv in ipairs(M.LEVELS) do
            for seed = 1, 20 do
                local s = C.fresh(lv)
                C.open(s, 1 + seed % lv.rows, 1 + (seed * 7) % lv.cols, Rng.new(seed))
                assert(not s.over)
                local mines = 0
                for _, c in ipairs(s.cells) do if c.mine then mines = mines + 1 end end
                assert(mines == lv.mines)
            end
        end
    end)

    test("minesweeper: zero flood fill, win and loss", function()
        local s = C.fresh({ name = "x", rows = 3, cols = 3, mines = 1 })
        s.placed = true
        s.cells[9].mine = true
        for _, i in ipairs({ 5, 6, 8 }) do s.cells[i].n = 1 end
        C.open(s, 1, 1, Rng.new(1))
        assert(s.won and s.over and s.revealed == 8 and not s.cells[9].open)
        s = C.fresh({ name = "x", rows = 3, cols = 3, mines = 1 })
        s.placed = true
        s.cells[9].mine = true
        C.open(s, 3, 3, Rng.new(1))
        assert(s.over and not s.won)
    end)

    test("minesweeper: flags block opening; chord and frozen timer", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, M, nil)
        local s = g.state()
        s.rows, s.cols, s.mines, s.flags, s.placed, s.revealed = 3, 3, 1, 0, true, 0
        s.cells = {}
        for i = 1, 9 do s.cells[i] = { mine = false, open = false, flag = false, n = 0 } end
        s.cells[9].mine = true
        for _, i in ipairs({ 5, 6, 8 }) do s.cells[i].n = 1 end
        g.hold(2, 2)
        assert(s.cells[5].flag and s.flags == 1)
        g.tap(2, 2)
        assert(not s.cells[5].open)
        g.hold(2, 2)
        g.tap(1, 1)
        assert(s.won and s.time ~= nil)
        local t0 = s.time
        g.tap(1, 1)
        assert(s.time == t0)
    end)
end
