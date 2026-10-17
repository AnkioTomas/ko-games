--[[--
数独。9×9，唯一解；先点格子再点数字；冲突的格子反白，提示会填入选中格的答案。
--]]
local T = require("kogames.l10n")
local LEVELS = {
    { name = "简单", clues = 40 },
    { name = "普通", clues = 32 },
    { name = "困难", clues = 26 },
}

local Core = {}

-- 返回 idx 所在行/列/宫已用数字的集合 used[v]=true
local function usedAt(g, idx)
    local r, c = math.floor((idx - 1) / 9), (idx - 1) % 9
    local used = {}
    for i = 0, 8 do
        used[g[r * 9 + i + 1]] = true
        used[g[i * 9 + c + 1]] = true
    end
    local br, bc = r - r % 3, c - c % 3
    for dr = 0, 2 do for dc = 0, 2 do used[g[(br + dr) * 9 + bc + dc + 1]] = true end end
    return used
end

-- 回溯数解，最多数到 limit 个；g 里 0 为空，结束后恢复原样
local function count(g, limit)
    local found = 0
    local function go()
        local best, best_used, best_n = nil, nil, 10
        for idx = 1, 81 do
            if g[idx] == 0 then
                local used = usedAt(g, idx)
                local n = 0
                for v = 1, 9 do if not used[v] then n = n + 1 end end
                if n < best_n then best, best_used, best_n = idx, used, n end
                if n <= 1 then break end
            end
        end
        if not best then found = found + 1 return end
        if best_n == 0 then return end
        for v = 1, 9 do
            if not best_used[v] then
                g[best] = v
                go()
                if found >= limit then g[best] = 0 return end
            end
        end
        g[best] = 0
    end
    go()
    return found
end

function Core.countSolutions(puzzle, limit)
    local g = {}
    for i = 1, 81 do g[i] = puzzle[i] end
    return count(g, limit or 2)
end

function Core.generate(clues, rng)
    local sol = {}
    for i = 1, 81 do sol[i] = 0 end
    -- 随机终盘：求一个解并保留
    local function fill(idx)
        if idx > 81 then return true end
        local used = usedAt(sol, idx)
        local vals = {}
        for v = 1, 9 do if not used[v] then vals[#vals + 1] = v end end
        rng:shuffle(vals)
        for _, v in ipairs(vals) do
            sol[idx] = v
            if fill(idx + 1) then return true end
        end
        sol[idx] = 0
        return false
    end
    fill(1)
    local puzzle = {}
    for i = 1, 81 do puzzle[i] = sol[i] end
    local order = {}
    for i = 1, 81 do order[i] = i end
    rng:shuffle(order)
    local left = 81
    for _, idx in ipairs(order) do
        if left <= clues then break end
        local keep = puzzle[idx]
        puzzle[idx] = 0
        if Core.countSolutions(puzzle, 2) ~= 1 then puzzle[idx] = keep else left = left - 1 end
    end
    return puzzle, sol
end

function Core.fresh(level, rng)
    local puzzle, sol = Core.generate(level.clues, rng)
    local user = {}
    for i = 1, 81 do user[i] = puzzle[i] end
    return { level = level.name, puzzle = puzzle, solution = sol, user = user, sel = nil, hints = 0 }
end

--- 与同行/列/宫里其它格冲突
function Core.conflict(user, idx)
    local v = user[idx]
    if v == 0 then return false end
    local r, c = math.floor((idx - 1) / 9), (idx - 1) % 9
    for i = 0, 8 do
        local a, b = r * 9 + i + 1, i * 9 + c + 1
        if a ~= idx and user[a] == v then return true end
        if b ~= idx and user[b] == v then return true end
    end
    local br, bc = r - r % 3, c - c % 3
    for dr = 0, 2 do for dc = 0, 2 do
        local o = (br + dr) * 9 + bc + dc + 1
        if o ~= idx and user[o] == v then return true end
    end end
    return false
end

function Core.solved(s)
    for i = 1, 81 do
        if s.user[i] == 0 or Core.conflict(s.user, i) then return false end
    end
    return true
end

local M = { id = "sudoku", title = T("数独"), icon = "apps", tier = "A", desc = T("唯一解数独"), help = T("在 9×9 的格子里填入 1–9，使每一行、每一列和每个 3×3 宫内数字都不重复。\n先点选一个空格，再点下方数字填入；灰色数字是你填的，黑色是题目给定。填错冲突的格子会反色显示。\n卡住了可以点「提示」，会填入一个正确数字。"), core = Core, LEVELS = LEVELS }

function M.new(ctx)
    local self = {}
    local s, started

    local function persist() ctx:save({ state = s, started = started }) end

    local function newGame(level)
        s, started = Core.fresh(level, ctx.rng), ctx.host:now()
        persist()
        self.render()
    end

    local function check()
        if s.done then return end
        if Core.solved(s) then
            s.done = true
            local t = math.floor(ctx.host:now() - started)
            if ctx:record("best_" .. s.level, t, true) then ctx:notify((T("新纪录：%d 分 %d 秒")):format(math.floor(t / 60), t % 60)) end
        end
    end

    local function put(v)
        if not s.sel or s.done or s.puzzle[s.sel] ~= 0 then return end
        s.user[s.sel] = v
        check()
        persist()
        self.render()
    end

    local function hint()
        if not s.sel or s.done or s.puzzle[s.sel] ~= 0 then return end
        s.user[s.sel] = s.solution[s.sel]
        s.hints = s.hints + 1
        check()
        persist()
        self.render()
    end

    function self.render()
        local status = T("%s    提示 %d 次", T(s.level), s.hints)
        if s.done then status = status .. T("    完成！") end
        local best = ctx:best("best_" .. s.level)
        if best then status = status .. (T("    最佳 %d:%02d")):format(math.floor(best / 60), best % 60) end
        local nums1, nums2 = {}, {}
        for v = 1, 5 do nums1[#nums1 + 1] = { text = tostring(v), callback = function() put(v) end } end
        for v = 6, 9 do nums2[#nums2 + 1] = { text = tostring(v), callback = function() put(v) end } end
        nums2[#nums2 + 1] = { text = T("清除"), callback = function() put(0) end }
        local lv = {}
        for _, l in ipairs(LEVELS) do
            lv[#lv + 1] = { text = T(l.name), selected = l.name == s.level, callback = function() newGame(l) end }
        end
        ctx:render({
            title = T("数独"),
            status = status,
            grid = {
                rows = 9, cols = 9, thick = 3,
                on_tap = function(r, c) s.sel = (r - 1) * 9 + c self.render() end,
                cell = function(r, c)
                    local idx = (r - 1) * 9 + c
                    local v = s.user[idx]
                    local cell = { text = v ~= 0 and tostring(v) or "", scale = 0.55 }
                    if s.puzzle[idx] == 0 then cell.color = "grey" end
                    if Core.conflict(s.user, idx) then cell.fill, cell.color = "dark", "white"
                    elseif idx == s.sel then cell.fill = "grey" end
                    return cell
                end,
            },
            buttons = {
                nums1, nums2,
                lv,
                {
                    { text = T("提示"), callback = hint },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state then s, started = saved.state, saved.started else return newGame(LEVELS[1]) end
        self.render()
    end

    self.put, self.hint, self.state = put, hint, function() return s end
    return self
end

return M
