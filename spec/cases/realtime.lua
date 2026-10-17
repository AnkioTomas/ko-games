return function(t)
    local test, H, Rng = t.test, t.H, t.Rng

    -- 虚拟时钟宿主：schedule 入队，advance(秒) 按时间顺序触发
    local function clockHost()
        local h = setmetatable({}, { __index = H.host })
        local now, q, seq = 0, {}, 0
        h.pending = function() return #q end
        h.now = function() return 1000 + now end
        h.schedule = function(_, sec, fn)
            seq = seq + 1
            local item = { at = now + sec, fn = fn, id = seq }
            q[#q + 1] = item
            return item
        end
        h.unschedule = function(_, item)
            for i, v in ipairs(q) do if v == item then table.remove(q, i) return end end
        end
        h.advance = function(sec)
            local limit = now + sec
            while true do
                local bi
                for i, v in ipairs(q) do if v.at <= limit and (not bi or v.at < q[bi].at) then bi = i end end
                if not bi then break end
                local item = table.remove(q, bi)
                now = item.at
                item.fn()
            end
            now = limit
        end
        return h
    end

    local function launch(def)
        H.saved, H.view = {}, nil
        local host = clockHost()
        host.showScreen = function(_, v) H.view = v H.shows = H.shows + 1 end
        local ctx = require("kogames.ctx").new(host, def, nil)
        local game = def.new(ctx)
        ctx.on_closed = function() if game.stop then game.stop() end end
        game.start()
        return game, host, ctx
    end

    local function gridText(v)
        local g = v.grid
        local n = 0
        for r = 1, g.rows do for c = 1, g.cols do if g.cell(r, c) then n = n + 1 end end end
        return n
    end

    -- snake ------------------------------------------------------------
    local S = require("kogames.games.snake")
    local SC = S.core

    test("snake moves, eats, grows and forbids reversing", function()
        local rng = Rng.new(5)
        local s = SC.fresh(rng)
        s.food = { s.body[1][1], s.body[1][2] + 1 }
        assert(not SC.turn(s, "west"))
        assert(SC.step(s, rng) == "eat" and #s.body == 4 and s.score == 1)
        assert(SC.turn(s, "north") and SC.step(s, rng) == "move" and #s.body == 4)
    end)

    test("snake dies on wall and on itself, tail chase is allowed", function()
        local rng = Rng.new(5)
        local s = SC.fresh(rng)
        s.body = { { 1, 1 }, { 1, 2 }, { 1, 3 } }
        s.dir, s.moved = "north", "west"
        assert(SC.step(s, rng) == "dead" and s.over)
        s = SC.fresh(rng)
        s.body = { { 2, 2 }, { 2, 3 }, { 3, 3 }, { 3, 2 } }
        s.dir, s.moved, s.food = "south", "west", { 9, 9 }
        assert(SC.step(s, rng) == "move" and not s.over) -- 追着尾巴走
        s = SC.fresh(rng)
        s.body = { { 5, 5 }, { 5, 6 }, { 6, 6 }, { 6, 5 }, { 6, 4 }, { 5, 4 } }
        s.dir, s.moved, s.food = "south", "west", { 9, 9 }
        assert(SC.step(s, rng) == "dead")
    end)

    test("snake session ticks on the virtual clock and stops cleanly", function()
        local g, host, ctx = launch(S)
        assert(H.view.grid and H.view.grid.rows == 16 and #H.view.buttons >= 3)
        assert(host.pending() == 0, "must wait for start")
        local shows = H.shows
        host.advance(10)
        assert(H.shows == shows)
        local head = g.state().body[1][2]
        g.input("north") -- turn; starts the game
        assert(host.pending() == 1 and not g.paused())
        host.advance(S.INTERVALS[2] * 2 + 0.01)
        assert(g.state().body[1][1] == 6, "moved up two cells")
        assert(H.shows == shows + 1 + 2, "one render per tick")
        g.setSpeed(5)
        assert(host.pending() == 1)
        g.pause()
        assert(host.pending() == 0 and g.paused())
        g.toggle()
        assert(host.pending() == 1)
        ctx:exit()
        assert(host.pending() == 0 and g.paused())
        assert(H.saved["snake"] and H.saved["snake"].state)
        assert(head)
    end)

    test("snake game over records best and stops the timer", function()
        local g, host = launch(S)
        g.state().score = 3
        g.input("north")
        host.advance(30)
        assert(g.state().over and host.pending() == 0)
        assert(H.saved["stats_snake"].best == 3)
    end)

    -- tetris -----------------------------------------------------------
    local TT = require("kogames.games.tetris")
    local TC = TT.core

    test("tetris shapes have 4 cells and rotate back after 4 turns", function()
        for _, k in ipairs({ "I", "O", "T", "S", "Z", "J", "L" }) do
            local a, b = TC.cells(k, 0), TC.cells(k, 4)
            assert(#a == 4)
            for i = 1, 4 do assert(a[i][1] == b[i][1] and a[i][2] == b[i][2]) end
        end
        local v = TC.cells("I", 1)
        assert(v[1][2] == v[4][2], "vertical I")
    end)

    test("tetris clears lines, scores and shifts rows down", function()
        local rng = Rng.new(3)
        local s = TC.fresh(rng, 2)
        for r = 17, 18 do for c = 3, 10 do s.board[(r - 1) * 10 + c] = 1 end end
        s.cur = { kind = "O", rot = 0, r = 1, c = 1 }
        TC.hardDrop(s, rng)
        assert(s.lines == 2 and s.score == 300 * 2 + 16)
        for i = 1, 180 do assert(s.board[i] == 0) end
    end)

    test("tetris move/rotate respect walls, game over when blocked", function()
        local rng = Rng.new(9)
        local s = TC.fresh(rng, 1)
        s.cur = { kind = "I", rot = 1, r = 1, c = 1 }
        assert(TC.rotate(s)) -- wall kick keeps it inside
        for _ = 1, 20 do TC.move(s, -1) end
        assert(TC.fits(s, s.cur.kind, s.cur.rot, s.cur.r, s.cur.c) and not TC.move(s, -1))
        for i = 1, 9 do s.board[i] = 1 end
        TC.hardDrop(s, rng)
        assert(s.over)
        assert(TC.interval(TC.fresh(rng, 5)) == 0.6 and TC.interval(TC.fresh(rng, 1)) == 1.0)
    end)

    test("tetris session gravity tick, controls and pause", function()
        local g, host, ctx = launch(TT)
        assert(H.view.grid.rows == 18 and host.pending() == 0)
        local before = gridText(H.view)
        assert(before == 8, "piece + ghost")
        g.left()
        g.toggle() -- start
        assert(host.pending() == 1)
        local r0 = g.state().cur.r
        local shows = H.shows
        host.advance(1.01)
        assert(g.state().cur.r == r0 + 1 and H.shows == shows + 1)
        local c0 = g.state().cur.c
        g.left()
        assert(g.state().cur.c == c0 - 1)
        g.toggle()
        assert(host.pending() == 0)
        local r1 = g.state().cur.r
        host.advance(10)
        assert(g.state().cur.r == r1)
        g.left()
        assert(g.state().cur.c == c0 - 1, "ignored while paused")
        g.toggle()
        g.hard()
        assert(g.state().score > 0)
        ctx:exit()
        assert(host.pending() == 0)
        assert(H.saved["tetris"] and H.saved["tetris"].state)
    end)

    test("tetris topping out records best score", function()
        local g, host = launch(TT)
        g.toggle()
        for _ = 1, 40 do if not g.state().over then g.hard() end end
        assert(g.state().over and host.pending() == 0)
        assert(H.saved["stats_tetris"].best == g.state().score)
    end)
end
