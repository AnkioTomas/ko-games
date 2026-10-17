--[[--
洪水填色（Flood-It）。每步选一种颜色，左上角连通区域变成该颜色并吞并相邻同色格；
在步数上限内把整块棋盘染成一色。点击任意格或下方颜色按钮选色，可撤销。
--]]
local T = require("kogames.l10n")
local SIZES = { 8, 12, 16 }
local NCOL = 5
local ICONS = { "sym_06", "sym_08", "sym_07", "sym_03", "sym_01" }
local FILLS = { "grey", "dark", "black", "raised", false }
local MARGIN = { [8] = 2, [12] = 3, [16] = 4 }
local UNDO_CAP = 200

local Core = {}

local function region(b, n, color)
    local seen, list, stack = { [1] = true }, { 1 }, { 1 }
    while #stack > 0 do
        local i = table.remove(stack)
        local r, c = math.floor((i - 1) / n), (i - 1) % n
        local nb = { r > 0 and i - n or nil, r < n - 1 and i + n or nil, c > 0 and i - 1 or nil, c < n - 1 and i + 1 or nil }
        for _, j in pairs(nb) do
            if not seen[j] and b[j] == color then
                seen[j] = true
                list[#list + 1] = j
                stack[#stack + 1] = j
            end
        end
    end
    return list
end

--- 把左上角区域染成 color，返回是否有变化。
function Core.fill(b, n, color)
    local old = b[1]
    if old == color then return false end
    for _, i in ipairs(region(b, n, old)) do b[i] = color end
    return true
end

function Core.solved(b)
    for i = 2, #b do if b[i] ~= b[1] then return false end end
    return true
end

--- 贪心求解步数（每步选吞并格数最多的颜色），作为步数上限的基准。
function Core.greedy(b0, n)
    local b = {}
    for i = 1, #b0 do b[i] = b0[i] end
    local moves = 0
    while not Core.solved(b) do
        local best, bestSize
        for col = 1, NCOL do
            if col ~= b[1] then
                local t = {}
                for i = 1, #b do t[i] = b[i] end
                Core.fill(t, n, col)
                local sz = #region(t, n, col)
                if not bestSize or sz > bestSize then best, bestSize = col, sz end
            end
        end
        Core.fill(b, n, best)
        moves = moves + 1
    end
    return moves
end

function Core.fresh(rng, n)
    n = n or 12
    local b
    repeat
        b = {}
        for i = 1, n * n do b[i] = rng:int(NCOL) end
    until not Core.solved(b)
    return { n = n, board = b, moves = 0, limit = Core.greedy(b, n) + (MARGIN[n] or 3) }
end

local function copy(b)
    local t = {}
    for i = 1, #b do t[i] = b[i] end
    return t
end

local M = { id = "flood", title = T("洪水填色"), icon = "apps", art = "icon_flood", tier = "A", desc = T("用颜色吞并整块棋盘"), help = T("每一步选一种颜色，左上角的色块会变成该颜色，并吞并相邻的同色格。\n点击棋盘任意格或下方数字按钮选色；每种颜色有不同的深浅和数字。\n在步数上限内把整块棋盘染成同一种颜色即过关。\n可以撤销，也可以切换棋盘大小。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, undo

    local function key() return "best" .. s.n end
    local function persist() ctx:save({ state = s, undo = undo }) end

    local function fresh(n)
        s, undo = Core.fresh(ctx.rng, n), {}
        persist()
        self.render()
    end

    local function pick(col)
        if s.done or s.lost then return end
        local before = copy(s.board)
        if not Core.fill(s.board, s.n, col) then return end
        undo[#undo + 1] = before
        if #undo > UNDO_CAP then table.remove(undo, 1) end
        s.moves = s.moves + 1
        if Core.solved(s.board) then
            s.done = true
            if ctx:record(key(), s.moves, true) then ctx:notify(T("新纪录：%d", s.moves)) end
        elseif s.moves >= s.limit then
            s.lost = true
        end
        persist()
        self.render()
    end

    function self.render()
        local n = s.n
        local status = T("步数 %d / %d", s.moves, s.limit)
        local best = ctx:best(key())
        if best then status = status .. T("    最少 %d", best) end
        if s.done then status = status .. T("    完成！") elseif s.lost then status = status .. T("    步数用完") end
        local sizes = {}
        for _, k in ipairs(SIZES) do
            sizes[#sizes + 1] = { text = k .. "×" .. k, selected = k == n, callback = function() if k ~= n then fresh(k) end end }
        end
        ctx:render({
            title = T("洪水填色"),
            status = status,
            grid = {
                rows = n, cols = n,
                cell = function(r, c)
                    local v = s.board[(r - 1) * n + c]
                    return { icon = ICONS[v] .. (v == 3 and "_w" or ""), fill = FILLS[v] or nil, icon_scale = 0.6 }
                end,
                on_tap = function(r, c) pick(s.board[(r - 1) * n + c]) end,
            },
            buttons = {
                sizes,
                {
                    { text = T("撤销"), enabled = #undo > 0, callback = function()
                        s.board = table.remove(undo)
                        s.moves = s.moves - 1
                        s.done, s.lost = nil, nil
                        persist()
                        self.render()
                    end },
                    { text = T("新游戏"), callback = function() fresh(s.n) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.board then
            s, undo = saved.state, saved.undo or {}
        else
            s, undo = Core.fresh(ctx.rng, 12), {}
        end
        self.render()
    end

    self.state = function() return s end
    self.pick = pick
    return self
end

return M
