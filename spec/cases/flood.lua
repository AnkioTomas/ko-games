return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view, H.settings = {}, nil, {}
        return require("kogames.registry").launch(H.host, require("kogames.games.flood"), nil)
    end

    test("flood: fill absorbs neighbours", function()
        local C = require("kogames.games.flood").core
        local b = { 1, 1, 2, 3, 2, 2, 3, 3, 1 }
        assert(C.fill(b, 3, 2))
        assert(b[1] == 2 and b[2] == 2 and b[3] == 2 and b[5] == 2 and b[6] == 2 and b[4] == 3)
        assert(not C.fill(b, 3, 2))
        assert(not C.solved(b))
        assert(C.solved({ 4, 4, 4, 4 }))
    end)

    test("flood: limit is reachable by greedy", function()
        local C = require("kogames.games.flood").core
        for _, n in ipairs({ 8, 12, 16 }) do
            local s = C.fresh(Rng.new(n), n)
            assert(#s.board == n * n and C.greedy(s.board, n) < s.limit)
        end
    end)

    test("flood: session play, win, lose and undo", function()
        local g = launch()
        local s = g.state()
        H.view.grid.on_tap(s.n, s.n)
        local before = s.moves
        H.view.buttons[3][1].callback() -- 撤销
        assert(s.moves <= before)
        local guard = 0
        while not s.done and not s.lost and guard < 500 do
            guard = guard + 1
            g.pick(s.board[1] % 5 + 1)
        end
        assert(s.done or s.lost)
        assert(H.saved.flood.state)
    end)
end
