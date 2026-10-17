return function(t)
    local test, H = t.test, t.H
    local M = require("kogames.games.connect4")
    local C = M.core
    local launchDef = function()
        H.saved, H.view = {}, nil
        return require("kogames.registry").launch(H.host, M, nil)
    end

    test("connect4 wins in all four directions", function()
        local function check(cells, who)
            local s = C.fresh()
            for _, rc in ipairs(cells) do s.board[(rc[1] - 1) * 7 + rc[2]] = who end
            local last = cells[2]
            assert(C.wins(s.board, last[1], last[2], who))
            s.board[(cells[1][1] - 1) * 7 + cells[1][2]] = 0
            assert(not C.wins(s.board, last[1], last[2], who))
        end
        check({ { 6, 1 }, { 6, 2 }, { 6, 3 }, { 6, 4 } }, 1)
        check({ { 3, 5 }, { 4, 5 }, { 5, 5 }, { 6, 5 } }, 2)
        check({ { 6, 1 }, { 5, 2 }, { 4, 3 }, { 3, 4 } }, 1)
        check({ { 3, 1 }, { 4, 2 }, { 5, 3 }, { 6, 4 } }, 2)
        local v = C.fresh()
        for _ = 1, 4 do C.drop(v, 3, 2) end
        assert(v.winner == 2)
    end)

    test("connect4 rejects full column and bad input", function()
        local s = C.fresh()
        for i = 1, 6 do assert(C.drop(s, 1, i % 2 + 1)) end
        assert(not C.drop(s, 1, 1))
        assert(not C.drop(s, 8, 1))
    end)

    test("connect4 AI wins/blocks and answers fast", function()
        local s = C.fresh()
        C.drop(s, 1, 1) C.drop(s, 1, 1) C.drop(s, 1, 1)
        assert(C.aiMove(s) == 1)
        local s2 = C.fresh()
        for _ = 1, 3 do C.drop(s2, 2, 2) C.drop(s2, 7, 1) end
        assert(C.aiMove(s2) == 2)
        local t0 = os.clock()
        local s3 = C.fresh()
        C.drop(s3, 4, 1)
        local c = C.aiMove(s3)
        assert(c and c >= 1 and c <= 7 and os.clock() - t0 < 1)
    end)

    test("connect4 session: tap, save, undo", function()
        launchDef()
        H.view.grid.on_tap(1, 4)
        local s = H.saved.connect4.state
        assert(#s.moves == 2 and s.board[(6 - 1) * 7 + 4] == 1)
        H.view.buttons[1][1].callback()
        assert(#H.saved.connect4.state.moves == 0)
    end)
end
