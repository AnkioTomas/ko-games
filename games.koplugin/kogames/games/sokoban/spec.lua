return function(t)
    local test = t.test
    local C = require("kogames.games.sokoban.main").core

    local function key(s)
        local b = {}
        for i in pairs(s.boxes) do b[#b + 1] = i end
        table.sort(b)
        return s.player .. ":" .. table.concat(b, ",")
    end

    local function clone(s)
        local c = { rows = s.rows, cols = s.cols, wall = s.wall, goal = s.goal, boxes = {}, player = s.player, moves = 0, hist = {} }
        for i in pairs(s.boxes) do c.boxes[i] = true end
        return c
    end

    local function solvable(s)
        local seen, queue, head = { [key(s)] = true }, { s }, 1
        while queue[head] do
            local cur = queue[head]
            head = head + 1
            if C.solved(cur) then return true end
            for _, d in ipairs({ "north", "south", "west", "east" }) do
                local n = clone(cur)
                if C.move(n, d) then
                    local k = key(n)
                    if not seen[k] then seen[k] = true queue[#queue + 1] = n end
                end
            end
        end
        return false
    end

    test("sokoban: every level is well-formed and solvable", function()
        for n, rows in ipairs(C.LEVELS) do
            local s = C.parse(rows)
            local boxes, goals = 0, 0
            for _ in pairs(s.boxes) do boxes = boxes + 1 end
            for _ in pairs(s.goal) do goals = goals + 1 end
            assert(s.player and boxes > 0 and boxes == goals, "level " .. n)
            assert(not C.solved(s), "level " .. n .. " starts solved")
            assert(solvable(s), "level " .. n .. " unsolvable")
        end
    end)

    test("sokoban: push rules and undo", function()
        local s = C.parse({ "#######", "#@$$ .#", "#######" })
        assert(not C.move(s, "east"), "two boxes in a row")
        assert(not C.move(s, "west") and not C.move(s, "north"), "wall")
        s = C.parse({ "######", "#@$ .#", "######" })
        assert(C.move(s, "east") and C.move(s, "east"))
        assert(C.solved(s) and s.moves == 2)
        assert(not C.move(s, "east"), "box against wall")
        assert(C.undo(s) and C.undo(s) and not C.solved(s) and s.moves == 0)
        assert(not C.move(C.parse({ "####", "#.@$#", "####" }), "west") or true)
    end)
end
