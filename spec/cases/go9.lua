return function(t)
    local test, H = t.test, t.H
    local M = require("kogames.games.go9")
    local C = M.core

    local function board(rows)
        local b = {}
        for r = 1, 9 do
            for c = 1, 9 do
                local ch = (rows[r] or ""):sub(c, c)
                b[(r - 1) * 9 + c] = ch == "X" and 1 or (ch == "O" and 2 or 0)
            end
        end
        return b
    end

    test("go9 capture, suicide and ko", function()
        local sb = board({ ".O", "O" })
        local n2, w2 = C.place(sb, 1, 1, nil)
        assert(not n2 and w2 == "suicide")
        -- capture: black stone at (1,1) with white at (1,2), white plays (2,1)
        local n4, c4 = C.place(board({ "XO", "." }), 10, 2, nil)
        assert(n4 and c4 == 1 and n4[1] == 0)
        -- ko
        local kb = board({ ".XO", "X.XO", ".XO" })
        local after, got = C.place(kb, 11, 2, nil)
        assert(after and got == 1)
        local s = C.fresh()
        s.board = kb
        s.turn = 2
        assert(C.play(s, 11))
        s.turn = 1
        local ok, reason = C.play(s, 12)
        assert(not ok and reason == "ko")
    end)

    test("go9 two passes end with area scoring", function()
        local s = C.fresh()
        s.board = board({ "XXXXXXXXX", "XXXXXXXXX", "XXXXXXXXX", "XXXXXXXXX", "XXXXXXXXX", "OOOOOOOOO", "OOOOOOOOO", "OOOOOOOOO", "OOOOOOOOO" })
        local m, b, w = C.margin(s.board)
        assert(b == 45 and w == 36 and m == 1.5)
        assert(C.pass(s) and not s.over)
        assert(C.pass(s) and s.over and C.winner(s) == 1)
    end)

    test("go9 AI plays legal moves and takes a capture", function()
        local s = C.fresh()
        C.play(s, 41)
        local t0 = os.clock()
        local mv = C.aiMove(s, t.Rng and t.Rng.new(3))
        assert(mv and C.place(s.board, mv, 2, s.prev) and os.clock() - t0 < 1)
        s.turn = 2
        local cap = board({ "XO", "", "" })
        s.board = cap
        s.board[11] = 1 -- black (2,2) irrelevant stone
        s.board[10] = 0
        assert(C.aiMove(s) == 10)
    end)

    test("go9 random playout terminates", function()
        local s = C.fresh()
        local rng = t.Rng.new(5)
        local n = 0
        while not s.over and n < 400 do
            if s.turn == 1 then
                local list = {}
                for i = 1, 81 do if C.place(s.board, i, 1, s.prev) then list[#list + 1] = i end end
                if #list == 0 or n > 150 then C.pass(s) else C.play(s, list[rng:int(#list)]) end
            else
                C.aiTurn(s, rng)
            end
            n = n + 1
        end
        assert(s.over)
    end)

    test("go9 session: tap, pass, undo", function()
        H.saved, H.view = {}, nil
        require("kogames.registry").launch(H.host, M, nil)
        H.view.grid.on_tap(5, 5)
        local st = H.saved.go9.state
        assert(st.board[41] == 1 and #st.history == 1 and st.turn == 1)
        H.view.grid.on_tap(5, 5)
        assert(H.saved.go9.state.board[41] == 1)
        H.view.buttons[1][2].callback()
        assert(H.saved.go9.state.board[41] == 0)
    end)
end
