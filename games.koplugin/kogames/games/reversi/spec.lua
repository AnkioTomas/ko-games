return function(t)
    local test, H = t.test, t.H
    local M = require("kogames.games.reversi.main")
    local C = M.core

    test("reversi opening moves and flips", function()
        local s = C.fresh()
        assert(#C.legalMoves(s.board, 1) == 4)
        assert(s.board[28] == 2 and s.board[37] == 2 and s.board[29] == 1 and s.board[36] == 1) -- d4/e5 white, e4/d5 black
        local mv = C.legalMoves(s.board, 1)
        table.sort(mv)
        assert(mv[1] == 20 and mv[2] == 27 and mv[3] == 38 and mv[4] == 45)
        local f = C.flips(s.board, 20, 1) -- (3,4) flips (4,4)
        assert(#f == 1 and f[1] == 28 and s.board[20] == 0)
        assert(C.play(s, 20))
        assert(s.board[20] == 1 and s.board[28] == 1 and s.turn == 2)
        assert(not C.play(s, 1))
        local h, a = C.count(s.board)
        assert(h == 4 and a == 1)
    end)

    test("reversi game end counts discs", function()
        local s = C.fresh()
        for i = 1, 64 do s.board[i] = 0 end
        s.board[1], s.board[2] = 1, 2
        s.turn = 1
        assert(C.play(s, 3))
        assert(s.over and C.winner(s) == 1)
    end)

    test("reversi forced pass keeps the same side to move", function()
        local s = C.fresh()
        for i = 1, 64 do s.board[i] = 0 end
        -- row 1: B W . . . . . .   plus a black-only follow-up: W at (1,2), B at (1,1); black plays (1,3)? needs white between
        s.board[1], s.board[2] = 1, 2
        s.board[9], s.board[17], s.board[25] = 1, 1, 2
        s.turn = 1
        assert(C.play(s, 3)) -- flips (1,2); white then has no discs left, black can still move at (5,1)
        assert(s.passed == 2 and s.turn == 1 and not s.over)
    end)

    test("reversi AI returns a legal move quickly", function()
        local s = C.fresh()
        C.play(s, 20)
        local t0 = os.clock()
        local m = C.aiMove(s)
        assert(#C.flips(s.board, m, 2) > 0 and os.clock() - t0 < 1.5)
    end)

    test("reversi random playout terminates", function()
        local s = C.fresh()
        local n = 0
        while not s.over and n < 200 do
            local mv = C.legalMoves(s.board, s.turn)
            assert(#mv > 0)
            assert(C.play(s, mv[(n * 7) % #mv + 1]))
            n = n + 1
        end
        assert(s.over and C.winner(s) ~= nil)
    end)

    test("reversi session: tap, save, undo", function()
        H.saved, H.view = {}, nil
        require("kogames.registry").launch(H.host, M, nil)
        assert(H.view.grid.cell(3, 4).icon == "goal")
        H.view.grid.on_tap(3, 4)
        local st = H.saved.reversi.state
        assert(st.turn == 1 and st.board[20] == 1 and #st.history == 1)
        H.view.buttons[1][1].callback()
        assert(H.saved.reversi.state.board[20] == 0 and H.saved.reversi.state.turn == 1)
    end)
end
