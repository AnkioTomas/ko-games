--[[--
黑白填格（Unruly / Binairo）。格子：0 空，1 黑，2 白。
规则：任意行列不能有连续三个同色；每行每列黑白数量相同。（不要求行列互不相同。）
生成：随机求出完整解，再随机挖空并用求解器保证解唯一。
--]]
local T = require("kogames.l10n")
local SIZES = { 6, 8, 10 }
local UNDO_CAP = 300

local Core = {}

local function lineIdx(n, horizontal, k)
    local t = {}
    for i = 1, n do t[i] = horizontal and (k - 1) * n + i or (i - 1) * n + k end
    return t
end

local LINES = {}
local function lines(n)
    if not LINES[n] then
        local l = {}
        for k = 1, n do
            l[#l + 1] = lineIdx(n, true, k)
            l[#l + 1] = lineIdx(n, false, k)
        end
        LINES[n] = l
    end
    return LINES[n]
end

-- 推理：补全强制格；矛盾返回 false
local function propagate(g, n)
    local half = n / 2
    local changed = true
    while changed do
        changed = false
        for _, idx in ipairs(lines(n)) do
            for i = 1, n - 2 do
                local a, b, c = idx[i], idx[i + 1], idx[i + 2]
                local va, vb, vc = g[a], g[b], g[c]
                if va ~= 0 and va == vb and vb == vc then return false end
                if va ~= 0 and va == vb and vc == 0 then g[c] = 3 - va changed = true
                elseif vb ~= 0 and vb == vc and va == 0 then g[a] = 3 - vb changed = true
                elseif va ~= 0 and va == vc and vb == 0 then g[b] = 3 - va changed = true end
            end
            local cnt = { 0, 0 }
            for i = 1, n do local v = g[idx[i]] if v ~= 0 then cnt[v] = cnt[v] + 1 end end
            if cnt[1] > half or cnt[2] > half then return false end
            for v = 1, 2 do
                if cnt[v] == half and cnt[3 - v] < half then
                    for i = 1, n do
                        if g[idx[i]] == 0 then g[idx[i]] = 3 - v changed = true end
                    end
                end
            end
        end
    end
    return true
end

--- 求解，返回 解的个数（至多 limit）与第一个解；rng 非空时随机选择分支顺序。
function Core.solve(cells, n, limit, rng)
    local count, first = 0, nil
    local function go(g)
        if not propagate(g, n) then return end
        local pick
        for i = 1, n * n do if g[i] == 0 then pick = i break end end
        if not pick then
            count = count + 1
            first = first or g
            return
        end
        local a = rng and rng:int(2) or 1
        for _, v in ipairs({ a, 3 - a }) do
            local h = {}
            for i = 1, n * n do h[i] = g[i] end
            h[pick] = v
            go(h)
            if count >= limit then return end
        end
    end
    local g = {}
    for i = 1, n * n do g[i] = cells[i] end
    go(g)
    return count, first
end

--- 违规格集合：三连同色的格子 -> true
function Core.conflicts(cells, n)
    local bad = {}
    for _, idx in ipairs(lines(n)) do
        for i = 1, n - 2 do
            local v = cells[idx[i]]
            if v ~= 0 and v == cells[idx[i + 1]] and v == cells[idx[i + 2]] then
                bad[idx[i]], bad[idx[i + 1]], bad[idx[i + 2]] = true, true, true
            end
        end
    end
    return bad
end

function Core.solved(cells, n)
    for i = 1, n * n do if cells[i] == 0 then return false end end
    if next(Core.conflicts(cells, n)) then return false end
    for _, idx in ipairs(lines(n)) do
        local black = 0
        for i = 1, n do if cells[idx[i]] == 1 then black = black + 1 end end
        if black * 2 ~= n then return false end
    end
    return true
end

function Core.fresh(rng, n)
    n = n or 6
    local empty = {}
    for i = 1, n * n do empty[i] = 0 end
    local _, sol = Core.solve(empty, n, 1, rng)
    local puz = {}
    for i = 1, n * n do puz[i] = sol[i] end
    local order = {}
    for i = 1, n * n do order[i] = i end
    rng:shuffle(order)
    for _, i in ipairs(order) do
        local keep = puz[i]
        puz[i] = 0
        if Core.solve(puz, n, 2) ~= 1 then puz[i] = keep end
    end
    local user, given = {}, {}
    for i = 1, n * n do user[i] = puz[i] given[i] = puz[i] ~= 0 end
    return { n = n, sol = sol, given = given, user = user }
end

local M = { id = "unruly", title = T("黑白填格"), icon = "grid_view", art = "icon_unruly", tier = "A", desc = T("黑白填格，不许三连"), help = T("把格子填成黑或白：任意行列都不能出现连续三个同色，且每行每列的黑白数量相同。\n点按空格依次变为黑、白、空；灰底的是题目给定的格子，不能修改。\n出现三连的格子中央会显示小方块标记。\n（本版不要求行列互不相同。）"), core = Core }

function M.new(ctx)
    local self = {}
    local s, started, undo

    local function persist() ctx:save({ state = s, started = started, undo = undo }) end

    local function newGame(n)
        s, started, undo = Core.fresh(ctx.rng, n), ctx.host:now(), {}
        persist()
        self.render()
    end

    local function tapCell(i)
        if s.done or s.given[i] then return end
        undo[#undo + 1] = { i, s.user[i] }
        if #undo > UNDO_CAP then table.remove(undo, 1) end
        s.user[i] = (s.user[i] + 1) % 3
        if Core.solved(s.user, s.n) then
            s.done = true
            s.time = math.floor(ctx.host:now() - started)
            if ctx:record("best_" .. s.n, s.time, true) then
                ctx:notify((T("新纪录：%d 分 %d 秒")):format(math.floor(s.time / 60), s.time % 60))
            end
        end
        persist()
        self.render()
    end

    function self.render()
        local n = s.n
        local bad = Core.conflicts(s.user, n)
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
        ctx:render({
            title = T("黑白填格"),
            status = status,
            grid = {
                rows = n, cols = n,
                cell = function(r, c)
                    local i = (r - 1) * n + c
                    local v = s.user[i]
                    local cell = { fill = s.given[i] and "grey" or nil }
                    if v == 1 then
                        cell.shape = "black"
                        if bad[i] then cell.mark = "white" end
                    elseif v == 2 then
                        cell.shape = "white"
                        if bad[i] then cell.mark = "black" end
                    end
                    return cell
                end,
                on_tap = function(r, c) tapCell((r - 1) * n + c) end,
            },
            buttons = {
                size_row,
                {
                    { text = T("撤销"), enabled = #undo > 0 and not s.done, callback = function()
                        local u = table.remove(undo)
                        s.user[u[1]] = u[2]
                        persist()
                        self.render()
                    end },
                    { text = T("重新开始"), callback = function()
                        for i = 1, n * n do s.user[i] = s.given[i] and s.sol[i] or 0 end
                        s.done, undo = nil, {}
                        persist()
                        self.render()
                    end },
                    { text = T("新游戏"), callback = function() newGame(n) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.sol then
            s, started, undo = saved.state, saved.started or ctx.host:now(), saved.undo or {}
        else
            s, started, undo = Core.fresh(ctx.rng, 6), ctx.host:now(), {}
        end
        self.render()
    end

    self.state = function() return s end
    return self
end

return M
