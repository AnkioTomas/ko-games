return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view, H.settings = {}, nil, {}
        return require("kogames.registry").launch(H.host, require("kogames.games.twentyfour"), nil)
    end

    test("twentyfour: rationals and solver", function()
        local C = require("kogames.games.twentyfour").core
        assert(C.fmt(C.apply("÷", C.rat(1), C.rat(3))) == "1/3")
        assert(C.apply("÷", C.rat(1), C.rat(0)) == nil)
        assert(C.solve({ 3, 3, 8, 8 }), "3 3 8 8 needs fractions")
        assert(C.solve({ 1, 1, 1, 1 }) == nil)
        assert(C.solve({ 5, 5, 5, 1 }))
        for seed = 1, 10 do assert(C.solve(C.deal(Rng.new(seed)))) end
    end)

    test("twentyfour: tap flow solves a hand", function()
        local g = launch()
        local s = g.state()
        s.nums = { 6, 4, 1, 1 }
        s.items = require("kogames.games.twentyfour").core.startItems(s.nums)
        H.view.grid.on_tap(1, 1)
        H.view.buttons[1][3].callback() -- ×
        H.view.grid.on_tap(1, 2)
        assert(#s.items == 3 and s.items[1].n == 24)
        H.view.grid.on_tap(1, 1)
        H.view.buttons[1][3].callback()
        H.view.grid.on_tap(1, 2)
        H.view.grid.on_tap(1, 1)
        H.view.buttons[1][3].callback()
        H.view.grid.on_tap(1, 2)
        assert(s.done and H.saved.stats_twentyfour.solved == 1)
        assert(H.view.status:find("完成"))
    end)

    test("twentyfour: hint, restart, skip", function()
        local g = launch()
        local s = g.state()
        H.view.buttons[2][3].callback()
        assert(s.hint and H.view.status:find("提示"))
        H.view.buttons[2][2].callback()
        assert(#s.items == 4 and not s.hint)
        H.view.buttons[2][4].callback()
        assert(#g.state().items == 4)
    end)
end
