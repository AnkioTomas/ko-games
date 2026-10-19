return function(t)
    local test, H = t.test, t.H
    local M = require("kogames.games.chess.main")
    local C = M.core

    local function fen(str)
        local pos = { b = {}, ep = nil, half = 0, wk = false, wq = false, bk = false, bq = false }
        local board, turn, cas = str:match("^(%S+) (%S) (%S+)")
        local map = { p = 1, n = 2, b = 3, r = 4, q = 5, k = 6 }
        local i = 1
        for ch in board:gmatch(".") do
            if ch == "/" then
            elseif ch:match("%d") then
                for _ = 1, tonumber(ch) do pos.b[i] = 0 i = i + 1 end
            else
                pos.b[i] = (ch:lower() == ch and -1 or 1) * map[ch:lower()]
                i = i + 1
            end
        end
        pos.turn = turn == "w" and 1 or -1
        pos.wk, pos.wq = cas:find("K") ~= nil, cas:find("Q") ~= nil
        pos.bk, pos.bq = cas:find("k") ~= nil, cas:find("q") ~= nil
        return pos
    end

    local function perft(pos, d)
        if d == 0 then return 1 end
        local n = 0
        for _, m in ipairs(C.legalMoves(pos)) do n = n + perft(C.make(pos, m), d - 1) end
        return n
    end

    test("chess perft matches known counts (castling, ep, promotion)", function()
        assert(perft(C.fresh(), 3) == 8902)
        local kiwi = fen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq")
        assert(perft(kiwi, 2) == 2039)
        local promo = fen("n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b -")
        assert(perft(promo, 2) == 496)
    end)

    test("chess en passant only right after the double push", function()
        local pos = fen("4k3/8/8/8/3p4/8/4P3/4K3 w -")
        pos = C.make(pos, { f = 53, t = 37 }) -- e2-e4
        assert(pos.ep == 45)
        local found
        for _, m in ipairs(C.movesFrom(pos, 36)) do if m.fl == "ep" then found = m end end
        assert(found)
        local np = C.make(pos, found)
        assert(np.b[37] == 0 and np.b[45] == -1)
    end)

    test("chess fool's mate and stalemate", function()
        local pos = C.fresh()
        for _, mv in ipairs({ { 54, 46 }, { 13, 29 }, { 55, 39 }, { 4, 40 } }) do
            local ok
            for _, m in ipairs(C.movesFrom(pos, mv[1])) do if m.t == mv[2] then ok = m end end
            assert(ok)
            pos = C.make(pos, ok)
        end
        local res, why = C.status(pos)
        assert(res == "loss" and why == "mate")
        local res2, why2 = C.status(fen("7k/5Q2/6K1/8/8/8/8/8 b -"))
        assert(res2 == "draw" and why2 == "stalemate")
    end)

    test("chess castling blocked through check", function()
        local pos = fen("4k3/8/8/8/8/8/5r2/R3K2R w KQ")
        local cs = 0
        for _, m in ipairs(C.movesFrom(pos, 61)) do if m.fl == "cs" then cs = cs + 1 end end
        assert(cs == 1) -- 王侧过 f1 被车攻击，只剩后翼
    end)

    test("chess AI finds mate in one and is fast", function()
        local pos = fen("6k1/5ppp/8/8/8/8/8/R5K1 w -")
        local m = C.aiMove(pos, 2)
        assert(m.f == 57 and m.t == 1)
        local t0 = os.clock()
        local am = C.aiMove(C.fresh(), 2)
        assert(am and os.clock() - t0 < 1.5)
    end)

    test("chess session: select, move, AI replies, undo, save", function()
        H.saved, H.view = {}, nil
        require("kogames.registry").launch(H.host, M, nil)
        H.view.grid.on_tap(7, 5) -- e2
        assert(H.view.grid.cell(5, 5).icon == "goal" and H.view.grid.cell(6, 5).icon == "goal")
        H.view.grid.on_tap(5, 5) -- e4
        local st = H.saved.chess.state
        assert(st.pos.b[37] == 1 and st.pos.turn == 1 and #st.history == 1 and st.last)
        H.view.settings.actions[1].callback()
        assert(H.saved.chess.state.pos.b[53] == 1 and #H.saved.chess.state.history == 0)
    end)

    test("chess promotion shows a picker", function()
        H.saved, H.view = {}, nil
        H.saved.chess = { state = { pos = fen("4k3/P7/8/8/8/8/8/4K3 w -"), history = {}, over = false, level = 1 } }
        require("kogames.registry").launch(H.host, M, nil)
        H.view.grid.on_tap(2, 1)
        H.view.grid.on_tap(1, 1)
        assert(H.saved.chess.state.pending)
        H.view.buttons[2][4].callback() -- 马
        local b = H.saved.chess.state.pos.b
        assert(b[1] == 2 and H.saved.chess.state.pending == nil)
    end)

    test("chess threefold repetition is a draw", function()
        local s = C.newState(1)
        s.pos = fen("4k2n/8/8/8/8/8/8/4K2N w -")
        local snap = { pos = s.pos }
        assert(not C.threefold(s))
        s.history = { snap, { pos = fen("4k2n/8/8/8/8/8/8/4K2N w -") } }
        assert(C.threefold(s))
        s.history = { snap }
        assert(not C.threefold(s))
    end)
end
