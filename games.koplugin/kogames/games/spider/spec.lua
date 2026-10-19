return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local Game = require("kogames.games.spider.main")
    local C = Game.core
    local function id(suit, rank) return (suit - 1) * 13 + rank end
    local function blank()
        local s = C.fresh(Rng.new(1), 1)
        s.tab = { {}, {}, {}, {}, {}, {}, {}, {}, {}, {} }
        s.stock, s.undo, s.moves, s.done = {}, {}, 0, 0
        return s
    end

    test("spider deal for 1/2/4 suits", function()
        for _, su in ipairs({ 1, 2, 4 }) do
            local s = C.fresh(Rng.new(9), su)
            local count, suitsSeen, n = {}, {}, 0
            local function add(v) v = math.abs(v) count[v] = (count[v] or 0) + 1 suitsSeen[C.suit(v)] = true n = n + 1 end
            for c = 1, 10 do
                assert(#s.tab[c] == (c <= 4 and 6 or 5) and s.tab[c][#s.tab[c]] > 0 and s.tab[c][1] < 0)
                for _, v in ipairs(s.tab[c]) do add(v) end
            end
            for _, v in ipairs(s.stock) do add(v) end
            assert(n == 104 and #s.stock == 50)
            local kinds = 0
            for _ in pairs(suitsSeen) do kinds = kinds + 1 end
            assert(kinds == su)
            for _, c in pairs(count) do assert(c == 8 / su) end
        end
    end)

    test("spider moves, run removal, deal, undo", function()
        local s = blank()
        s.tab[1] = { -id(1, 5), id(1, 6), id(2, 5) }  -- 6♠ 5♥ : not a run
        s.tab[2] = { id(3, 6) }
        assert(not C.moveTab(s, 1, 2, 2), "mixed suit run")
        assert(C.moveTab(s, 1, 3, 2) and s.tab[1][2] == id(1, 6), "5♥ onto 6♦")
        assert(C.moveTab(s, 1, 1, 3) == false, "hidden card")
        assert(C.undo(s) and #s.tab[1] == 3 and s.tab[1][1] < 0)
        -- full run removal
        local w = blank()
        w.tab[1] = { -id(2, 3) }
        for r = 13, 2, -1 do w.tab[1][#w.tab[1] + 1] = id(1, r) end
        w.tab[2] = { id(1, 1) }
        w.tab[1][1] = -id(2, 3)
        assert(C.moveTab(w, 2, 1, 1) and w.done == 1 and #w.tab[1] == 1 and w.tab[1][1] > 0)
        assert(C.undo(w) and w.done == 0 and #w.tab[1] == 13)
        -- deal rule
        local d = C.fresh(Rng.new(2), 1)
        assert(C.deal(d) and #d.stock == 40 and #d.tab[1] == 7)
        d.tab[3] = {}
        assert(not C.canDeal(d) and not C.deal(d))
        local last = blank()
        last.done = 7
        local run = {}
        for r = 13, 1, -1 do if r > 1 then run[#run + 1] = id(1, r) end end
        last.tab[1] = run
        for c = 2, 10 do last.tab[c] = { id(2, 5) } end
        last.stock = {}
        for c = 1, 9 do last.stock[c] = id(2, 6) end
        last.stock[10] = id(1, 1)
        assert(C.deal(last) and C.won(last))
        local win = blank()
        win.done = 8
        assert(C.won(win))
    end)

    test("spider session tap flow", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, Game, nil)
        local s = g.state()
        assert(H.view.grid.cols == 10 and H.view.grid.ratio and H.view.help)
        assert(H.view.grid.cell(2, 1).rank and H.view.grid.cell(1, 1).text)
        s.tab[1] = { id(1, 7) }
        s.tab[2] = { id(1, 6) }
        local rows = H.view.grid.rows
        H.view.grid.on_tap(1, 2)
        assert(H.view.grid.cell(1, 2).fill == "black")
        H.view.grid.on_tap(1, 1)
        assert(#s.tab[1] == 2 and #s.tab[2] == 0 and H.saved.spider.state.moves == 1)
        H.view.buttons[1][1].callback() -- deal blocked by empty column
        assert(#s.stock == 50)
        for c = 1, 10 do s.tab[c] = { id(2, 5) } end
        local run = {}
        for r = 13, 2, -1 do run[#run + 1] = id(1, r) end
        s.tab[1], s.done, s.stock, s.moves = run, 7, {}, 5
        for c = 1, 9 do s.stock[c] = id(2, 6) end
        s.stock[10] = id(1, 1)
        H.view.buttons[1][1].callback() -- last deal completes the 8th run
        assert(C.won(s) and H.saved.stats_spider.best_moves_1 == 6)
        H.view.settings.groups[1].options[2].callback() -- 2 suits, new game
        assert(g.state().suits == 2 and #g.state().stock == 50 and rows >= 8)
    end)
end
