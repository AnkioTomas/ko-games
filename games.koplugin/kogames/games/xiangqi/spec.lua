return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local M = require("kogames.games.xiangqi.main")
    local C = M.core
    local function at(r, c) return (r - 1) * 9 + c end
    local function empty()
        local s = C.fresh()
        for i = 1, 90 do s.board[i] = 0 end
        return s
    end

    test("xiangqi opening has 44 legal moves per side", function()
        local s = C.fresh()
        assert(#C.legalMoves(s.board, 1) == 44)
        assert(#C.legalMoves(s.board, -1) == 44)
    end)

    test("xiangqi horse leg, cannon screen, elephant river", function()
        local s = C.fresh()
        local d = C.destinations(s.board, at(10, 2)) -- horse: legs blocked on sides only up front free
        assert(d[at(8, 1)] and d[at(8, 3)] and not d[at(9, 4)])
        local cd = C.destinations(s.board, at(8, 2)) -- cannon captures across screen
        assert(cd[at(3, 2)] == nil and cd[at(2, 2)] == nil)
        assert(cd[at(1, 2)] == true)
        local e = empty()
        e.board[at(6, 3)] = 3
        e.board[at(10, 5)] = 1
        e.board[at(1, 4)] = -1
        local ed = C.destinations(e.board, at(6, 3))
        assert(ed[at(8, 1)] and ed[at(8, 5)] and not ed[at(4, 1)] and not ed[at(4, 5)])
        e.board[at(7, 4)] = -5 -- blocks the eye
        assert(not C.destinations(e.board, at(6, 3))[at(8, 5)])
    end)

    test("xiangqi flying general and pinned piece", function()
        local s = empty()
        s.board[at(10, 5)], s.board[at(1, 5)] = 1, -1
        assert(C.inCheck(s.board, 1) and C.inCheck(s.board, -1))
        s.board[at(5, 5)] = 5 -- red rook shields, now pinned to its file
        assert(not C.inCheck(s.board, 1))
        local d = C.destinations(s.board, at(5, 5))
        assert(d[at(6, 5)] and d[at(1, 5)])
        assert(not d[at(5, 4)])
    end)

    test("xiangqi checkmate and stalemate lose", function()
        local s = empty()
        s.board[at(1, 4)], s.board[at(10, 6)] = -1, 1
        s.board[at(1, 1)] = 5 -- red rook gives check along row 1
        s.board[at(2, 5)], s.board[at(2, 6)] = 5, 5
        s.turn = -1
        assert(C.inCheck(s.board, -1))
        assert(#C.legalMoves(s.board, -1) == 0)
        s.turn = 1
        assert(C.play(s, at(10, 6), at(9, 6)))
        assert(s.over and s.winner == 1)
    end)

    test("xiangqi AI is legal, fast, and takes a free piece", function()
        local s = C.fresh(2)
        C.play(s, at(10, 2), at(8, 3))
        local t0 = os.clock()
        local f, to = C.aiMove(s, 2, Rng.new(1))
        assert(os.clock() - t0 < 1.2)
        assert(C.destinations(s.board, f)[to])
        local e = empty()
        e.board[at(10, 5)], e.board[at(1, 4)] = 1, -1
        e.board[at(5, 1)], e.board[at(5, 9)] = -5, 4
        e.turn = -1
        local ff, tt = C.aiMove(e, 2, Rng.new(1))
        assert(ff == at(5, 1) and tt == at(5, 9))
    end)

    test("xiangqi session: select, move, AI replies, undo, save", function()
        H.saved, H.view = {}, nil
        require("kogames.registry").launch(H.host, M, nil)
        H.view.grid.on_tap(10, 2)
        assert(H.view.grid.cell(8, 3).icon == "goal")
        H.view.grid.on_tap(8, 3)
        local st = H.saved.xiangqi.state
        assert(#st.history == 1 and st.board[at(8, 3)] == 4 and st.turn == 1)
        H.view.buttons[1][1].callback()
        st = H.saved.xiangqi.state
        assert(st.board[at(10, 2)] == 4 and st.turn == 1 and #st.history == 0)
    end)
end
