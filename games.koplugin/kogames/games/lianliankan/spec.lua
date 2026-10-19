return function(t)
    local test, H, Rng = t.test, t.H, t.Rng
    local C = require("kogames.games.lianliankan.main").core

    local function board(rows, cols, cells)
        return { rows = rows, cols = cols, kinds = 2, cells = cells, left = #cells, shuffles = 0 }
    end

    test("lianliankan: connect rules (turns, blockers, outside edge)", function()
        local s = board(3, 3, { 1, 0, 1, 0, 0, 0, 0, 0, 0 })
        assert(C.connect(s, 1, 3))
        s = board(3, 3, { 1, 2, 1, 0, 0, 0, 0, 0, 0 })
        assert(C.connect(s, 1, 3)) -- 绕棋盘外侧
        s = board(3, 3, { 1, 2, 2, 2, 2, 2, 1, 2, 2 })
        assert(C.connect(s, 1, 7)) -- 走外圈：两个拐弯
        s = board(3, 3, { 1, 0, 2, 0, 3, 0, 2, 0, 1 })
        assert(not C.connect(s, 1, 9)) -- 需要三个拐弯
        s = board(1, 4, { 1, 2, 2, 1 })
        assert(C.connect(s, 1, 4)) -- 单行：绕上方
        s = board(4, 1, { 1, 2, 2, 1 })
        assert(C.remove(s, 1, 4) and s.left == 2)
    end)

    test("lianliankan: fresh pairs, shuffle keeps tiles, always solvable path exists", function()
        local s = C.fresh(Rng.new(4), 8, 6, 12)
        local cnt = {}
        for _, v in ipairs(s.cells) do cnt[v] = (cnt[v] or 0) + 1 end
        for _, n in pairs(cnt) do assert(n % 2 == 0) end
        assert(C.findPair(s))
        local before = {}
        for _, v in ipairs(s.cells) do before[#before + 1] = v end
        table.sort(before)
        C.shuffle(s, Rng.new(9))
        local after = {}
        for _, v in ipairs(s.cells) do after[#after + 1] = v end
        table.sort(after)
        assert(table.concat(before, ",") == table.concat(after, ","))
    end)

    test("lianliankan: clearing everything wins and records time", function()
        H.saved, H.view = {}, nil
        local g = require("kogames.registry").launch(H.host, require("kogames.games.lianliankan.main"), nil)
        local s = g.state()
        local safety = 0
        while not s.done and safety < 200 do
            safety = safety + 1
            local a, b = C.findPair(s)
            assert(a, "stuck")
            local function rc(i) return math.floor((i - 1) / s.cols) + 1, (i - 1) % s.cols + 1 end
            g.tap(rc(a)) g.tap(rc(b))
        end
        assert(s.done and s.left == 0 and H.saved["stats_lianliankan"].best8x6)
    end)
end
