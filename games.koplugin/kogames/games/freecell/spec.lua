return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local Game = require("kogames.games.freecell.main")
    local C = Game.core
    local function id(suit, rank) return (suit - 1) * 13 + rank end
    local function blank()
        local s = C.fresh(Rng.new(1), true)
        s.tab = { {}, {}, {}, {}, {}, {}, {}, {} }
        s.cells, s.found, s.undo, s.moves = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, {}, 0
        return s
    end

    test("freecell deal", function()
        local s = C.fresh(Rng.new(5), true)
        local seen, n = {}, 0
        for c = 1, 8 do
            assert(#s.tab[c] == (c <= 4 and 7 or 6))
            for _, v in ipairs(s.tab[c]) do assert(v > 0) seen[v] = true n = n + 1 end
        end
        assert(n == 52)
        for i = 1, 52 do assert(seen[i]) end
    end)

    test("freecell moves, supermove limit, found, undo", function()
        local s = blank()
        s.tab[1] = { id(1, 9), id(2, 8), id(1, 7), id(2, 6) } -- 9♠ 8♥ 7♠ 6♥
        s.tab[2] = { id(2, 10) }
        for c = 3, 8 do s.tab[c] = { id(3, 13) } end -- no empty columns
        s.cells = { 1, 2, 3, 0 } -- one free cell: max 2 cards
        assert(C.maxMove(s, 2) == 2)
        assert(not C.moveTab(s, 1, 1, 2), "4 cards exceed the limit")
        assert(not C.moveTab(s, 1, 2, 2), "8♥ onto 10♥ illegal")
        assert(C.moveTab(s, 1, 3, 2) == false, "7♠ onto 10♥ illegal")
        s.limit = false
        assert(C.moveTab(s, 1, 1, 2) and #s.tab[2] == 5 and #s.tab[1] == 0)
        assert(C.undo(s) and #s.tab[1] == 4 and s.moves == 0)
        s.limit = true
        assert(C.tabToCell(s, 1) and s.cells[4] == id(2, 6))
        assert(not C.tabToCell(s, 1), "cells full")
        assert(C.maxMove(s, 2) == 1)
        s.cells = { 0, 0, 0, 0 }
        s.found = { 0, 0, 0, 0 }
        s.tab[3] = { id(3, 13), id(3, 1) }
        s.tab[4] = { id(3, 2) }
        assert(C.toFound(s, "tab", 3) and s.found[3] == 1)
        assert(C.cellToTab(s, 1, 2) == false)
        s.cells[1] = id(3, 2)
        s.tab[4] = {}
        assert(C.toFound(s, "cell", 1) and s.found[3] == 2)
        s.found = { 13, 13, 13, 12 }
        s.tab = { { id(4, 13) }, {}, {}, {}, {}, {}, {}, {} }
        assert(C.autoCollect(s) == 1 and C.won(s))
    end)

    test("freecell session tap flow", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, Game, nil)
        local s = g.state()
        assert(H.view.grid.ratio and H.view.grid.cols == 8 and H.view.help)
        s.tab[1] = { id(1, 7) }
        s.tab[2] = { id(2, 6) }
        H.view.grid.on_tap(2, 2)
        assert(H.view.grid.cell(2, 2).fill == "black")
        H.view.grid.on_tap(2, 1)
        assert(#s.tab[1] == 2 and #s.tab[2] == 0 and H.saved.freecell.state.moves == 1)
        H.view.grid.on_tap(3, 1) -- select 6♥, park in a free cell
        H.view.grid.on_tap(1, 1)
        assert(s.cells[1] == id(2, 6) and #s.tab[1] == 1)
        H.view.buttons[1][1].callback()
        assert(s.cells[1] == 0 and #s.tab[1] == 2)
        H.view.buttons[1][3].callback()
        assert(#g.state().tab[1] == 7)
    end)
end
