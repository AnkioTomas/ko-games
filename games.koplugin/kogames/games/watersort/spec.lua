return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.watersort.main").core

    test("watersort: fresh has 4 of each colour and two empty tubes", function()
        for _, k in ipairs({ 4, 6, 8 }) do
            local s = C.fresh(Rng.new(k), k)
            assert(#s.tubes == k + 2 and #s.tubes[k + 1] == 0 and #s.tubes[k + 2] == 0)
            local cnt = {}
            for _, tube in ipairs(s.tubes) do for _, v in ipairs(tube) do cnt[v] = (cnt[v] or 0) + 1 end end
            for c = 1, k do assert(cnt[c] == 4) end
            assert(not C.solved(s))
        end
    end)

    test("watersort: pour rules, undo and solve", function()
        local s = { colors = 2, moves = 0, hist = {}, tubes = { { 1, 2, 2 }, { 2, 1, 1, 1 }, {} } }
        assert(not C.canPour(s, 1, 2)) -- 目标管满了
        assert(C.pour(s, 1, 3) and #s.tubes[3] == 2 and #s.tubes[1] == 1)
        assert(C.undo(s) and #s.tubes[1] == 3 and s.moves == 0)
        s = { colors = 2, moves = 0, hist = {}, tubes = { { 1, 1, 1 }, { 1 }, {}, } }
        assert(not C.canPour(s, 1, 3)) -- 纯色倒空管没有意义
        assert(C.pour(s, 2, 1) and C.solved(s))
    end)

    test("watersort: session select and pour", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.watersort.main"), nil)
        local s = g.state()
        s.tubes = { { 1, 2 }, { 2, 1 }, {}, {} }
        s.colors, s.moves, s.hist = 2, 0, {}
        g.render()
        H.view.grid.on_tap(1, 1)
        H.view.grid.on_tap(3, 1)
        assert(#s.tubes[3] == 1 and s.moves == 1)
    end)
end
