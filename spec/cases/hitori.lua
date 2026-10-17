return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view, H.settings = {}, nil, {}
        return require("kogames.registry").launch(H.host, require("kogames.games.hitori"), nil)
    end

    test("hitori: rules", function()
        local C = require("kogames.games.hitori").core
        local num = { 1, 2, 1, 2, 1, 2, 3, 3, 3 }
        local a = C.analyze(num, 3, { 0, 0, 0, 0, 0, 0, 0, 0, 0 })
        assert(a.dup[1] and not a.solved)
        -- shading two adjacent cells is illegal
        a = C.analyze(num, 3, { 1, 1, 0, 0, 0, 0, 0, 0, 0 })
        assert(a.adj[1] and a.adj[2] and not a.solved)
        -- disconnected unshaded cells: shade a cut ring
        local g = { 1, 2, 3, 2, 3, 1, 3, 1, 2 }
        assert(C.solved(g, 3, { 0, 0, 0, 0, 0, 0, 0, 0, 0 }))
        assert(not C.solved(g, 3, { 0, 1, 0, 1, 0, 0, 0, 0, 0 }))
    end)

    test("hitori: generated puzzles solvable, unique, fast", function()
        local C = require("kogames.games.hitori").core
        for _, n in ipairs({ 5, 6, 8 }) do
            local t0 = os.clock()
            for seed = 1, 5 do
                local s = C.fresh(Rng.new(seed), n)
                assert(C.solved(s.num, n, (function()
                    local u = {}
                    for i = 1, n * n do u[i] = s.sol[i] == 1 and 1 or 0 end
                    return u
                end)()))
                assert(C.solve(s.num, n, 2) == 1)
            end
            assert((os.clock() - t0) / 5 < 1)
        end
    end)

    test("hitori: taps, hold and win", function()
        local g = launch()
        local s = g.state()
        local n = s.n
        local function pos(i) return math.floor((i - 1) / n) + 1, (i - 1) % n + 1 end
        H.view.grid.on_hold(1, 1)
        assert(s.user[1] == 2)
        H.view.grid.on_hold(1, 1)
        assert(s.user[1] == 0)
        for i = 1, n * n do if s.sol[i] == 1 then H.view.grid.on_tap(pos(i)) end end
        assert(s.done and H.view.status:find("完成"))
        assert(H.saved["stats_hitori"]["best_5"] ~= nil)
    end)
end
