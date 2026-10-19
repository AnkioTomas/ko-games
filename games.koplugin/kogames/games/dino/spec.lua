return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local launch = dofile("spec/clock.lua")(t)
    local D = require("kogames.games.dino.main")
    local C = D.core

    local function bare(level)
        local s = C.fresh(Rng.new(1), level)
        s.nextX = 1000
        return s
    end

    test("dino jump arc lasts about five ticks and clears a cactus", function()
        local rng = Rng.new(3)
        local s = bare()
        s.obs = { { kind = "big", w = 2, h = 4, x = 7 } }
        assert(C.jump(s))
        local air = 0
        for _ = 1, 8 do
            C.step(s, rng)
            if s.y > 0 then air = air + 1 end
            assert(not s.over)
        end
        assert(air == D.AIR, "airborne ticks " .. air)
        assert(not C.jump({ over = true, y = 0 }) and not C.jump({ y = 3 }))
    end)

    test("dino dies on a cactus when not jumping", function()
        local s = bare()
        s.obs = { { kind = "small", w = 1, h = 3, x = 6 } }
        local r
        for _ = 1, 6 do r = C.step(s, Rng.new(1)) if s.over then break end end
        assert(s.over and r == "dead")
    end)

    test("dino pterodactyl heights need jump, duck or nothing", function()
        local function run(by, act)
            local s = bare()
            s.dist = 300
            s.obs = { { kind = "ptero", w = 2, h = 2, by = by, x = 6 } }
            local rng = Rng.new(1)
            for i = 1, 10 do
                if i == 1 and act then C[act](s) end
                C.step(s, rng)
            end
            return not s.over
        end
        assert(not run(3) and run(3, "duck"))
        assert(not run(1) and not run(1, "duck") and run(1, "jump"))
        assert(run(6) and not run(6, "jump"))
    end)

    test("dino duck lasts two ticks", function()
        local s = bare()
        local rng = Rng.new(1)
        C.duck(s) C.step(s, rng)
        assert(C.height(s) == 2)
        C.step(s, rng)
        assert(C.height(s) == 4 or s.duck == 0)
    end)

    test("dino speed rises and score milestones fire", function()
        assert(C.speed(0) == 1 and C.speed(250) == 2 and C.speed(700) == 3)
        local s = bare()
        s.dist = 99
        local r = C.step(s, Rng.new(1))
        assert(r == "milestone" and s.flash > 0)
    end)

    test("dino spacing is always jumpable and a simple bot survives", function()
        for level = 1, 3 do
            for seed = 1, 3 do
                local rng = Rng.new(seed)
                local s = C.fresh(rng, level)
                for _ = 1, 1500 do
                    local sp = C.speed(s.dist)
                    if s.y == 0 then
                        for _, o in ipairs(s.obs) do
                            if o.x + o.w - 1 >= D.DX then
                                local gap = o.x - (D.DX + 1)
                                if o.kind == "ptero" and o.by == 3 then
                                    if gap >= 1 and gap <= 2 * sp - 2 then C.duck(s) end
                                elseif o.kind == "ptero" and o.by == 6 then
                                    -- 直接跑过
                                elseif gap <= sp then C.jump(s) end
                                break
                            end
                        end
                    end
                    C.step(s, rng)
                    assert(not s.over, ("bot died lvl %d seed %d dist %d"):format(level, seed, s.dist))
                end
                assert(s.dist > 1500)
                for i = 2, #s.obs do
                    local a, b = s.obs[i - 1], s.obs[i]
                    assert(b.x - (a.x + a.w) >= C.minGap(1), "gap too small")
                end
            end
        end
    end)

    test("dino session ticks, saves and restores", function()
        local g, host, ctx = launch(D)
        assert(H.view.canvas and #H.view.buttons[1] == 3)
        assert(host.pending() == 0, "waits for start")
        H.view.canvas.on_tap(10, 10) -- 起跳并开始
        assert(host.pending() == 1 and not g.paused())
        local shows = H.shows
        host.advance(D.INTERVALS[2] * 2 + 0.01)
        assert(g.state().ticks == 2 and H.shows == shows + 2 and g.state().y > 0)
        g.pause()
        assert(host.pending() == 0 and g.paused())
        ctx:exit()
        assert(H.saved["dino"] and H.saved["dino"].state.ticks == 2)
    end)

    test("dino game over records best and offers restart", function()
        local g, host = launch(D)
        g.state().dist = 140
        g.state().obs = { { kind = "big", w = 2, h = 4, x = 5 } }
        g.toggle()
        host.advance(5)
        assert(g.state().over and host.pending() == 0)
        assert(H.saved["stats_dino"].best >= 140)
        assert(H.view.buttons[1][3].text == "重来")
        local d = { rect = function() end, text = function() end }
        H.view.canvas.draw(d)
        H.view.buttons[1][3].callback()
        assert(not g.state().over and g.state().dist == 0)
    end)

    test("dino difficulty changes tick interval", function()
        local g, host = launch(D)
        g.setLevel(3)
        g.toggle()
        host.advance(D.INTERVALS[3] + 0.01)
        assert(g.state().ticks == 1 and g.state().level == 3)
    end)
end
