return function(t)
    local test, Rng = t.test, t.Rng
    local C = require("kogames.games.g2048.main").core
    local function board(rows)
        local b = {}
        for _, r in ipairs(rows) do for _, v in ipairs(r) do b[#b + 1] = v end end
        return { n = #rows, board = b, score = 0 }
    end
    local function row(s, k) local n = s.n local o = {} for i = 1, n do o[i] = s.board[(k - 1) * n + i] end return table.concat(o, ",") end

    test("2048: merge once per move, toward the move direction", function()
        local s = board({ { 2, 2, 2, 0 }, { 4, 4, 4, 4 }, { 2, 2, 4, 8 }, { 0, 2, 2, 4 } })
        assert(C.move(s, "west"))
        assert(row(s, 1) == "4,2,0,0" and row(s, 2) == "8,8,0,0" and row(s, 3) == "4,4,8,0" and row(s, 4) == "4,4,0,0")
        assert(s.score == 4 + 16 + 4 + 4)
        s = board({ { 2, 2, 2, 0 }, { 4, 4, 4, 4 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } })
        assert(C.move(s, "east"))
        assert(row(s, 1) == "0,0,2,4" and row(s, 2) == "0,0,8,8")
        s = board({ { 2, 0, 0 }, { 2, 0, 0 }, { 2, 0, 0 } })
        assert(C.move(s, "south") and s.board[7] == 4 and s.board[4] == 2 and s.board[1] == 0)
    end)

    test("2048: spawn only 2/4, win flag, no spawn on blocked move", function()
        local s = { n = 4, board = {}, score = 0 }
        for i = 1, 16 do s.board[i] = 0 end
        local twos, fours = 0, 0
        for seed = 1, 400 do
            for i = 1, 16 do s.board[i] = 0 end
            C.spawn(s, Rng.new(seed))
            for i = 1, 16 do
                if s.board[i] == 2 then twos = twos + 1 elseif s.board[i] == 4 then fours = fours + 1 end
            end
        end
        assert(twos + fours == 400 and fours > 10 and fours < 80)
        local w = board({ { 1024, 1024 }, { 0, 0 } })
        assert(C.move(w, "west") and w.won and w.board[1] == 2048)
    end)

    test("2048: best score is recorded during play, not only at game over", function()
        local H = require("kogames.games.g2048.main") and t.H
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.g2048.main"), nil)
        local s = g.state()
        s.n, s.board, s.score = 4, { 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, 0
        g.step("west")
        assert(s.score == 4 and not s.over)
        assert(H.saved["stats_2048"] and H.saved["stats_2048"].best == 4)
    end)
end
