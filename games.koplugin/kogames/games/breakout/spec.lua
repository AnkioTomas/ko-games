return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local launch = dofile("spec/clock.lua")(t)
    local B = require("kogames.games.breakout.main")
    local C = B.core

    local function empty(s)
        for i = 1, #s.bricks do s.bricks[i] = 0 end
    end

    test("breakout layouts differ by level and paddle snaps to whole cells", function()
        local a, b = C.layout(1), C.layout(2)
        local diff = false
        for i = 1, #a do if a[i] ~= b[i] then diff = true end end
        assert(diff and C.speedOf(2) > C.speedOf(1))
        local s = C.fresh(1)
        C.movePaddle(s, 33.4)
        assert(s.px == 33 and s.bx == 33 + C.PW / 2)
        C.movePaddle(s, -50)
        assert(s.px == 0)
        C.movePaddle(s, 500)
        assert(s.px == C.W - C.PW)
    end)

    test("breakout ball bounces off walls, bricks and paddle without tunnelling", function()
        local s = C.fresh(1)
        s.stuck = false
        s.bx, s.by, s.vx, s.vy = 3, 80, -9, 0.5
        C.step(s)
        assert(s.vx > 0 and s.bx >= C.R)
        s.bx, s.by, s.vx, s.vy = 55, 60, 0, -9 -- 直线向上穿过砖块区
        local before = C.remaining(s)
        local ev = C.step(s)
        assert(C.remaining(s) == before - 1 and s.vy > 0 and ev[1] == "brick" and s.score > 0)
        s.bx, s.by, s.vx, s.vy = 50, C.PY - 6, 0, 9
        s.px = 40
        local ev2 = C.step(s)
        assert(ev2[1] == "paddle" and s.vy < 0)
        s.px = 60 -- 击中挡板左缘：向左反弹
        s.bx, s.by, s.vx, s.vy = 61, C.PY - 6, 0, 9
        C.step(s)
        assert(s.vx < 0 and s.vy < 0)
    end)

    test("breakout loses lives, game over and clears levels", function()
        local s = C.fresh(1)
        s.stuck, s.px = false, 0
        s.bx, s.by, s.vx, s.vy = 80, 138, 0, 9
        local ev = C.step(s)
        assert(ev[#ev] == "lost" and s.lives == 2 and s.stuck)
        s.lives = 1
        s.stuck, s.bx, s.by, s.vx, s.vy = false, 80, 138, 0, 9
        ev = C.step(s)
        assert(ev[#ev] == "over" and s.over)
        s = C.fresh(1)
        empty(s)
        s.bricks[5 * C.COLS + 5] = 1
        s.stuck, s.bx, s.by, s.vx, s.vy = false, 45, 20 + 5 * 5 + 7, 0, -9
        ev = C.step(s)
        assert(ev[#ev] == "clear")
        C.nextLevel(s)
        assert(s.level == 2 and s.stuck and C.remaining(s) > 0)
    end)

    test("breakout session: tap, buttons, serve, tick, save and restore", function()
        local g, host = launch(B)
        assert(H.view.canvas and #H.view.buttons == 0 and host.pending() == 0)
        H.view.canvas.on_tap(72, 100) -- 点画布：挡板移过去，同时发球
        assert(g.state().px == 62)
        assert(not g.state().stuck and host.pending() == 1 and not g.paused())
        host.advance(B.INTERVAL + 0.01)
        assert(g.state().by < 126)
        g.toggle()
        assert(g.paused() and host.pending() == 0)
        H.view.canvas.on_tap(30, 100) -- 暂停中点画布：移动挡板并继续
        assert(g.state().px == 20 and not g.paused() and host.pending() == 1)
        g.toggle()
        g.state().score = 12
        g.stop()
        assert(H.saved["breakout"].state.score == 12)
        local g2 = launch(B)
        assert(g2.state().score == 0)
        g.state().lives = 1
        g.state().stuck, g.state().bx, g.state().by, g.state().vy = false, 5, 135, 9
        g.state().over = false
        g.toggle()
        host.advance(5)
    end)
end
