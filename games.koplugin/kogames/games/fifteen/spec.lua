return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local function launch()
        H.saved, H.view = {}, nil
        return require("kogames.registry").launch(H.host, require("kogames.games.fifteen.main"), nil)
    end

    local function inversions(b)
        local inv, list = 0, {}
        for _, v in ipairs(b) do if v ~= 0 then list[#list + 1] = v end end
        for i = 1, #list do for j = i + 1, #list do if list[i] > list[j] then inv = inv + 1 end end end
        return inv
    end

    test("fifteen: fresh boards are solvable and shuffled", function()
        local C = require("kogames.games.fifteen.main").core
        for _, n in ipairs({ 3, 4, 5 }) do
            for seed = 1, 10 do
                local s = C.fresh(Rng.new(seed), n)
                assert(not C.solved(s) and s.moves == 0)
                local br = C.blank(s)
                local ok
                if n % 2 == 1 then ok = inversions(s.board) % 2 == 0
                else ok = (inversions(s.board) + (n - br)) % 2 == 0 end
                assert(ok, "unsolvable " .. n)
            end
        end
    end)

    test("fifteen: slide moves a run toward the blank", function()
        local C = require("kogames.games.fifteen.main").core
        local s = { n = 3, moves = 0, board = { 1, 2, 3, 4, 5, 6, 7, 8, 0 } }
        assert(C.slide(s, 3, 1))
        assert(table.concat(s.board, ",") == "1,2,3,4,5,6,0,7,8")
        assert(C.slide(s, 1, 1))
        assert(table.concat(s.board, ",") == "0,2,3,1,5,6,4,7,8")
        assert(not C.slide(s, 2, 2) and s.moves == 2)
        assert(C.swipe(s, "west"))
        assert(table.concat(s.board, ",") == "2,0,3,1,5,6,4,7,8")
    end)

    test("fifteen: win, record and undo via session", function()
        local g = launch()
        local C = require("kogames.games.fifteen.main").core
        local s = g.state()
        s.n, s.board, s.moves, s.done = 3, { 1, 2, 3, 4, 5, 6, 7, 0, 8 }, 0, nil
        g.render()
        assert(H.view.buttons[2][1].enabled == false)
        H.view.grid.on_tap(3, 3)
        assert(s.done and C.solved(s) and s.moves == 1)
        assert(H.saved["stats_fifteen"] and H.saved["stats_fifteen"].best3 == 1)
        assert(H.view.status:find("1"))
    end)
end
