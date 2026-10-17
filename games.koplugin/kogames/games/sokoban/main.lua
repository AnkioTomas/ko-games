--[[--
推箱子。滑动或方向按钮推动；可撤销到开头；每关记最少步数。
--]]
local T = require("kogames.l10n")
local LEVELS = require("kogames.games.sokoban.levels")

local Core = {}

local DELTA = { north = { -1, 0 }, south = { 1, 0 }, west = { 0, -1 }, east = { 0, 1 } }

function Core.parse(rows)
    local cols = 0
    for _, row in ipairs(rows) do cols = math.max(cols, #row) end
    local s = { rows = #rows, cols = cols, wall = {}, goal = {}, boxes = {}, moves = 0, hist = {} }
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local ch, idx = row:sub(c, c), (r - 1) * cols + c
            if ch == "#" then s.wall[idx] = true end
            if ch == "." or ch == "*" or ch == "+" then s.goal[idx] = true end
            if ch == "$" or ch == "*" then s.boxes[idx] = true end
            if ch == "@" or ch == "+" then s.player = idx end
        end
    end
    return s
end

--- 走一步；返回是否有效。
function Core.move(s, dir)
    local d = DELTA[dir]
    if not d then return false end
    local r, c = math.ceil(s.player / s.cols), (s.player - 1) % s.cols + 1
    local nr, nc = r + d[1], c + d[2]
    if nr < 1 or nr > s.rows or nc < 1 or nc > s.cols then return false end
    local to = (nr - 1) * s.cols + nc
    if s.wall[to] then return false end
    local entry = { from = s.player }
    if s.boxes[to] then
        local br, bc = nr + d[1], nc + d[2]
        if br < 1 or br > s.rows or bc < 1 or bc > s.cols then return false end
        local bto = (br - 1) * s.cols + bc
        if s.wall[bto] or s.boxes[bto] then return false end
        s.boxes[to], s.boxes[bto] = nil, true
        entry.box_from, entry.box_to = to, bto
    end
    s.player = to
    s.moves = s.moves + 1
    s.hist[#s.hist + 1] = entry
    return true
end

function Core.undo(s)
    local e = table.remove(s.hist)
    if not e then return false end
    s.player = e.from
    if e.box_to then s.boxes[e.box_to], s.boxes[e.box_from] = nil, true end
    s.moves = s.moves - 1
    return true
end

function Core.solved(s)
    for idx in pairs(s.boxes) do if not s.goal[idx] then return false end end
    return true
end

Core.LEVELS = LEVELS

local M = { id = "sokoban", title = T("推箱子"), icon = "inventory_2", art = "box", tier = "A", desc = T("把箱子推到目标上"), help = T("控制小人把所有箱子推到标有圆圈的目标位置。箱子只能推、不能拉，也不能一次推两个。\n在棋盘上滑动或点下方方向键移动。走进死路可以点「撤销」或「重来」。"), core = Core }

function M.new(ctx)
    local self = {}
    local level, s = 1, nil

    local function persist() ctx:save({ level = level, state = s }) end

    local function load(n)
        level = n
        s = Core.parse(LEVELS[n])
        persist()
        self.render()
    end

    local function step(dir)
        if Core.solved(s) then return end
        if not Core.move(s, dir) then return end
        if Core.solved(s) then
            if ctx:record("best_" .. level, s.moves, true) then ctx:notify((T("过关！%d 步，新纪录")):format(s.moves)) end
        end
        persist()
        self.render()
    end

    function self.render()
        local solved = Core.solved(s)
        local status = (T("第 %d / %d 关    步数 %d")):format(level, #LEVELS, s.moves)
        local best = ctx:best("best_" .. level)
        if best then status = status .. T("    最少 %d", best) end
        if solved then status = status .. T("    过关！") end
        ctx:render({
            title = T("推箱子"),
            status = status,
            grid = {
                rows = s.rows, cols = s.cols,
                cell = function(r, c)
                    local idx = (r - 1) * s.cols + c
                    if s.wall[idx] then return { icon = "wall", icon_scale = 1, fill = "black" } end
                    local goal = s.goal[idx]
                    if idx == s.player then return { icon = "player", icon_scale = 0.82, fill = goal and "grey" or nil } end
                    if s.boxes[idx] then return { icon = goal and "box_done" or "box", icon_scale = 0.9, fill = "grey", color = "black" } end
                    if goal then return { icon = "goal", icon_scale = 0.6 } end
                    return nil
                end,
            },
            on_swipe = step,
            buttons = {
                {
                    { text = "←", callback = function() step("west") end },
                    { text = "↑", callback = function() step("north") end },
                    { text = "↓", callback = function() step("south") end },
                    { text = "→", callback = function() step("east") end },
                },
                {
                    { text = T("撤销"), enabled = #s.hist > 0, callback = function() Core.undo(s) persist() self.render() end },
                    { text = T("重来"), callback = function() load(level) end },
                    { text = T("上一关"), enabled = level > 1, callback = function() load(level - 1) end },
                    { text = T("下一关"), enabled = level < #LEVELS, callback = function() load(level + 1) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and LEVELS[saved.level] then level, s = saved.level, saved.state
        else s = Core.parse(LEVELS[1]) end
        self.render()
    end

    self.step, self.state = step, function() return s end
    return self
end

return M
