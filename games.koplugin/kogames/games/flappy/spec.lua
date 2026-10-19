return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local launch = dofile("spec/clock.lua")(t)
    local F = require("kogames.games.flappy.main")
    local C = F.core

    test("flappy gap centres of adjacent pipes stay within the passable shift", function()
        for level = 1, 3 do
            local rng = Rng.new(level)
            local s = C.fresh(rng, level)
            s.vy = 0
            for _ = 1, 400 do
                s.y, s.vy = 60, 0
                C.step(s, rng)
            end
            for i = 2, #s.pipes do
                assert(math.abs(s.pipes[i].cy - s.pipes[i - 1].cy) <= C.MAX_SHIFT)
                assert(s.pipes[i].cy - s.gap / 2 >= 0 and s.pipes[i].cy + s.gap / 2 <= C.GROUND)
            end
        end
    end)

    test("flappy flap, gravity, score and collisions", function()
        local rng = Rng.new(3)
        local s = C.fresh(rng, 2)
        s.y, s.vy = 60, 0
        assert(C.flap(s) and s.vy < 0)
        C.step(s, rng)
        assert(s.y < 60)
        s = C.fresh(rng, 2)
        s.pipes = { { x = C.BIRD_X - C.PIPE_W - C.BIRD_R - 2, cy = 60 }, { x = 200, cy = 60 } }
        s.y, s.vy = 60, -2
        assert(C.step(s, rng) == "score" and s.score == 1)
        s = C.fresh(rng, 2)
        s.pipes = { { x = C.BIRD_X - 3, cy = 100 } }
        s.y, s.vy = 20, 0
        assert(C.step(s, rng) == "dead" and s.over)
        s = C.fresh(rng, 2)
        s.y, s.vy = 5, -7
        assert(C.step(s, rng) == "dead")
        s = C.fresh(rng, 2)
        s.y, s.vy = 120, 6
        assert(C.step(s, rng) == "dead")
    end)

    test("flappy session starts on tap, ticks, records best and saves", function()
        local g, host = launch(F)
        assert(H.view.canvas and host.pending() == 0 and #H.view.buttons == 0 and #H.view.settings.actions == 2)
        H.view.canvas.on_tap(50, 50)
        assert(host.pending() == 1 and not g.paused())
        host.advance(F.INTERVAL + 0.01)
        assert(g.state().ticks == 1)
        g.toggle()
        assert(g.paused() and host.pending() == 0)
        g.toggle()
        g.state().score = 4
        host.advance(30)
        assert(g.state().over and host.pending() == 0)
        assert(H.saved["stats_flappy"].best >= 4)
        H.view.canvas.draw({ rect = function() end, frame = function() end, text = function() end, icon = function() end })
        H.view.canvas.on_tap(50, 50)
        assert(not g.state().over and g.state().score == 0)
        g.tap()
        g.pause()
        assert(H.saved["flappy"].state.pipes)
        local g2 = launch(F)
        assert(g2.state().ticks == 0)
    end)
end
