return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view = {}, nil
        return require("kogames.registry").launch(H.host, require("kogames.games.filling"), nil)
    end

    test("filling: region status", function()
        local C = require("kogames.games.filling").core
        local val = { 2, 2, 1, 3, 3, 3, 0, 0, 0 }
        assert(C.status(3, val, 1) == "ok" and C.status(3, val, 3) == "ok" and C.status(3, val, 4) == "ok")
        assert(C.status(3, { 1, 1, 0, 0, 0, 0, 0, 0, 0 }, 1) == "bad")
        assert(C.status(3, { 2, 3, 3, 0, 0, 0, 0, 0, 0 }, 1) == nil)
        assert(C.status(3, { 2, 3, 2, 3, 2, 3, 2, 3, 2 }, 1) == "bad")
        assert(C.solved(3, { 2, 2, 1, 3, 3, 3, 1, 4, 4 }) == false)
        assert(C.solved(3, { 9, 9, 9, 9, 9, 9, 9, 9, 9 }))
    end)

    test("filling: generated puzzles are uniquely solvable and fast", function()
        local C = require("kogames.games.filling").core
        for _, n in ipairs({ 6, 8 }) do
            local t0 = os.clock()
            for seed = 1, 5 do
                local s = C.fresh(Rng.new(seed), n)
                assert(C.solved(n, s.sol))
                local count, sol = C.solve(n, s.given, 2)
                assert(count == 1, "not unique n=" .. n)
                for i = 1, n * n do assert(sol[i] == s.sol[i]) end
            end
            assert((os.clock() - t0) / 5 < 1, "slow n=" .. n)
        end
    end)

    test("filling: select, enter numbers and win", function()
        local g = launch()
        local s = g.state()
        local n = s.n
        local gi
        for i = 1, n * n do if s.given[i] ~= 0 then gi = i break end end
        H.view.grid.on_tap(math.floor((gi - 1) / n) + 1, (gi - 1) % n + 1)
        H.view.buttons[1][1].callback()
        assert(s.val[gi] == s.given[gi])
        for i = 1, n * n do
            if s.given[i] == 0 then
                H.view.grid.on_tap(math.floor((i - 1) / n) + 1, (i - 1) % n + 1)
                local v = s.sol[i]
                H.view.buttons[v <= 5 and 1 or 2][v <= 5 and v or v - 5].callback()
            end
        end
        assert(s.done and H.view.status:find("完成"))
        assert(H.saved["stats_filling"].best_6 == 0)
    end)

    test("filling: clear", function()
        local g = launch()
        local s = g.state()
        local n = s.n
        local e
        for i = 1, n * n do if s.given[i] == 0 then e = i break end end
        H.view.grid.on_tap(math.floor((e - 1) / n) + 1, (e - 1) % n + 1)
        H.view.buttons[1][1].callback()
        assert(s.val[e] == 1)
        H.view.buttons[2][5].callback()
        assert(s.val[e] == 0)
    end)
end
