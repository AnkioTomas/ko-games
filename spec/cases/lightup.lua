return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view, H.settings = {}, nil, {}
        return require("kogames.registry").launch(H.host, require("kogames.games.lightup"), nil)
    end

    test("lightup: analysis rules", function()
        local C = require("kogames.games.lightup").core
        local W, B = C.WHITE, C.WALL
        -- W W W / W 1 W / W W W
        local g = { W, W, W, W, 1, W, W, W, W }
        local a = C.analyze(g, 3, { 1, 0, 0, 0, 0, 0, 0, 0, 1 })
        assert(a.lit[2] and a.lit[7] and a.lit[8] and not a.lit[5] and not a.badLamp[1] and not a.solved)
        a = C.analyze(g, 3, { 0, 1, 0, 1, 0, 0, 0, 0, 0 })
        assert(not a.badLamp[2] and not a.solved)
        a = C.analyze({ W, W, W, B, W, W, W, W, W }, 3, { 1, 1, 0, 0, 0, 0, 0, 0, 0 })
        assert(a.badLamp[1] and a.badLamp[2])
    end)

    test("lightup: generated puzzles unique, sound and fast", function()
        local C = require("kogames.games.lightup").core
        for _, n in ipairs({ 7, 10 }) do
            local t0 = os.clock()
            for seed = 1, 4 do
                local s = C.fresh(Rng.new(seed), n)
                local cnt, sol = C.solve(s.g, n, 2)
                assert(cnt >= 1)
                local user = {}
                for i = 1, n * n do user[i] = sol[i] == 1 and 1 or 0 end
                assert(C.solved(s.g, n, user))
            end
            assert((os.clock() - t0) / 4 < 1)
        end
    end)

    test("lightup: taps, hold, win", function()
        local g = launch()
        local s = g.state()
        local n = s.n
        local C = require("kogames.games.lightup").core
        local function pos(i) return math.floor((i - 1) / n) + 1, (i - 1) % n + 1 end
        local wall
        for i = 1, n * n do if s.g[i] ~= C.WHITE then wall = i break end end
        if wall then H.view.grid.on_tap(pos(wall)) assert(s.user[wall] == 0) end
        local white
        for i = 1, n * n do if s.g[i] == C.WHITE then white = i break end end
        H.view.grid.on_hold(pos(white))
        assert(s.user[white] == 2)
        H.view.grid.on_tap(pos(white))
        assert(s.user[white] == 1)
        H.view.grid.on_tap(pos(white))
        assert(s.user[white] == 0)
        local _, sol = C.solve(s.g, n, 1)
        for i = 1, n * n do if sol[i] == 1 then H.view.grid.on_tap(pos(i)) end end
        assert(s.done and H.view.status:find("完成"))
    end)
end
