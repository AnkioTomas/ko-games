return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local Game = require("kogames.games.klondike.main")
    local C = Game.core

    local function blank()
        local s = C.fresh(Rng.new(1), 1)
        s.tab = { {}, {}, {}, {}, {}, {}, {} }
        s.stock, s.waste, s.found, s.undo, s.moves = {}, {}, { 0, 0, 0, 0 }, {}, 0
        return s
    end
    local function id(suit, rank) return (suit - 1) * 13 + rank end

    test("klondike deal", function()
        local s = C.fresh(Rng.new(5), 1)
        local n, seen = 0, {}
        for c = 1, 7 do
            assert(#s.tab[c] == c and s.tab[c][c] > 0)
            for i = 1, c - 1 do assert(s.tab[c][i] < 0) end
            for _, v in ipairs(s.tab[c]) do n = n + 1 seen[math.abs(v)] = true end
        end
        for _, v in ipairs(s.stock) do seen[v] = true end
        assert(n == 28 and #s.stock == 24 and #s.waste == 0)
        for i = 1, 52 do assert(seen[i]) end
    end)

    test("klondike move rules and undo", function()
        local s = blank()
        s.tab[1] = { id(1, 7) }          -- 7♠
        s.tab[2] = { -id(2, 3), id(2, 6) } -- 6♥ on top
        s.tab[3] = { id(2, 8) }          -- 8♥
        s.tab[4] = { id(4, 13) }         -- K♣
        assert(not C.moveTab(s, 2, 2, 3), "6♥ onto 8♥ is illegal")
        assert(not C.moveTab(s, 3, 1, 1), "8♥ onto 7♠ is illegal")
        assert(C.moveTab(s, 2, 2, 1))
        assert(#s.tab[1] == 2 and s.tab[2][1] > 0, "new top flips")
        assert(not C.moveTab(s, 1, 1, 2), "7♠ pile onto 3♥ illegal")
        assert(not C.moveTab(s, 3, 1, 5), "non-king on empty column")
        assert(C.moveTab(s, 4, 1, 5), "king on empty column")
        assert(C.moveTab(s, 1, 1, 3), "7♠+6♥ onto 8♥")
        assert(#s.tab[3] == 3)
        while #s.undo > 0 do assert(C.undo(s)) end
        assert(#s.tab[1] == 1 and s.tab[2][1] < 0 and #s.tab[2] == 2 and #s.tab[5] == 0 and s.moves == 0)
        s.found = { 0, 1, 0, 0 }
        s.tab[1] = { id(2, 2) }
        s.tab[2] = { id(1, 1) }
        assert(C.toFound(s, "tab", 1) and s.found[2] == 2)
        assert(C.toFound(s, "tab", 2) and s.found[1] == 1)
        s.tab[3] = { id(3, 5) }
        assert(not C.toFound(s, "tab", 3))
    end)

    test("klondike stock cycle, auto collect and win", function()
        local s = C.fresh(Rng.new(3), 1)
        for _ = 1, 24 do assert(C.draw(s)) end
        assert(#s.stock == 0 and #s.waste == 24)
        assert(C.draw(s) and #s.stock == 24 and #s.waste == 0)
        local s2 = blank()
        for su = 1, 4 do
            for r = 1, 5 do s2.tab[su][#s2.tab[su] + 1] = id(su, 6 - r) end
        end
        s2.found = { 0, 0, 0, 0 }
        s2.tab[5] = { id(1, 6), id(2, 6), id(3, 6), id(4, 6) }
        s2.tab[5] = { id(1, 13) }
        assert(C.autoCollect(s2) == 20 and #s2.undo == 1 and s2.found[1] == 5)
        assert(C.undo(s2) and s2.found[1] == 0)
        local w = blank()
        w.found = { 13, 13, 13, 12 }
        w.tab[1] = { id(4, 13) }
        assert(not C.won(w))
        assert(C.autoCollect(w) == 1 and C.won(w))
    end)

    test("klondike session tap flow saves state", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, Game, nil)
        assert(H.view.grid.ratio and H.view.grid.cols == 7 and H.view.grid.rows >= 8)
        local s = g.state()
        assert(H.view.grid.cell(2, 1).rank and H.view.grid.cell(2, 1).icon)
        H.view.grid.on_tap(1, 1) -- draw
        assert(#s.waste == 1 and H.saved.klondike.state.moves == 1)
        H.view.grid.on_tap(1, 2) -- select waste
        assert(H.view.grid.cell(1, 2).fill == "black")
        H.view.grid.on_tap(1, 2)
        assert(H.view.grid.cell(1, 2).fill ~= "black")
        -- put a legal tableau move in place and play it with taps
        s.tab[1] = { id(1, 7) }
        s.tab[2] = { id(2, 6) }
        H.view.grid.on_tap(2, 2)
        assert(H.view.grid.cell(2, 2).fill == "black")
        H.view.grid.on_tap(2, 1)
        assert(#s.tab[1] == 2 and #s.tab[2] == 0)
        H.view.settings.actions[1].callback() -- 撤销
        assert(#s.tab[1] == 1 and #s.tab[2] == 1)
        H.view.settings.actions[2].callback() -- 新游戏
        assert(#g.state().stock == 24)
    end)
end
