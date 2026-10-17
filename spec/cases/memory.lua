return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view = {}, nil
        return require("kogames.registry").launch(H.host, require("kogames.games.memory"), nil)
    end

    test("memory: fresh deals pairs", function()
        local C = require("kogames.games.memory").core
        for _, sz in ipairs({ { 4, 4 }, { 5, 4 }, { 6, 6 } }) do
            local s = C.fresh(Rng.new(3), sz[1], sz[2])
            local cnt = {}
            for _, v in ipairs(s.cards) do cnt[v] = (cnt[v] or 0) + 1 end
            assert(#s.cards == sz[1] * sz[2])
            for _, n in pairs(cnt) do assert(n == 2) end
        end
    end)

    test("memory: match stays, mismatch hides on next tap", function()
        local C = require("kogames.games.memory").core
        local s = { rows = 2, cols = 2, cards = { 1, 2, 1, 2 }, matched = {}, up = {}, moves = 0, pairs = 0 }
        assert(C.flip(s, 1) and not C.flip(s, 1))
        assert(C.flip(s, 2) and #s.up == 2 and s.moves == 1)
        assert(C.flip(s, 3) and #s.up == 1 and s.up[1] == 3)
        s = { rows = 2, cols = 2, cards = { 1, 2, 1, 2 }, matched = {}, up = {}, moves = 0, pairs = 0 }
        C.flip(s, 1); C.flip(s, 3)
        assert(s.matched[1] and s.matched[3] and #s.up == 0 and not C.flip(s, 1))
        C.flip(s, 2); C.flip(s, 4)
        assert(C.solved(s) and s.moves == 2)
    end)

    test("memory: session win records best", function()
        local g = launch()
        local s = g.state()
        s.rows, s.cols, s.cards, s.matched, s.up, s.moves, s.pairs, s.done = 2, 2, { 1, 2, 1, 2 }, {}, {}, 0, 0, nil
        g.render()
        H.view.grid.on_tap(1, 1); H.view.grid.on_tap(2, 1)
        H.view.grid.on_tap(1, 2); H.view.grid.on_tap(2, 2)
        assert(s.done and s.moves == 2)
        assert(H.saved["stats_memory"].best2x2 == 2)
    end)
end
