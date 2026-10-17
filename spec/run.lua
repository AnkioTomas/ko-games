-- 无 KOReader 的离线测试：luajit spec/run.lua（在仓库根目录运行）
package.path = "games.koplugin/?.lua;" .. package.path

local H = { saved = {}, view = nil, shows = 0, settings = {}, notes = {} }
H.host = {
    showScreen = function(_, v) H.view = v H.shows = H.shows + 1 end,
    closeScreen = function() H.view = nil end,
    schedule = function() return {} end, unschedule = function() end,
    load = function(_, id) return H.saved[id] end,
    save = function(_, id, t) H.saved[id] = t end,
    getSetting = function(_, k, d) if H.settings[k] == nil then return d end return H.settings[k] end,
    setSetting = function(_, k, v) H.settings[k] = v end,
    notify = function(_, t) H.notes[#H.notes + 1] = t end,
    now = function() return 1000 end,
}
require("kogames.host.interface").check(H.host)

local Registry = require("kogames.registry")
local Rng = require("kogames.rng")

local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then print("FAIL " .. name .. ": " .. tostring(err)) os.exit(1) end
    passed = passed + 1
    print("ok   " .. name)
end

local function launch(id)
    H.saved, H.view = {}, nil
    return Registry.launch(H.host, Registry.get(id), nil)
end

test("registry loads every listed game", function()
    assert(#Registry.all() == #Registry.LIST, "a game failed to load")
end)

test("rng is reproducible and in range", function()
    local a, b = Rng.new(7), Rng.new(7)
    for _ = 1, 50 do
        local x = a:int(10)
        assert(x == b:int(10) and x >= 1 and x <= 10)
    end
end)

test("2048 slide/merge", function()
    local C = require("kogames.games.g2048").core
    local s = { board = { 2, 2, 2, 2, 0, 0, 0, 0, 2, 0, 2, 4, 0, 0, 0, 0 }, score = 0 }
    assert(C.move(s, "west"))
    assert(s.board[1] == 4 and s.board[2] == 4 and s.board[3] == 0)
    assert(s.board[9] == 4 and s.board[10] == 4 and s.board[11] == 0)
    assert(s.score == 12)
    local stuck = { board = { 2, 4, 2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, score = 0 }
    assert(not C.move(stuck, "west"))
    local full = { board = { 2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2 }, score = 0 }
    assert(not C.canMove(full))
end)

test("2048 session saves, swipes, ends", function()
    local g = launch("2048")
    local before = H.view.grid.cell
    assert(H.view.on_swipe and H.view.title == "2048")
    for _, d in ipairs({ "west", "north", "east", "south" }) do H.view.on_swipe(d) end
    assert(H.saved["2048"] and H.saved["2048"].state)
    assert(before)
    g.stop = nil
end)

test("minesweeper first tap is safe and flood fills", function()
    local M = require("kogames.games.minesweeper")
    local C = M.core
    for seed = 1, 20 do
        local s = C.fresh(M.LEVELS[1])
        C.open(s, 5, 5, Rng.new(seed))
        assert(not s.over and s.revealed >= 1)
        assert(not s.cells[(5 - 1) * 9 + 5].mine)
    end
    local s = C.fresh(M.LEVELS[1])
    C.open(s, 1, 1, Rng.new(3))
    C.flag(s, 9, 9)
    assert(s.flags == 1 or s.cells[81].open)
end)

test("minesweeper can be won by opening all safe cells", function()
    local M = require("kogames.games.minesweeper")
    local C = M.core
    local s = C.fresh(M.LEVELS[1])
    local rng = Rng.new(11)
    C.open(s, 5, 5, rng)
    for r = 1, 9 do for c = 1, 9 do
        if not s.cells[(r - 1) * 9 + c].mine then C.open(s, r, c, rng) end
    end end
    assert(s.won and s.over)
end)

test("minesweeper session", function()
    local g = launch("minesweeper")
    H.view.grid.on_tap(5, 5)
    assert(H.saved.minesweeper.state.placed)
    H.view.grid.on_hold(1, 1)
    assert(H.view.grid.cell(1, 1) ~= nil)
    g.stop = nil
end)

test("sudoku generates unique-solution puzzles", function()
    local C = require("kogames.games.sudoku").core
    for seed = 1, 3 do
        local puzzle, sol = C.generate(36, Rng.new(seed))
        assert(C.countSolutions(puzzle, 2) == 1, "not unique")
        local clues = 0
        for i = 1, 81 do if puzzle[i] ~= 0 then clues = clues + 1 assert(puzzle[i] == sol[i]) end end
        assert(clues >= 36 and clues < 81)
        local s = { user = sol }
        assert(C.solved(s))
        for i = 1, 81 do assert(not C.conflict(sol, i)) end
    end
end)

test("sudoku session: input, conflict, hint, win", function()
    local g = launch("sudoku")
    local s = g.state()
    local idx
    for i = 1, 81 do if s.puzzle[i] == 0 then idx = i break end end
    H.view.grid.on_tap(math.ceil(idx / 9), (idx - 1) % 9 + 1)
    g.put(s.solution[idx] % 9 + 1)
    assert(g.state().user[idx] ~= s.solution[idx])
    g.hint()
    assert(g.state().user[idx] == s.solution[idx])
    for i = 1, 81 do
        if s.puzzle[i] == 0 then
            H.view.grid.on_tap(math.ceil(i / 9), (i - 1) % 9 + 1)
            g.hint()
        end
    end
    assert(g.state().done)
    assert(H.saved.stats_sudoku)
end)

test("gomoku win detection, ai blocks, undo", function()
    local C = require("kogames.games.gomoku").core
    local s = C.fresh()
    for c = 1, 5 do C.place(s, 8, c, 1) end
    assert(s.winner == 1)
    C.undo(s)
    assert(s.winner == nil and #s.moves == 4)
    local t = C.fresh()
    for c = 1, 4 do C.place(t, 8, c + 2, 1) end -- 黑四连，两头敞开
    table.insert(t.moves, 0) -- 凑成该 AI 走
    local r, c = C.aiMove(t, Rng.new(1))
    assert(r == 8 and (c == 2 or c == 7), "ai should block, got " .. r .. "," .. c)
end)

test("gomoku session: tap triggers ai reply", function()
    local g = launch("gomoku")
    H.view.grid.on_tap(8, 8)
    assert(#g.state().moves == 2)
    assert(H.view.buttons[1][1].enabled)
end)

test("sokoban levels all solvable (BFS)", function()
    local C = require("kogames.games.sokoban").core
    local dirs = { "north", "south", "west", "east" }
    for n, rows in ipairs(C.LEVELS) do
        local s = C.parse(rows)
        local function key(st)
            local b = {}
            for idx in pairs(st.boxes) do b[#b + 1] = idx end
            table.sort(b)
            return st.player .. ":" .. table.concat(b, ",")
        end
        local seen, queue, qi, found = { [key(s)] = true }, { s }, 1, false
        while qi <= #queue and not found and #queue < 400000 do
            local cur = queue[qi]
            qi = qi + 1
            for _, d in ipairs(dirs) do
                -- 复制状态
                local nx = { rows = cur.rows, cols = cur.cols, wall = cur.wall, goal = cur.goal,
                    player = cur.player, moves = 0, hist = {}, boxes = {} }
                for idx in pairs(cur.boxes) do nx.boxes[idx] = true end
                if C.move(nx, d) then
                    local k = key(nx)
                    if not seen[k] then
                        seen[k] = true
                        if C.solved(nx) then found = true break end
                        queue[#queue + 1] = nx
                    end
                end
            end
        end
        assert(found, "level " .. n .. " unsolvable")
    end
end)

test("sokoban move/undo and session", function()
    local g = launch("sokoban")
    local s = g.state()
    local p = s.player
    g.step("east")
    assert(g.state().moves == 1 and g.state().player ~= p)
    H.view.buttons[2][1].callback() -- 撤销
    assert(g.state().player == p and g.state().moves == 0)
end)

test("lobby lists games and launches one", function()
    H.saved, H.view = {}, nil
    local Lobby = require("kogames.lobby").new(H.host):show()
    local n, first = 0, nil
    for _, it in ipairs(H.view.cards.items) do
        if it.callback then n = n + 1 first = first or it end
    end
    assert(n >= #Registry.LIST)
    first.callback()
    assert(H.view.title ~= "游戏")
    H.view.back() -- 标题栏返回 → 大厅
    assert(H.view.title == "游戏")
    assert(Lobby)
end)

test("l10n: every source string has en and zh_TW translations", function()
    local files = { "lobby", "registry", "launcher" }
    for _, g in ipairs(Registry.LIST) do files[#files + 1] = "games/" .. g end
    local keys = { ["初级"] = true, ["中级"] = true, ["高级"] = true, ["简单"] = true, ["普通"] = true, ["困难"] = true }
    local function scan(path)
        local f = assert(io.open(path))
        for line in f:lines() do
            if not line:match("^%s*%-%-") then
                for k in line:gmatch('[T_]%("([^"]*[\228-\233][^"]*)"') do keys[k] = true end
            end
        end
        f:close()
    end
    for _, n in ipairs(files) do scan("games.koplugin/kogames/" .. n .. ".lua") end
    for _, n in ipairs({ "main", "_meta", "moon_source" }) do scan("games.koplugin/" .. n .. ".lua") end
    local en, tw = require("kogames.l10n.en"), require("kogames.l10n.zh_TW")
    for k in pairs(keys) do
        assert(en[k], "missing en: " .. k)
        assert(tw[k], "missing zh_TW: " .. k)
    end
end)

test("l10n: language selection and formatting", function()
    local L = require("kogames.l10n")
    assert(L.candidates("zh_CN")[1] == nil)
    assert(L.candidates("zh_TW")[1] == "zh_TW" and L.candidates("zh_HK")[1] == "zh_TW")
    assert(L.candidates("C")[1] == "en" and L.candidates("en_US")[1] == "en")
    local c = L.candidates("de_DE")
    assert(c[1] == "de_DE" and c[2] == "de" and c[3] == "en")
    L.load("en_US")
    assert(L("返回") == "Back")
    assert(L("得分 %d    最高 %d", 3, 9) == "Score 3    Best 9")
    L.load("zh_TW")
    assert(L("撤销") == "復原")
    L.load("zh_CN")
    assert(L("撤销") == "撤销" and L("新纪录：%d", 5) == "新纪录：5")
end)

print(("%d tests passed"):format(passed))
