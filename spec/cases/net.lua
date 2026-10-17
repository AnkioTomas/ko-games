return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view = {}, nil
        return require("kogames.registry").launch(H.host, require("kogames.games.net"), nil)
    end

    test("net: rotation", function()
        local C = require("kogames.games.net").core
        assert(C.rotCW(1) == 2 and C.rotCW(8) == 1 and C.rotCW(3) == 6 and C.rotCW(9) == 3)
        for m = 1, 15 do assert(C.rotCCW(C.rotCW(m)) == m) end
    end)

    test("net: generated trees are connected without loops and scrambled", function()
        local C = require("kogames.games.net").core
        for _, n in ipairs({ 5, 7 }) do
            for seed = 1, 10 do
                local s = C.fresh(Rng.new(seed), n)
                local edges = 0
                for i = 1, n * n do
                    assert(s.sol[i] > 0)
                    for b = 1, 8, 1 do if b == 1 or b == 2 or b == 4 or b == 8 then if s.sol[i] % (b * 2) >= b then edges = edges + 1 end end end
                end
                assert(edges == 2 * (n * n - 1), "not a tree")
                assert(C.solved({ cur = s.sol, n = n, server = s.server }))
                assert(not C.solved(s))
            end
        end
    end)

    test("net: tap rotates, hold reverses, solving wins", function()
        local g = launch()
        local C = require("kogames.games.net").core
        local s = g.state()
        local n = s.n
        local before = s.cur[1]
        H.view.grid.on_tap(1, 1)
        assert(s.cur[1] == C.rotCW(before))
        H.view.grid.on_hold(1, 1)
        assert(s.cur[1] == before)
        for i = 1, n * n do
            local guard = 0
            while s.cur[i] ~= s.sol[i] and guard < 4 do
                H.view.grid.on_tap(math.floor((i - 1) / n) + 1, (i - 1) % n + 1)
                guard = guard + 1
            end
        end
        assert(s.done and H.view.status:find("完成"))
        assert(H.saved["stats_net"].best_5 == 0)
    end)
end
