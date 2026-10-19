return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local launch, gridText = dofile("spec/clock.lua")(t)

    -- tetris -----------------------------------------------------------
    local TT = require("kogames.games.tetris.main")
    local TC = TT.core

    test("tetris shapes have 4 cells and rotate back after 4 turns", function()
        for _, k in ipairs({ "I", "O", "T", "S", "Z", "J", "L" }) do
            local a, b = TC.cells(k, 0), TC.cells(k, 4)
            assert(#a == 4)
            for i = 1, 4 do assert(a[i][1] == b[i][1] and a[i][2] == b[i][2]) end
        end
        local v = TC.cells("I", 1)
        assert(v[1][2] == v[4][2], "vertical I")
    end)

    test("tetris clears lines, scores and shifts rows down", function()
        local rng = Rng.new(3)
        local s = TC.fresh(rng, 2)
        for r = 17, 18 do for c = 3, 10 do s.board[(r - 1) * 10 + c] = 1 end end
        s.cur = { kind = "O", rot = 0, r = 1, c = 1 }
        TC.hardDrop(s, rng)
        assert(s.lines == 2 and s.score == 300 * 2 + 16)
        for i = 1, 180 do assert(s.board[i] == 0) end
    end)

    test("tetris move/rotate respect walls, game over when blocked", function()
        local rng = Rng.new(9)
        local s = TC.fresh(rng, 1)
        s.cur = { kind = "I", rot = 1, r = 1, c = 1 }
        assert(TC.rotate(s)) -- wall kick keeps it inside
        for _ = 1, 20 do TC.move(s, -1) end
        assert(TC.fits(s, s.cur.kind, s.cur.rot, s.cur.r, s.cur.c) and not TC.move(s, -1))
        for i = 1, 9 do s.board[i] = 1 end
        TC.hardDrop(s, rng)
        assert(s.over)
        assert(TC.interval(TC.fresh(rng, 5)) == 0.6 and TC.interval(TC.fresh(rng, 1)) == 1.0)
    end)

    test("tetris session gravity tick, controls and pause", function()
        local g, host, ctx = launch(TT)
        assert(H.view.grid.rows == 18 and host.pending() == 0)
        local before = gridText(H.view)
        assert(before == 8, "piece + ghost")
        g.left()
        g.toggle() -- start
        assert(host.pending() == 1)
        local r0 = g.state().cur.r
        local shows = H.shows
        host.advance(1.01)
        assert(g.state().cur.r == r0 + 1 and H.shows == shows + 1)
        local c0 = g.state().cur.c
        g.left()
        assert(g.state().cur.c == c0 - 1)
        g.toggle()
        assert(host.pending() == 0)
        local r1 = g.state().cur.r
        host.advance(10)
        assert(g.state().cur.r == r1)
        g.left()
        assert(g.state().cur.c == c0 - 1, "ignored while paused")
        g.toggle()
        g.hard()
        assert(g.state().score > 0)
        ctx:exit()
        assert(host.pending() == 0)
        assert(H.saved["tetris"] and H.saved["tetris"].state)
    end)

    test("tetris topping out records best score", function()
        local g, host = launch(TT)
        g.toggle()
        for _ = 1, 40 do if not g.state().over then g.hard() end end
        assert(g.state().over and host.pending() == 0)
        assert(H.saved["stats_tetris"].best == g.state().score)
    end)

    test("tetris shows the next piece", function()
        local g = launch(TT)
        local label = H.view.buttons[1].label
        assert(label and label:find(g.state().next, 1, true))
    end)
end
