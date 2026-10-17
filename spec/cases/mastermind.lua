return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view, H.settings = {}, nil, {}
        return require("kogames.registry").launch(H.host, require("kogames.games.mastermind"), nil)
    end

    test("mastermind: scoring and secret", function()
        local C = require("kogames.games.mastermind").core
        local a, b = C.score("1234", "1243")
        assert(a == 2 and b == 2)
        a, b = C.score("1234", "5678")
        assert(a == 0 and b == 0)
        assert(C.validGuess("1234") and not C.validGuess("1123") and not C.validGuess("123"))
        for seed = 1, 20 do assert(C.validGuess(C.secret(Rng.new(seed)))) end
    end)

    test("mastermind: win flow records best", function()
        local g = launch()
        local s = g.state()
        s.secret = "1234"
        g.press("5") g.press("6") g.press("7") g.press("8")
        g.submit()
        assert(#s.guesses == 1 and s.guesses[1].a == 0 and not s.done)
        assert(H.view.grid.cell(1, 2).text == "0A0B")
        g.press("1") g.press("1")
        assert(#s.input == 1)
        for _, d in ipairs({ "2", "3", "4" }) do g.press(d) end
        g.delete() g.press("4")
        g.submit()
        assert(s.won and s.done and H.saved.stats_mastermind.best_tries == 2)
    end)

    test("mastermind: loses after 10 tries, give up reveals", function()
        local g = launch()
        local s = g.state()
        s.secret = "1234"
        for _ = 1, 10 do
            for _, d in ipairs({ "5", "6", "7", "8" }) do g.press(d) end
            g.submit()
        end
        assert(s.done and not s.won and H.view.status:find("1234"))
        g = launch()
        H.view.buttons[4][1].callback() -- 提示
        assert(g.state().hinted)
        H.view.buttons[4][2].callback() -- 认输
        assert(g.state().done)
    end)
end
