--[[--
数织（Picross）。按行列数字提示涂黑格子；随机生成并用逐行逐列推理验证唯一解。
格子：0 空，1 涂黑，2 打叉。棋盘上方/左侧用额外的行列显示提示数字。
--]]
local T = require("kogames.l10n")
local SIZES = { 5, 10, 15 }
local DENSITY = 0.6
local UNDO_CAP = 200

local Core = {}

--- 一条线（1/0 或 1 为涂黑，其余视为空）的连续块长度表，空线为 {}。
function Core.lineClue(line, n)
    local out, run = {}, 0
    for i = 1, n do
        if line[i] == 1 then run = run + 1
        elseif run > 0 then out[#out + 1] = run run = 0 end
    end
    if run > 0 then out[#out + 1] = run end
    return out
end

local function getLine(cells, n, horizontal, k)
    local line = {}
    for i = 1, n do line[i] = horizontal and cells[(k - 1) * n + i] or cells[(i - 1) * n + k] end
    return line
end

--- 返回 rows, cols 两组提示（cells 为 n*n 的一维数组）。
function Core.clues(cells, n)
    local rows, cols = {}, {}
    for k = 1, n do
        rows[k] = Core.lineClue(getLine(cells, n, true, k), n)
        cols[k] = Core.lineClue(getLine(cells, n, false, k), n)
    end
    return rows, cols
end

local function sameClue(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

--- 线求解：line[i] 为 -1 未知/0 空/1 黑；返回新线，矛盾返回 nil。
function Core.solveLine(clue, line, n)
    local can0, can1 = {}, {}
    for i = 1, n do can0[i], can1[i] = false, false end
    local nb = #clue
    -- suffix[b] = 第 b..nb 块至少占用的长度
    local need = {}
    need[nb + 1] = 0
    for b = nb, 1, -1 do need[b] = clue[b] + (b < nb and 1 or 0) + need[b + 1] end
    local starts = {}
    local found = false

    local function record()
        found = true
        local pos = 1
        for b = 1, nb do
            for i = pos, starts[b] - 1 do can0[i] = true end
            for i = starts[b], starts[b] + clue[b] - 1 do can1[i] = true end
            pos = starts[b] + clue[b]
        end
        for i = pos, n do can0[i] = true end
    end

    local function place(b, from)
        if b > nb then
            for i = from, n do if line[i] == 1 then return end end
            record()
            return
        end
        local len = clue[b]
        for s = from, n - need[b] + 1 do
            if s > from and line[s - 1] == 1 then break end
            local ok = true
            for i = s, s + len - 1 do if line[i] == 0 then ok = false break end end
            local e = s + len
            if ok and e <= n and line[e] == 1 then ok = false end
            if ok then
                starts[b] = s
                place(b + 1, e + 1)
            end
        end
    end
    place(1, 1)
    if not found then return nil end
    local out = {}
    for i = 1, n do
        if can1[i] and not can0[i] then out[i] = 1
        elseif can0[i] and not can1[i] then out[i] = 0
        else out[i] = -1 end
    end
    return out
end

--- 仅用行列推理能否完全解出；返回 解出的格子 或 nil。
function Core.lineSolve(rows, cols, n)
    local g = {}
    for i = 1, n * n do g[i] = -1 end
    local changed = true
    while changed do
        changed = false
        for pass = 1, 2 do
            local horizontal = pass == 1
            for k = 1, n do
                local line = getLine(g, n, horizontal, k)
                local out = Core.solveLine((horizontal and rows or cols)[k], line, n)
                if not out then return nil end
                for i = 1, n do
                    if out[i] ~= line[i] then
                        changed = true
                        g[horizontal and (k - 1) * n + i or (i - 1) * n + k] = out[i]
                    end
                end
            end
        end
    end
    for i = 1, n * n do if g[i] == -1 then return nil end end
    return g
end

function Core.randomCells(rng, n)
    local cells, any = {}, false
    for i = 1, n * n do
        cells[i] = rng:float() < DENSITY and 1 or 0
        if cells[i] == 1 then any = true end
    end
    if not any then cells[1] = 1 end
    return cells
end

function Core.fresh(rng, n)
    n = n or 5
    local cells
    for _ = 1, n <= 5 and 200 or 60 do
        cells = Core.randomCells(rng, n)
        local rows, cols = Core.clues(cells, n)
        if Core.lineSolve(rows, cols, n) then break end
    end
    local rows, cols = Core.clues(cells, n)
    local user = {}
    for i = 1, n * n do user[i] = 0 end
    return { n = n, sol = cells, rows = rows, cols = cols, user = user }
end

--- 当前涂黑的格子是否满足全部行列提示。
function Core.solved(s)
    local n = s.n
    for k = 1, n do
        if not sameClue(Core.lineClue(getLine(s.user, n, true, k), n), s.rows[k]) then return false end
        if not sameClue(Core.lineClue(getLine(s.user, n, false, k), n), s.cols[k]) then return false end
    end
    return true
end

local function lineDone(s, horizontal, k)
    local line = getLine(s.user, s.n, horizontal, k)
    return sameClue(Core.lineClue(line, s.n), (horizontal and s.rows or s.cols)[k])
end

local function maxLen(list)
    local m = 1
    for _, c in ipairs(list) do m = math.max(m, #c) end
    return m
end

local M = { id = "nonogram", title = T("数织"), icon = "grid_on", art = "icon_nonogram", tier = "A", desc = T("按数字提示涂出图案"), help = T("每行左侧、每列上方的数字表示该行/列连续涂黑的格数，多个数字之间至少隔一个空格。\n点按格子涂黑；切换到「打叉」模式再点按，或长按格子，可标记确定为空的格子。\n涂出符合所有提示的图案即完成；已满足的提示会变灰。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, started, mode, undo

    local function persist() ctx:save({ state = s, started = started, mode = mode, undo = undo }) end

    local function newGame(n)
        s, started, undo = Core.fresh(ctx.rng, n), ctx.host:now(), {}
        persist()
        self.render()
    end

    local function check()
        if s.done or not Core.solved(s) then return end
        s.done = true
        s.time = math.floor(ctx.host:now() - started)
        if ctx:record("best_" .. s.n, s.time, true) then
            ctx:notify((T("新纪录：%d 分 %d 秒")):format(math.floor(s.time / 60), s.time % 60))
        end
    end

    -- 把 (i) 设为 v；再次设为相同值则清空
    local function setCell(i, v)
        if s.done then return end
        local new = s.user[i] == v and 0 or v
        undo[#undo + 1] = { i, s.user[i] }
        if #undo > UNDO_CAP then table.remove(undo, 1) end
        s.user[i] = new
        check()
        persist()
        self.render()
    end

    function self.render()
        local n = s.n
        local mr, mc = maxLen(s.rows), maxLen(s.cols)
        local status = T("%d×%d", n, n)
        if s.done then
            status = status .. T("    完成！") .. (T("    用时 %d:%02d")):format(math.floor(s.time / 60), s.time % 60)
        end
        local best = ctx:best("best_" .. n)
        if best then status = status .. (T("    最佳 %d:%02d")):format(math.floor(best / 60), best % 60) end
        local size_row = {}
        for _, k in ipairs(SIZES) do
            size_row[#size_row + 1] = { text = k .. "×" .. k, selected = k == n, callback = function() if k ~= n then newGame(k) end end }
        end
        local function toPuzzle(r, c)
            r, c = r - mc, c - mr
            if r < 1 or c < 1 then return nil end
            return (r - 1) * n + c
        end
        ctx:render({
            title = T("数织"),
            status = status,
            grid = {
                rows = n + mc, cols = n + mr,
                cell = function(r, c)
                    local pr, pc = r - mc, c - mr
                    if pr >= 1 and pc >= 1 then
                        local v = s.user[(pr - 1) * n + pc]
                        if v == 1 then return { fill = "black" } end
                        if v == 2 then return { text = "×", color = "grey", scale = 0.6 } end
                        return nil
                    end
                    if pr < 1 and pc < 1 then return nil end
                    local scale = n >= 15 and 0.42 or 0.5
                    if pc >= 1 then
                        local clue = s.cols[pc]
                        local v = clue[r - (mc - #clue)]
                        if #clue == 0 and r == mc then v = 0 end
                        if v then return { text = tostring(v), scale = scale, color = lineDone(s, false, pc) and "grey" or "black" } end
                    else
                        local clue = s.rows[pr]
                        local v = clue[c - (mr - #clue)]
                        if #clue == 0 and c == mr then v = 0 end
                        if v then return { text = tostring(v), scale = scale, color = lineDone(s, true, pr) and "grey" or "black" } end
                    end
                    return nil
                end,
                on_tap = function(r, c)
                    local i = toPuzzle(r, c)
                    if i then setCell(i, mode == "x" and 2 or 1) end
                end,
                on_hold = function(r, c)
                    local i = toPuzzle(r, c)
                    if i then setCell(i, 2) end
                end,
            },
            buttons = {
                size_row,
                {
                    { text = T("填充"), selected = mode ~= "x", callback = function() mode = "fill" persist() self.render() end },
                    { text = "×", selected = mode == "x", callback = function() mode = "x" persist() self.render() end },
                },
                {
                    { text = T("撤销"), enabled = #undo > 0 and not s.done, callback = function()
                        local u = table.remove(undo)
                        s.user[u[1]] = u[2]
                        persist()
                        self.render()
                    end },
                    { text = T("新游戏"), callback = function() newGame(s.n) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.sol then
            s, started, mode, undo = saved.state, saved.started or ctx.host:now(), saved.mode or "fill", saved.undo or {}
        else
            mode = "fill"
            s, started, undo = Core.fresh(ctx.rng, 5), ctx.host:now(), {}
        end
        self.render()
    end

    self.state = function() return s end
    return self
end

return M
