--[[--
汉诺塔。三根柱子，N 个圆盘：点一根柱子选中（高亮），再点另一根把顶上的盘子移过去。
圆盘用重复的 “█” 表示，长度即盘子大小；每层一格，棋盘共 N+1 层（顶层用于显示选中状态）。
--]]
local T = require("kogames.l10n")
local SIZES = { 3, 4, 5, 6, 7 }
local UNDO_CAP = 300

local Core = {}

function Core.fresh(n)
    local p = {}
    for i = n, 1, -1 do p[#p + 1] = i end
    return { n = n, pegs = { p, {}, {} }, moves = 0 }
end

function Core.solved(s) return #s.pegs[3] == s.n end

function Core.optimal(n) return 2 ^ n - 1 end

function Core.canMove(s, from, to)
    if from == to then return false end
    local a, b = s.pegs[from], s.pegs[to]
    if #a == 0 then return false end
    return #b == 0 or a[#a] < b[#b]
end

function Core.move(s, from, to)
    if not Core.canMove(s, from, to) then return false end
    local a = s.pegs[from]
    local d = table.remove(a)
    table.insert(s.pegs[to], d)
    s.moves = s.moves + 1
    return true
end

--- 从当前（任意合法）状态出发，把所有盘子移到 target 的最优第一步：返回 from, to。
function Core.hint(s, target)
    target = target or 3
    local where = {}
    for p = 1, 3 do for _, d in ipairs(s.pegs[p]) do where[d] = p end end
    local function solve(k, tgt)
        if k == 0 then return nil end
        if where[k] == tgt then return solve(k - 1, tgt) end
        local other = 6 - where[k] - tgt
        local f, t = solve(k - 1, other)
        if f then return f, t end
        return where[k], tgt
    end
    return solve(s.n, target)
end

local M = { id = "hanoi", title = T("汉诺塔"), icon = "apps", tier = "A", desc = T("把圆盘搬到右边柱子"), help = T("目标：把左边柱子上的全部圆盘搬到右边柱子。\n每次只能移动一个盘子，大盘不能压在小盘上。\n点一根柱子选中，再点另一根柱子，顶上的盘子就会移过去。\n可选 3 到 7 个盘子，最少步数为 2 的盘数次方减 1；提示会给出最优的下一步。"), core = Core }

local unpack = unpack or table.unpack

local function copyState(s)
    local p = {}
    for i = 1, 3 do p[i] = { unpack(s.pegs[i]) } end
    return p
end

function M.new(ctx)
    local self = {}
    local s, undo, sel

    local function key() return "best" .. s.n end
    local function persist() ctx:save({ state = s, undo = undo }) end

    local function fresh(n)
        s, undo, sel = Core.fresh(n), {}, nil
        persist()
        self.render()
    end

    local function doMove(from, to)
        local before = copyState(s)
        if not Core.move(s, from, to) then return false end
        undo[#undo + 1] = before
        if #undo > UNDO_CAP then table.remove(undo, 1) end
        if Core.solved(s) then
            s.done = true
            if ctx:record(key(), s.moves, true) then ctx:notify(T("新纪录：%d", s.moves)) end
        end
        return true
    end

    local function tapCell(_, c)
        if s.done then return end
        if not sel then
            if #s.pegs[c] > 0 then sel = c end
        elseif sel == c then
            sel = nil
        elseif not doMove(sel, c) then
            ctx:notify(T("不能把大盘放在小盘上"))
            sel = nil
        else
            sel = nil
        end
        persist()
        self.render()
    end

    function self.render()
        local n = s.n
        local status = T("步数 %d", s.moves) .. T("    最少 %d", Core.optimal(n))
        local best = ctx:best(key())
        if best then status = status .. T("    纪录 %d", best) end
        if s.done then status = status .. T("    完成！") end
        local size_row = {}
        for _, k in ipairs(SIZES) do
            size_row[#size_row + 1] = { text = tostring(k), selected = k == n, callback = function() if k ~= n then fresh(k) end end }
        end
        ctx:render({
            title = T("汉诺塔"),
            status = status,
            grid = {
                rows = n + 1, cols = 3, ratio = 0.6,
                cell = function(r, c)
                    local level = n + 1 - r
                    if level == n then
                        if sel == c then return { icon = "arrow_down", fill = "dark", icon_scale = 0.5 } end
                        return nil
                    end
                    local d = s.pegs[c][level + 1]
                    if not d then return { peg = true } end
                    return { peg = true, bar = 0.3 + 0.7 * d / n }
                end,
                on_tap = tapCell,
            },
            buttons = {
                size_row,
                {
                    { text = T("撤销"), enabled = #undo > 0 and not s.done, callback = function()
                        s.pegs = table.remove(undo)
                        s.moves = s.moves - 1
                        sel = nil
                        persist()
                        self.render()
                    end },
                    { text = T("提示"), enabled = not s.done, callback = function()
                        local f, t = Core.hint(s, 3)
                        if f then
                            sel = f
                            ctx:notify(T("把柱子 %d 顶上的盘子移到柱子 %d", f, t))
                            self.render()
                        end
                    end },
                    { text = T("新游戏"), callback = function() fresh(s.n) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.pegs then
            s, undo = saved.state, saved.undo or {}
        else
            s, undo = Core.fresh(4), {}
        end
        sel = nil
        self.render()
    end

    self.state = function() return s end
    self.tap = tapCell
    return self
end

return M
