--[[--
2048。滑动（或方向按钮）合并方块；可撤销一步；自动存档。
--]]
local T = require("kogames.l10n")
local N = 4

local Core = {}

function Core.fresh(rng)
    local s = { board = {}, score = 0, won = false, over = false }
    for i = 1, N * N do s.board[i] = 0 end
    Core.spawn(s, rng)
    Core.spawn(s, rng)
    return s
end

function Core.spawn(s, rng)
    local empty = {}
    for i = 1, N * N do if s.board[i] == 0 then empty[#empty + 1] = i end end
    if #empty == 0 then return end
    s.board[empty[rng:int(#empty)]] = rng:float() < 0.9 and 2 or 4
end

-- 把一行向前（下标小的一侧）压紧合并，返回新行、得到的分、是否变化
local function slide(line)
    local out, gained, last = {}, 0, nil
    for _, v in ipairs(line) do
        if v ~= 0 then
            if last and out[#out] == v and last == v then
                out[#out] = v * 2
                gained = gained + v * 2
                last = nil
            else
                out[#out + 1] = v
                last = v
            end
        end
    end
    for i = #out + 1, N do out[i] = 0 end
    local changed = false
    for i = 1, N do if out[i] ~= line[i] then changed = true end end
    return out, gained, changed
end

local DIRS = { west = true, east = true, north = true, south = true }

--- 返回是否发生移动；会改 s.board / s.score，不生成新方块。
function Core.move(s, dir)
    if not DIRS[dir] then return false end
    local moved = false
    for k = 1, N do
        local line = {}
        for i = 1, N do
            local idx
            if dir == "west" then idx = (k - 1) * N + i
            elseif dir == "east" then idx = (k - 1) * N + (N + 1 - i)
            elseif dir == "north" then idx = (i - 1) * N + k
            else idx = (N - i) * N + k end
            line[i] = s.board[idx]
        end
        local out, gained, changed = slide(line)
        if changed then
            moved = true
            s.score = s.score + gained
            for i = 1, N do
                local idx
                if dir == "west" then idx = (k - 1) * N + i
                elseif dir == "east" then idx = (k - 1) * N + (N + 1 - i)
                elseif dir == "north" then idx = (i - 1) * N + k
                else idx = (N - i) * N + k end
                s.board[idx] = out[i]
                if out[i] >= 2048 then s.won = true end
            end
        end
    end
    return moved
end

function Core.canMove(s)
    for i = 1, N * N do if s.board[i] == 0 then return true end end
    for r = 1, N do
        for c = 1, N do
            local v = s.board[(r - 1) * N + c]
            if c < N and s.board[(r - 1) * N + c + 1] == v then return true end
            if r < N and s.board[r * N + c] == v then return true end
        end
    end
    return false
end

local function copy(s)
    local t = { board = {}, score = s.score, won = s.won, over = s.over }
    for i = 1, N * N do t.board[i] = s.board[i] end
    return t
end

local M = { id = "2048", title = "2048", icon = "grid_view", tier = "A", desc = T("滑动合并方块"), core = Core }

function M.new(ctx)
    local self = {}
    local s, prev

    local function persist() ctx:save({ state = s, prev = prev }) end

    local function step(dir)
        if s.over then return end
        local before = copy(s)
        if not Core.move(s, dir) then return end
        prev = before
        Core.spawn(s, ctx.rng)
        if not Core.canMove(s) then
            s.over = true
            if ctx:record("best", s.score) then ctx:notify(T("新纪录：%d", s.score)) end
        end
        persist()
        self.render()
    end

    function self.render()
        local best = ctx:best("best") or 0
        local status = (T("得分 %d    最高 %d")):format(s.score, math.max(best, s.score))
        if s.over then status = status .. T("    游戏结束") elseif s.won then status = status .. T("    已达成 2048") end
        ctx:render({
            title = "2048",
            status = status,
            grid = {
                rows = N, cols = N,
                cell = function(r, c)
                    local v = s.board[(r - 1) * N + c]
                    if v == 0 then return nil end
                    local fill = v >= 128 and "black" or (v >= 16 and "dark" or "grey")
                    return { text = tostring(v), fill = fill, scale = v >= 1024 and 0.3 or (v >= 128 and 0.38 or 0.5) }
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
                    { text = T("撤销"), enabled = prev ~= nil, callback = function() s, prev = prev, nil persist() self.render() end },
                    { text = T("新游戏"), callback = function() s, prev = Core.fresh(ctx.rng), nil persist() self.render() end },
                    { text = T("返回"), callback = function() ctx:exit() end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state then s, prev = saved.state, saved.prev else s = Core.fresh(ctx.rng) end
        self.render()
    end

    self.step = step
    self.state = function() return s end
    return self
end

return M
