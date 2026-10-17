return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local launch, gridText = dofile("spec/clock.lua")(t)

    -- snake ------------------------------------------------------------
    local S = require("kogames.games.snake.main")
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
        assert(H.saved["stats_snake"].best >= 3)
    end)
end
