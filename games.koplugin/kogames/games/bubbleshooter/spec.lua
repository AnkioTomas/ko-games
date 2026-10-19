return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.bubbleshooter.main").core
    local COLS, ROWS = 9, 11

    local function blank(colors)
        local s = C.fresh(Rng.new(1), "normal")
        for i = 1, ROWS * COLS do s.board[i] = 0 end
        s.colors, s.misses, s.score = colors or 5, 0, 0
        return s
    end

    test("bubbleshooter: fresh board and landing", function()
        local s = C.fresh(Rng.new(2), "normal")
        for c = 1, COLS do assert(C.landing(s, c) == 6) end
        local e = blank()
        assert(C.landing(e, 3) == 1)
    end)

    test("bubbleshooter: three of a colour pop and floating bubbles fall", function()
        local s = blank()
        s.board[1], s.board[2], s.board[9] = 2, 2, 4
        s.board[COLS + 2] = 3 -- 挂在被消除的泡泡下面，应掉落
        s.cur, s.nxt = 2, 2
        local r = C.fire(s, Rng.new(1), 3)
        assert(r.popped == 3 and r.fell == 1 and s.board[COLS + 2] == 0 and s.board[9] == 4)
        assert(s.score == 3 * 10 + 20 and not r.cleared)
        local e = blank()
        e.board[1], e.cur, e.nxt = 2, 2, 2
        local r2 = C.fire(e, Rng.new(1), 1) -- 只有两个相连，不消除
        assert(r2.popped == 0 and e.misses == 1)
        local f = blank()
        f.board[1], f.cur, f.nxt = 2, 2, 2
        f.board[2] = 2
        local r3 = C.fire(f, Rng.new(1), 3)
        assert(r3.cleared and f.score == 3 * 10 + 200)
    end)

    test("bubbleshooter: misses descend a row and bottom row ends game", function()
        local s = C.fresh(Rng.new(4), "normal")
        local rng = Rng.new(9)
        local guard = 0
        while not C.over(s) and guard < 400 do
            guard = guard + 1
            s.aim = rng:int(COLS)
            C.fire(s, rng, s.aim)
        end
        assert(C.over(s) or guard == 400)
        local e = blank()
        e.misses, e.period = 4, 5
        e.board[1] = 1
        e.cur, e.nxt = 2, 2
        C.fire(e, Rng.new(1), 5)
        assert(e.board[COLS + 1] == 1 and e.misses == 0)
    end)

    test("bubbleshooter: session fire and persist", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.bubbleshooter.main"), nil)
        local s = g.state()
        local cur = s.cur
        g.fire()
        assert(H.saved.bubbleshooter and H.saved.bubbleshooter.state)
        assert(H.view.grid.rows == ROWS + 1 and cur)
    end)
end
