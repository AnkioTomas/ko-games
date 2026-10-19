return function(t)
    local test, Rng = t.test, t.Rng
    local M = require("kogames.games.sudoku.main")
    local C = M.core

    local function valid(g)
        for i = 1, 81 do
            if g[i] < 1 or g[i] > 9 or C.conflict(g, i) then return false end
        end
        return true
    end

    test("sudoku: generated puzzles have a unique solution and valid givens", function()
        for _, lv in ipairs(M.LEVELS) do
            for seed = 1, 2 do
                local s = C.fresh(lv, Rng.new(seed))
                assert(valid(s.solution), "solution invalid")
                local clues = 0
                for i = 1, 81 do
                    if s.puzzle[i] ~= 0 then
                        clues = clues + 1
                        assert(s.puzzle[i] == s.solution[i])
                    end
                end
                assert(C.countSolutions(s.puzzle, 2) == 1, "not unique")
                assert(clues >= lv.clues and clues <= lv.clues + 6, lv.name .. " clues " .. clues)
                assert(not C.solved(s))
                s.user = s.solution
                assert(C.solved(s))
            end
        end
    end)

    test("sudoku: conflicts and incomplete boards are not solved", function()
        local s = C.fresh(M.LEVELS[1], Rng.new(5))
        local u = {}
        for i = 1, 81 do u[i] = s.solution[i] end
        u[1], u[2] = 5, 5
        assert(C.conflict(u, 1) and C.conflict(u, 2))
        s.user = u
        assert(not C.solved(s))
        u[1] = 0
        assert(not C.solved(s))
    end)
end
