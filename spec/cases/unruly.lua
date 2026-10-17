return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view, H.settings = {}, nil, {}
        return require("kogames.registry").launch(H.host, require("kogames.games.unruly"), nil)
    end

    test("unruly: rules", function()
        local C = require("kogames.games.unruly").core
        local bad = C.conflicts({ 1, 1, 1, 2, 2, 0, 0, 0, 0 }, 3)
        assert(bad[1] and bad[2] and bad[3] and not bad[4])
        assert(C.solved({ 1, 1, 2, 2, 2, 2, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1 }, 4))
        assert(not C.solved({ 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1 }, 4))
    end)

    test("unruly: generated puzzles are unique, valid and fast", function()
        local C = require("kogames.games.unruly").core
        for _, n in ipairs({ 6, 8, 10 }) do
            local t0 = os.clock()
            for seed = 1, 4 do
                local s = C.fresh(Rng.new(seed), n)
                assert(C.solved(s.sol, n))
                assert(C.solve(s.user, n, 2) == 1)
            end
            assert((os.clock() - t0) / 4 < 1)
        end
    end)

    test("unruly: tap flow and win", function()
        local g = launch()
        local s = g.state()
        local n = s.n
        for i = 1, n * n do
            if s.given[i] then
                H.view.grid.on_tap(math.floor((i - 1) / n) + 1, (i - 1) % n + 1)
                assert(s.user[i] == s.sol[i])
            end
        end
        for i = 1, n * n do
            if not s.given[i] then
                local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
                for _ = 1, s.sol[i] do H.view.grid.on_tap(r, c) end
            end
        end
        assert(s.done and H.view.status:find("完成"))
        assert(H.saved["stats_unruly"]["best_6"] ~= nil)
    end)
end
