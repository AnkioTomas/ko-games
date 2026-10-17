return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view = {}, nil
        return require("kogames.registry").launch(H.host, require("kogames.games.tents"), nil)
    end

    test("tents: rules", function()
        local C = require("kogames.games.tents").core
        -- 3x3: 树在 (1,2)，帐篷在 (1,1) 合法；帐篷在 (2,3) 与树不相邻
        local tree = { false, true, false, false, false, false, false, false, false }
        local s = { n = 3, tree = tree, rows = { 1, 0, 0 }, cols = { 1, 0, 0 } }
        assert(C.valid(s, { true }))
        assert(not C.valid(s, { [6] = true }))
        local s2 = { n = 3, tree = { false, true, false, false, false, true, false, false, false }, rows = { 1, 0, 1 }, cols = { 1, 0, 1 } }
        assert(not C.valid(s2, { true, [9] = true }) == false)
        assert(not C.valid({ n = 3, tree = tree, rows = { 1, 1, 0 }, cols = { 2, 0, 0 } }, { true, [4] = true }))
    end)

    test("tents: generated puzzles are uniquely solvable and fast", function()
        local C = require("kogames.games.tents").core
        for _, n in ipairs({ 6, 8, 10 }) do
            local t0 = os.clock()
            for seed = 1, 5 do
                local s = C.fresh(Rng.new(seed), n)
                assert(C.valid(s, s.sol))
                assert(C.solve(n, s.tree, s.rows, s.cols, 2) == 1, "not unique n=" .. n)
            end
            assert((os.clock() - t0) / 5 < 1, "slow n=" .. n)
        end
    end)

    test("tents: taps, hold and win", function()
        local g = launch()
        local s = g.state()
        local n = s.n
        local function pos(i) return math.floor((i - 1) / n) + 2, (i - 1) % n + 2 end
        local r, c = pos(1)
        H.view.grid.on_tap(1, 1)
        local free
        for i = 1, n * n do if not s.tree[i] then free = i break end end
        r, c = pos(free)
        H.view.grid.on_tap(r, c)
        assert(s.user[free] == 1)
        H.view.grid.on_tap(r, c)
        assert(s.user[free] == 2)
        H.view.grid.on_tap(r, c)
        assert(s.user[free] == 0)
        H.view.grid.on_hold(r, c)
        assert(s.user[free] == 2)
        for i = 1, n * n do if s.tree[i] then H.view.grid.on_tap(pos(i)) assert(s.user[i] == 0) end end
        H.view.grid.on_hold(r, c)
        for i = 1, n * n do if s.sol[i] then H.view.grid.on_tap(pos(i)) end end
        assert(s.done and H.view.status:find("完成"))
        assert(H.saved["stats_tents"].best_6 == 0)
    end)
end
