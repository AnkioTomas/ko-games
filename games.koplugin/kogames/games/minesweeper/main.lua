--[[--
扫雷。点按翻开，长按插旗（也可切到「标记」模式点按）；首次翻开保证不是雷。
--]]
local T = require("kogames.l10n")
local LEVELS = {
    { name = "初级", rows = 9, cols = 9, mines = 10 },
    { name = "中级", rows = 12, cols = 12, mines = 24 },
    { name = "高级", rows = 16, cols = 16, mines = 40 },
}

local Core = {}

function Core.fresh(level)
    local s = { rows = level.rows, cols = level.cols, mines = level.mines, level = level.name,
        cells = {}, placed = false, over = false, won = false, revealed = 0, flags = 0 }
    for i = 1, level.rows * level.cols do s.cells[i] = { mine = false, open = false, flag = false, n = 0 } end
    return s
end

local function neighbors(s, r, c)
    local out = {}
    for dr = -1, 1 do
        for dc = -1, 1 do
            local rr, cc = r + dr, c + dc
            if (dr ~= 0 or dc ~= 0) and rr >= 1 and rr <= s.rows and cc >= 1 and cc <= s.cols then
                out[#out + 1] = (rr - 1) * s.cols + cc
            end
        end
    end
    return out
end

local function place(s, safe_r, safe_c, rng)
    local pool = {}
    for r = 1, s.rows do
        for c = 1, s.cols do
            if math.abs(r - safe_r) > 1 or math.abs(c - safe_c) > 1 then pool[#pool + 1] = (r - 1) * s.cols + c end
        end
    end
    rng:shuffle(pool)
    for i = 1, s.mines do s.cells[pool[i]].mine = true end
    for r = 1, s.rows do
        for c = 1, s.cols do
            local n = 0
            for _, idx in ipairs(neighbors(s, r, c)) do if s.cells[idx].mine then n = n + 1 end end
            s.cells[(r - 1) * s.cols + c].n = n
        end
    end
    s.placed = true
end

function Core.open(s, r, c, rng)
    if s.over then return end
    if not s.placed then place(s, r, c, rng) end
    local first = s.cells[(r - 1) * s.cols + c]
    if first.flag or first.open then return end
    local stack = { { r, c } }
    while #stack > 0 do
        local p = table.remove(stack)
        local cell = s.cells[(p[1] - 1) * s.cols + p[2]]
        if not cell.open and not cell.flag then
            cell.open = true
            if cell.mine then
                s.over = true
                return
            end
            s.revealed = s.revealed + 1
            if cell.n == 0 then
                for _, idx in ipairs(neighbors(s, p[1], p[2])) do
                    stack[#stack + 1] = { math.ceil(idx / s.cols), (idx - 1) % s.cols + 1 }
                end
            end
        end
    end
    if s.revealed == s.rows * s.cols - s.mines then s.over, s.won = true, true end
end

function Core.flag(s, r, c)
    if s.over then return end
    local cell = s.cells[(r - 1) * s.cols + c]
    if cell.open then return end
    cell.flag = not cell.flag
    s.flags = s.flags + (cell.flag and 1 or -1)
end

local M = { id = "minesweeper", title = T("扫雷"), icon = "flag", art = "mine", tier = "A", desc = T("经典扫雷"), help = T("点按格子翻开它。数字表示周围 8 格里有几颗雷；翻开所有不是雷的格子即获胜，踩到雷则失败。\n怀疑是雷的格子可以标记：切换到「标记」模式再点按，或长按格子。\n第一次点击一定安全。"), core = Core, LEVELS = LEVELS }

function M.new(ctx)
    local self = {}
    local s, mode, started = nil, "open", nil

    local function persist() ctx:save({ state = s, started = started }) end

    local function elapsed() return started and math.max(0, math.floor(ctx.host:now() - started)) or 0 end

    local function finish()
        if s.won then
            local t = elapsed()
            if ctx:record("best_" .. s.level, t, true) then ctx:notify((T("新纪录：%d 秒")):format(t)) end
        end
    end

    local function tap(r, c)
        local cell = s.cells[(s.cols) * (r - 1) + c]
        if mode == "flag" then
            Core.flag(s, r, c)
        else
            if cell.open then
                -- 点已翻开的数字：周围旗数够了就翻开其余
                local flags = 0
                local around = {}
                for dr = -1, 1 do for dc = -1, 1 do
                    local rr, cc = r + dr, c + dc
                    if (dr ~= 0 or dc ~= 0) and rr >= 1 and rr <= s.rows and cc >= 1 and cc <= s.cols then
                        around[#around + 1] = { rr, cc }
                        if s.cells[(rr - 1) * s.cols + cc].flag then flags = flags + 1 end
                    end
                end end
                if cell.n > 0 and flags == cell.n then
                    for _, p in ipairs(around) do Core.open(s, p[1], p[2], ctx.rng) end
                end
            else
                started = started or ctx.host:now()
                Core.open(s, r, c, ctx.rng)
            end
        end
        if s.over then finish() end
        persist()
        self.render()
    end

    local function hold(r, c)
        local was = mode
        mode = "flag"
        tap(r, c)
        mode = was
    end

    local function newGame(level)
        s, started = Core.fresh(level), nil
        persist()
        self.render()
    end

    function self.render()
        local status = T("%s    剩余雷 %d    用时 %ds", T(s.level), s.mines - s.flags, elapsed())
        if s.won then status = status .. T("    通关！") elseif s.over then status = status .. T("    踩雷了") end
        local best = ctx:best("best_" .. s.level)
        if best then status = status .. T("    最佳 %ds", best) end
        local level_row = {}
        for _, lv in ipairs(LEVELS) do
            level_row[#level_row + 1] = { text = T(lv.name), selected = lv.name == s.level, callback = function() newGame(lv) end }
        end
        ctx:render({
            title = T("扫雷"),
            status = status,
            grid = {
                rows = s.rows, cols = s.cols, on_tap = tap, on_hold = hold,
                cell = function(r, c)
                    local cell = s.cells[(r - 1) * s.cols + c]
                    if cell.open then
                        if cell.mine then return { icon = "mine", fill = "dark", icon_scale = 0.8 } end
                        return { text = cell.n > 0 and tostring(cell.n) or "", fill = "grey" }
                    end
                    if s.over and cell.mine and not s.won then return { icon = "mine", fill = "grey", icon_scale = 0.75 } end
                    if cell.flag then return { icon = "flag", fill = "raised", icon_scale = 0.7 } end
                    return { fill = "raised" }
                end,
            },
            settings = { groups = { { label = T("难度"), options = level_row } }, reset = function() newGame({ name = s.level, rows = s.rows, cols = s.cols, mines = s.mines }) end },
            buttons = {
                {
                    { text = mode == "open" and T("翻开") or T("标记"), selected = true,
                      callback = function() mode = mode == "open" and "flag" or "open" self.render() end },
                    { text = T("重新开始"), callback = function() newGame({ name = s.level, rows = s.rows, cols = s.cols, mines = s.mines }) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state then s, started = saved.state, saved.started else s = Core.fresh(LEVELS[1]) end
        self.render()
    end

    self.tap, self.hold, self.state = tap, hold, function() return s end
    return self
end

return M
