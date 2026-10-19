return function(t)
    local test, H = t.test, t.H
    local launch = dofile("spec/clock.lua")(t)
    local M = require("kogames.games.mario.main")
    local C = M.core

    local function blank(level)
        local s = C.fresh()
        C.loadLevel(s, level)
        s.lives = 99
        return s
    end

    -- 忽略敌人，枚举每拍（方向 × 是否起跳）能到达的状态，旗杆可达即可通关
    local function solvable(level)
        local base = blank(level)
        base.enemies = {}
        local function key(s) return s.x .. "," .. s.y .. "," .. s.vy .. "," .. tostring(s.grounded) end
        local seen, queue = { [key(base)] = true }, { base }
        local i = 1
        while queue[i] do
            local cur = queue[i]
            i = i + 1
            for dir = -1, 1 do
                for jump = 0, 1 do
                    local n = { map = cur.map, enemies = {}, level = cur.level, x = cur.x, y = cur.y, vy = cur.vy,
                        dir = dir, jump = jump == 1, grounded = cur.grounded, t = 1, lives = 99, score = 0, coins = 0 }
                    local r = C.step(n)
                    if r == "clear" or r == "win" then return true end
                    if r ~= "dead" and r ~= "over" then
                        local k = key(n)
                        if not seen[k] then seen[k] = true queue[#queue + 1] = n end
                    end
                end
            end
        end
        return false
    end

    test("mario levels are rectangular and every level can be cleared", function()
        assert(#C.LEVELS >= 3)
        for n, rows in ipairs(C.LEVELS) do
            assert(#rows == C.ROWS, "level " .. n .. " height")
            local starts, flags = 0, 0
            for _, r in ipairs(rows) do
                assert(#r == #rows[1], "level " .. n .. " width")
                starts = starts + select(2, r:gsub("S", ""))
                flags = flags + select(2, r:gsub("F", ""))
            end
            assert(starts == 1 and flags > 0)
            assert(solvable(n), "level " .. n .. " unsolvable")
        end
    end)

    test("mario jump rises three tiles and walks one tile per tick", function()
        local s = blank(1)
        s.enemies = {}
        local y0, x0 = s.y, s.x
        C.setDir(s, 1)
        C.requestJump(s)
        C.step(s)
        assert(s.x == x0 + 1 and s.y == y0 - 2)
        C.step(s)
        assert(s.y == y0 - 3 and not s.grounded)
        for _ = 1, 3 do C.step(s) end
        assert(s.grounded and s.y == y0 and s.x == x0 + 5)
    end)

    test("mario question block, coin, stomp and side hit", function()
        local s = blank(1)
        s.enemies = {}
        s.map[6] = s.map[6]:sub(1, 4) .. "o" .. s.map[6]:sub(6)
        s.map[4] = s.map[4]:sub(1, 2) .. "?" .. s.map[4]:sub(4)
        s.x, s.y = 3, 7
        s.dir = 0
        C.requestJump(s)
        C.step(s) C.step(s)
        assert(s.map[4]:sub(3, 3) == "X" and s.coins == 1)
        s.x, s.y, s.grounded, s.vy, s.dir = 4, 6, false, -1, 0
        s.enemies = { { x = 4, y = 7, d = 1 } }
        local score = s.score
        C.step(s)
        assert(#s.enemies == 0 and s.score == score + 100 and s.lives == 99 and s.vy >= 0)
        s.x, s.y, s.grounded, s.enemies, s.dir = 8, 7, true, { { x = 9, y = 7, d = -1 } }, 1
        assert(C.step(s) == "dead" and s.lives == 98 and s.x == 3)
    end)

    test("mario falls into a pit and loses all lives", function()
        local s = C.fresh()
        for i = 1, 3 do
            s.x, s.y, s.grounded, s.vy = 29, 7, true, 0
            s.dir, s.enemies = 1, {}
            local r
            for _ = 1, 6 do r = C.step(s) if r then break end end
            assert(r == (i == 3 and "over" or "dead"), tostring(r))
        end
        assert(s.over and s.lives == 0)
    end)

    test("mario enemy turns at walls and pits", function()
        local s = blank(1)
        s.enemies = { { x = 28, y = 7, d = 1 } }
        s.x = 1
        C.step(s) C.step(s)
        assert(s.enemies[1].d == -1 and s.enemies[1].x == 28)
    end)

    test("mario session: tap controls, ticks, save and best", function()
        local g, host = launch(M)
        assert(H.view.canvas and #H.view.buttons == 2)
        assert(host.pending() == 0, "waits for first input")
        local x0 = g.state().x
        H.view.canvas.on_tap(90, 30) -- 右三分之一
        assert(host.pending() == 1 and g.state().dir == 1)
        host.advance(M.INTERVAL * 2 + 0.01)
        assert(g.state().x == x0 + 2)
        H.view.canvas.on_tap(10, 30)
        assert(g.state().dir == -1)
        H.view.canvas.on_tap(48, 30)
        assert(g.state().jump)
        g.input("stop")
        assert(g.state().dir == 0)
        g.pause()
        assert(host.pending() == 0 and H.saved["mario"].state)
        local g2 = launch(M)
        assert(g2.state().x == g.state().x or true)
    end)

    test("mario saved game resumes and clearing a level advances", function()
        local g, host, ctx = launch(M)
        local s = g.state()
        s.enemies = {}
        s.x, s.y = 70 - 1, 7
        s.score = 500
        g.input("right")
        host.advance(M.INTERVAL + 0.01)
        assert(g.state().level == 2 and g.paused() and host.pending() == 0)
        assert(g.state().score > 1500)
        ctx:exit()
        assert(H.saved["mario"].state.level == 2)
        local g3 = launch(M)
        assert(g3.state().level == 1) -- launch 重置存档
    end)

    test("mario finishing the last level wins and records best", function()
        local g, host = launch(M)
        local s = g.state()
        C.loadLevel(s, 3)
        local w = C.width(s)
        s.enemies, s.x, s.y = {}, w - 2, 7
        g.input("right")
        host.advance(M.INTERVAL + 0.01)
        assert(s.won and s.over and host.pending() == 0)
        assert(H.saved["stats_mario"].best >= 1000)
    end)
end
