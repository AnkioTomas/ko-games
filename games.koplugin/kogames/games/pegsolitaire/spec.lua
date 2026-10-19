return function(t)
    local test, H = t.test, t.H
    local C = require("kogames.games.pegsolitaire.main").core

    test("pegsolitaire: start position, jump, undo", function()
        local s = C.fresh()
        assert(C.count(s) == 32 and C.hasMove(s))
        assert(not C.jump(s, 1, 2))
        assert(C.jump(s, (2 - 1) * 7 + 4, (4 - 1) * 7 + 4))
        assert(C.count(s) == 31 and s.board[(3 - 1) * 7 + 4] == false)
        assert(C.undo(s) and C.count(s) == 32 and s.board[(4 - 1) * 7 + 4] == false)
    end)

    test("pegsolitaire: session select and jump via taps", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.pegsolitaire.main"), nil)
        H.view.grid.on_tap(2, 4)
        H.view.grid.on_tap(4, 4)
        assert(C.count(g.state()) == 31)
    end)
end
