return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view = {}, nil
        return require("kogames.registry").launch(H.host, require("kogames.games.nonogram.main"), nil)
    end

    test("nonogram: clues", function()
        local C = require("kogames.games.nonogram.main").core
        local c = C.lineClue({ 1, 1, 0, 1, 0 }, 5)
        assert(#c == 2 and c[1] == 2 and c[2] == 1)
        assert(#C.lineClue({ 0, 0, 0 }, 3) == 0)
        local rows, cols = C.clues({ 1, 0, 1, 1, 1, 0, 0, 1, 1 }, 3)
        assert(rows[1][1] == 1 and rows[1][2] == 1 and rows[2][1] == 2 and cols[1][1] == 2 and #cols[1] == 1)
    end)

    test("nonogram: line solver", function()
        local C = require("kogames.games.nonogram.main").core
        local out = C.solveLine({ 3 }, { -1, -1, -1, -1, -1 }, 5)
        assert(out[3] == 1 and out[1] == -1)
        out = C.solveLine({ 1, 1 }, { 1, -1, -1 }, 3)
        assert(out[1] == 1 and out[2] == 0 and out[3] == 1)
        assert(C.solveLine({ 4 }, { -1, 0, -1 }, 3) == nil)
    end)

    test("nonogram: generated puzzles are uniquely line-solvable and fast", function()
        local C = require("kogames.games.nonogram.main").core
        for _, n in ipairs({ 5, 10 }) do
            local t0 = os.clock()
            for seed = 1, 5 do
                local s = C.fresh(Rng.new(seed), n)
                local g = C.lineSolve(s.rows, s.cols, n)
                assert(g, "not solvable n=" .. n)
                for i = 1, n * n do assert(g[i] == s.sol[i]) end
            end
            assert((os.clock() - t0) / 5 < 1, "slow n=" .. n)
        end
        assert(C.fresh(Rng.new(3), 15).n == 15)
    end)

    test("nonogram: win detection and taps", function()
        local g = launch()
        local C = require("kogames.games.nonogram.main").core
        local s = g.state()
        local n = s.n
        local mr, mc = 0, 0
        for k = 1, n do mr = math.max(mr, #s.rows[k]) mc = math.max(mc, #s.cols[k]) end
        local function tap(i) H.view.grid.on_tap(math.floor((i - 1) / n) + 1 + mc, (i - 1) % n + 1 + mr) end
        H.view.grid.on_tap(1, 1)
        assert(not s.done)
        local first
        for i = 1, n * n do if s.sol[i] == 1 then first = first or i tap(i) end end
        assert(s.user[first] == 1 and s.done and C.solved(s))
        assert(H.view.status:find("完成"))
        assert(H.saved["stats_nonogram"].best_5 == 0)
    end)

    test("nonogram: x mode, hold and undo", function()
        local g = launch()
        local s = g.state()
        local n = s.n
        local mr, mc = 0, 0
        for k = 1, n do mr = math.max(mr, #s.rows[k]) mc = math.max(mc, #s.cols[k]) end
        H.view.grid.on_hold(mc + 1, mr + 1)
        assert(s.user[1] == 2)
        H.view.buttons[1][2].callback()
        H.view.grid.on_tap(mc + 1, mr + 2)
        assert(s.user[2] == 2)
        H.view.grid.on_tap(mc + 1, mr + 2)
        assert(s.user[2] == 0)
        H.view.settings.actions[1].callback()
        assert(s.user[2] == 2)
    end)
end
