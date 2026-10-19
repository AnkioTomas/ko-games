return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.tictactoe.main").core

    test("tictactoe: winner detection and ai takes win / blocks", function()
        local s = C.fresh(3, 3)
        s.board = { 1, 1, nil, 2, 2, nil, nil, nil, nil }
        s.moves, s.turn = 4, 2
        assert(C.aiMove(s, Rng.new(1)) == 6)
        s.turn = 1
        s.board = { 2, 2, nil, 1, nil, nil, nil, nil, nil }
        s.moves = 3
        s.turn = 1
        s.turn = 2
        s.board = { 1, 1, nil, nil, 2, nil, nil, nil, nil }
        s.moves, s.turn = 3, 2
        assert(C.aiMove(s, Rng.new(1)) == 3)
        s.board = { 1, 1, 1 }
        assert(C.winner(s) == 1)
    end)

    test("tictactoe: 3x3 ai never loses against random play", function()
        for seed = 1, 30 do
            local rng = Rng.new(seed)
            local s = C.fresh(3, 3)
            while not C.winner(s) do
                if s.turn == 1 then
                    local free = {}
                    for i = 1, 9 do if not s.board[i] then free[#free + 1] = i end end
                    C.play(s, free[rng:int(#free)])
                else
                    C.play(s, C.aiMove(s, rng))
                end
            end
            assert(C.winner(s) ~= 1)
        end
    end)

    test("tictactoe: session tap answers and 5x5 ai moves", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.tictactoe.main"), nil)
        H.view.grid.on_tap(2, 2)
        local s = g.state()
        assert(s.moves == 2 and s.board[5] == 1)
        local b = C.fresh(5, 4)
        C.play(b, 13)
        assert(C.aiMove(b, Rng.new(2)))
    end)
end
