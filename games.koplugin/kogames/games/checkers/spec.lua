return function(t)
    local test, H = t.test, t.H
    local M = require("kogames.games.checkers.main")
    local C = M.core

    local function empty()
        local s = C.fresh()
        for i = 1, 64 do s.board[i] = 0 end
        return s
    end
    local function at(r, c) return (r - 1) * 8 + c end

    test("checkers opening has 7 moves and no captures", function()
        local s = C.fresh()
        local mv, forced = C.moves(s.board, 1)
        assert(#mv == 7 and not forced)
    end)

    test("checkers perft matches English draughts (7, 49, 302, 1469)", function()
        local function perft(b, who, d)
            if d == 0 then return 1 end
            local n = 0
            for _, m in ipairs(C.moves(b, who)) do
                n = n + perft(C.apply(b, m), who == 1 and 2 or 1, d - 1)
            end
            return n
        end
        local b = C.fresh().board
        assert(perft(b, 1, 1) == 7 and perft(b, 1, 2) == 49 and perft(b, 1, 3) == 302 and perft(b, 1, 4) == 1469)
    end)

    test("checkers captured pieces still block until the move ends", function()
        local s = empty()
        -- king loops around a 2x2 block of white men: may not jump the same piece twice
        s.board[at(8, 1)] = 2
        s.board[at(7, 2)] = 3
        s.board[at(5, 4)] = 3
        s.board[at(5, 2)] = 3
        s.board[at(7, 4)] = 3
        local mv = C.moves(s.board, 1)
        for _, m in ipairs(mv) do
            local seen = {}
            for _, k in ipairs(m.caps) do assert(not seen[k]); seen[k] = true end
        end
    end)

    test("checkers capture is mandatory and multi-jumps", function()
        local s = empty()
        s.board[at(8, 1)] = 1
        s.board[at(7, 2)] = 3
        s.board[at(5, 4)] = 3
        s.board[at(8, 7)] = 1 -- spare piece with a plain move
        local mv, forced = C.moves(s.board, 1)
        assert(forced and #mv == 1)
        assert(mv[1].from == at(8, 1) and mv[1].to == at(4, 5) and #mv[1].caps == 2)
        local nb = C.apply(s.board, mv[1])
        assert(nb[at(7, 2)] == 0 and nb[at(5, 4)] == 0 and nb[at(4, 5)] == 1)
    end)

    test("checkers promotion ends the jump; kings move backward", function()
        local s = empty()
        s.board[at(3, 2)] = 1
        s.board[at(2, 3)] = 3
        s.board[at(2, 5)] = 3
        local mv = C.moves(s.board, 1)
        assert(#mv == 1 and mv[1].to == at(1, 4) and #mv[1].caps == 1)
        local nb, crowned = C.apply(s.board, mv[1])
        assert(crowned and nb[at(1, 4)] == 2)
        local k = empty()
        k.board[at(4, 5)] = 2
        assert(#C.moves(k.board, 1) == 4)
    end)

    test("checkers side without moves loses", function()
        local s = empty()
        s.board[at(3, 2)] = 1
        s.board[at(2, 3)] = 3
        C.play(s, C.find(C.moves(s.board, 1), at(3, 2), at(1, 4)))
        assert(s.over and s.result == 1)
    end)

    test("checkers AI answers within a time budget", function()
        local s = C.fresh()
        C.play(s, C.moves(s.board, 1)[1])
        local t0 = os.clock()
        local m = C.aiMove(s)
        assert(m and os.clock() - t0 < 1.2)
        assert(C.find(C.moves(s.board, 2), m.from, m.to))
    end)

    test("checkers session: select, move, undo", function()
        H.saved, H.view = {}, nil
        require("kogames.registry").launch(H.host, M, nil)
        H.view.grid.on_tap(6, 1)
        assert(H.view.grid.cell(5, 2).icon == "goal")
        H.view.grid.on_tap(5, 2)
        local st = H.saved.checkers.state
        assert(#st.history == 1 and st.board[at(6, 1)] == 0)
        H.view.buttons[1][1].callback()
        local st2 = H.saved.checkers.state
        assert(st2.board[at(6, 1)] == 1 and #st2.history == 0)
    end)
end
