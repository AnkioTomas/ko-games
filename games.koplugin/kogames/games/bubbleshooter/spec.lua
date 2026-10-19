return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.bubbleshooter.main").core

    local function blank()
        local s = C.fresh(Rng.new(1), "normal")
        for i = 1, C.ROWS * C.COLS do s.board[i] = 0 end
        s.misses, s.score = 0, 0
        return s
    end
    local function put(s, r, c, v) s.board[r * C.COLS + c + 1] = v end
    local function get(s, r, c) return s.board[r * C.COLS + c + 1] end

    test("bubbleshooter: hex neighbours depend on row parity", function()
        local s = blank()
        local function has(list, r, c) for _, n in ipairs(list) do if n[1] == r and n[2] == c then return true end end end
        local n0 = C.neighbors(s, 1, 3) -- 奇数行（0 起）右移半格
        assert(#n0 == 6 and has(n0, 0, 3) and has(n0, 0, 4) and has(n0, 2, 3) and has(n0, 2, 4))
        local n1 = C.neighbors(s, 2, 0)
        assert(has(n1, 1, 0) and has(n1, 3, 0) and not has(n1, 1, -1) and #n1 == 3)
    end)

    test("bubbleshooter: straight shot, wall bounce and top snap", function()
        local s = blank()
        local r = C.trace(s, 0)
        assert(r.r == 0 and r.c == 4 or r.c == 3)
        local b = C.trace(s, 70)
        assert(#b.path >= 3 and b.r == 0)
        local x1 = b.path[2][1]
        assert(x1 > C.W - 10) -- 先撞右墙
        put(s, 0, 4, 2)
        local h = C.trace(s, 0)
        assert(h.r == 1)
        assert(C.angleTo(0, 130) == -C.MAX_ANGLE and C.angleTo(50, 10) == 0 and C.angleTo(99, C.SY + 5) == C.MAX_ANGLE)
    end)

    test("bubbleshooter: pop three and drop floating", function()
        local s = blank()
        put(s, 0, 3, 2) put(s, 0, 4, 2)
        put(s, 1, 2, 3) -- 挂在被消除泡泡下面
        put(s, 0, 7, 4)
        s.cur, s.nxt = 2, 2
        local r = C.fire(s, Rng.new(1), 0)
        assert(r.popped == 3 and r.fell == 1 and get(s, 1, 2) == 0 and get(s, 0, 7) == 4, r.popped .. "/" .. r.fell)
        assert(s.score == 30 + 20 and s.misses == 0)
    end)

    test("bubbleshooter: misses descend a row and flip parity", function()
        local s = blank()
        put(s, 0, 0, 1)
        s.cur, s.nxt, s.misses = 2, 2, s.period - 1
        local r = C.fire(s, Rng.new(1), 0)
        assert(r.descended and s.misses == 0 and s.par == 1)
        assert(get(s, 1, 0) == 1)
        for c = 0, 6 do assert(get(s, 0, c) ~= 0) end
        assert(get(s, 0, 7) == 0)
    end)

    test("bubbleshooter: dead line loses, clear levels up", function()
        local s = blank()
        for c = 0, 7 do put(s, 0, c, 1) end
        put(s, 10, 0, 3)
        s.misses, s.cur, s.nxt = 0, 2, 2
        put(s, 11, 2, 3)
        assert(C.over(s))
        local e = blank()
        put(e, 0, 3, 2) put(e, 0, 4, 2)
        e.cur, e.nxt = 2, 2
        local r = C.fire(e, Rng.new(1), 0)
        assert(r.cleared)
        C.nextLevel(e, Rng.new(2))
        assert(e.level == 2 and e.score == 30 + 200 and not C.cleared(e))
    end)

    test("bubbleshooter: random play stays consistent", function()
        local s = C.fresh(Rng.new(4), "hard")
        local rng, n = Rng.new(9), 0
        while not C.over(s) and n < 300 do
            n = n + 1
            if C.fire(s, rng, rng:int(150) - 75) and C.cleared(s) then C.nextLevel(s, rng) end
        end
        assert(C.over(s) or n == 300)
    end)

    test("bubbleshooter: session tap, buttons and restore", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.bubbleshooter.main"), nil)
        assert(H.view.canvas and H.view.canvas.w)
        local cur, nxt = g.state().cur, g.state().nxt
        H.view.canvas.on_tap(20, C.SY + 4)
        assert(g.state().cur == nxt and g.state().nxt == cur)
        assert(#(H.view.buttons or {}) == 0)
        cur = g.state().cur
        H.view.canvas.on_tap(30, 60)
        assert(H.saved.bubbleshooter and H.saved.bubbleshooter.state and g.state().aim < 0)
        local snap = g.state().score
        H.view, g = nil, nil
        g = require("kogames.registry").launch(H.host, require("kogames.games.bubbleshooter.main"), nil)
        assert(g.state().score == snap and cur)
    end)
end
