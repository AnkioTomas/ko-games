return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.match3.main").core

    test("match3: deal has no matches but has a move", function()
        for seed = 1, 20 do
            local b = C.deal(Rng.new(seed))
            local _, any = C.matches(b)
            assert(not any and C.hasMove(b))
        end
    end)

    test("match3: invalid swap reverts, valid swap scores and refills", function()
        local s = C.fresh(Rng.new(5), 30)
        local ok, a, b = C.hasMove(s.board)
        assert(ok)
        local bad
        for i = 1, 63 do
            if i % 8 ~= 0 then
                local x = { board = { unpack(s.board) }, moves = 30, score = 0 }
                x.board[i], x.board[i + 1] = x.board[i + 1], x.board[i]
                local _, any = C.matches(x.board)
                if not any then bad = i break end
            end
        end
        local snapshot = table.concat(s.board, ",")
        assert(C.swapTiles(s, bad, bad + 1, Rng.new(1)) == nil)
        assert(table.concat(s.board, ",") == snapshot and s.moves == 30)
        assert(C.swapTiles(s, a, b, Rng.new(1)))
        assert(s.moves == 29 and s.score >= 30)
        local _, any = C.matches(s.board)
        assert(not any)
        for _, v in ipairs(s.board) do assert(v >= 1 and v <= 6) end
    end)

    test("match3: session ends and records best", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.match3.main"), nil)
        local s = g.state()
        s.moves = 1
        local _, a, b = C.hasMove(s.board)
        local ra, ca = math.floor((a - 1) / 8) + 1, (a - 1) % 8 + 1
        local rb, cb = math.floor((b - 1) / 8) + 1, (b - 1) % 8 + 1
        g.tap(ra, ca)
        g.tap(rb, cb)
        assert(s.moves == 0 and s.over and H.saved["stats_match3"].best30 == s.score)
    end)
end
