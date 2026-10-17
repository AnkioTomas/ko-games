--[[--
帐篷（Tents）。每棵树旁边（上下左右）放一顶帐篷，一一对应；帐篷之间互不相邻（含斜角）；行列外的数字是该行/列的帐篷数。
格子：user 0 空，1 帐篷，2 草地（确定没有帐篷）。棋盘上方/左侧多出一行一列显示数字。
生成：先放帐篷再给每顶挑一棵树，用回溯求解器验证解唯一。
--]]
local T = require("kogames.l10n")
local SIZES = { 6, 8, 10 }
local ATTEMPTS = 400
local NODE_CAP = 60000

local Core = {}

local function neighbours4(n, i)
    local out = {}
    local r, c = math.floor((i - 1) / n), (i - 1) % n
    if r > 0 then out[#out + 1] = i - n end
    if r < n - 1 then out[#out + 1] = i + n end
    if c > 0 then out[#out + 1] = i - 1 end
    if c < n - 1 then out[#out + 1] = i + 1 end
    return out
end

local function touches(n, i, j)
    local r1, c1, r2, c2 = math.floor((i - 1) / n), (i - 1) % n, math.floor((j - 1) / n), (j - 1) % n
    return i ~= j and math.abs(r1 - r2) <= 1 and math.abs(c1 - c2) <= 1
end

--- 帐篷集合 tents（true/1 表示有帐篷）能否与树一一配对（二分图匹配）。
function Core.matched(n, tree, tents)
    local list, trees = {}, {}
    for i = 1, n * n do
        if tents[i] then list[#list + 1] = i end
        if tree[i] then trees[#trees + 1] = i end
    end
    if #list ~= #trees then return false end
    local owner = {}
    local function try(t, seen)
        for _, j in ipairs(neighbours4(n, t)) do
            if tree[j] and not seen[j] then
                seen[j] = true
                if not owner[j] or try(owner[j], seen) then owner[j] = t return true end
            end
        end
        return false
    end
    for _, t in ipairs(list) do
        if not try(t, {}) then return false end
    end
    return true
end

--- tents 与 rows/cols 计数、互不相邻、配对规则是否全部满足。
function Core.valid(s, tents)
    local n = s.n
    local rc, cc, list = {}, {}, {}
    for k = 1, n do rc[k], cc[k] = 0, 0 end
    for i = 1, n * n do
        if tents[i] then
            if s.tree[i] then return false end
            local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
            rc[r], cc[c] = rc[r] + 1, cc[c] + 1
            for _, j in ipairs(list) do if touches(n, i, j) then return false end end
            list[#list + 1] = i
        end
    end
    for k = 1, n do if rc[k] ~= s.rows[k] or cc[k] ~= s.cols[k] then return false end end
    return Core.matched(n, s.tree, tents)
end

--- 回溯数解（最多 limit 个）；返回 解数, 第一个解, 是否超出节点上限。
function Core.solve(n, tree, rows, cols, limit)
    local N = n * n
    local cand = {}
    for i = 1, N do
        if not tree[i] then
            for _, j in ipairs(neighbours4(n, i)) do if tree[j] then cand[i] = true break end end
        end
    end
    local tents, rc, cc = {}, {}, {}
    for k = 1, n do rc[k], cc[k] = 0, 0 end
    -- 每列后续还能放的候选格数量，用来剪枝
    local colLeft = {}
    for c = 1, n do
        local k = 0
        for r = 0, n - 1 do if cand[r * n + c] then k = k + 1 end end
        colLeft[c] = k
    end
    local count, first, nodes, capped = 0, nil, 0, false

    local function rowDone(r) -- r 为 1 基
        if rc[r] ~= rows[r] then return false end
        if r >= 2 then
            for c = 1, n do
                local i = (r - 2) * n + c
                if tree[i] then
                    local ok = false
                    for _, j in ipairs(neighbours4(n, i)) do if tents[j] then ok = true break end end
                    if not ok then return false end
                end
            end
        end
        return true
    end

    local function dfs(i)
        if capped or count >= limit then return end
        nodes = nodes + 1
        if nodes > NODE_CAP then capped = true return end
        if i > N then
            if rowDone(n) then
                -- 最后一行的树也要有帐篷
                for c = 1, n do
                    local t = (n - 1) * n + c
                    if tree[t] then
                        local ok = false
                        for _, j in ipairs(neighbours4(n, t)) do if tents[j] then ok = true break end end
                        if not ok then return end
                    end
                end
                for k = 1, n do if cc[k] ~= cols[k] then return end end
                if Core.matched(n, tree, tents) then
                    count = count + 1
                    if not first then first = {} for k in pairs(tents) do first[k] = true end end
                end
            end
            return
        end
        local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
        local function advance()
            if c == n then
                if not rowDone(r) then return end
            end
            dfs(i + 1)
        end
        if cand[i] then colLeft[c] = colLeft[c] - 1 end
        -- 放帐篷
        if cand[i] and rc[r] < rows[r] and cc[c] < cols[c] then
            local ok = true
            if c > 1 and tents[i - 1] then ok = false end
            if ok and r > 1 then
                if tents[i - n] or (c > 1 and tents[i - n - 1]) or (c < n and tents[i - n + 1]) then ok = false end
            end
            if ok then
                tents[i], rc[r], cc[c] = true, rc[r] + 1, cc[c] + 1
                advance()
                tents[i], rc[r], cc[c] = nil, rc[r] - 1, cc[c] - 1
            end
        end
        -- 不放：该列剩余候选必须够填满
        if cc[c] + colLeft[c] >= cols[c] then
            advance()
        end
        if cand[i] then colLeft[c] = colLeft[c] + 1 end
    end
    dfs(1)
    return count, first, capped
end

function Core.fresh(rng, n)
    n = n or 6
    local best
    local target = math.floor(n * n * 0.22 + 0.5)
    for attempt = 1, ATTEMPTS do
        local tents, tree, list = {}, {}, {}
        local order = {}
        for i = 1, n * n do order[i] = i end
        rng:shuffle(order)
        for _, i in ipairs(order) do
            if #list >= target then break end
            local ok = true
            for _, j in ipairs(list) do if touches(n, i, j) then ok = false break end end
            if ok then
                -- 给它挑一个还没被占用的相邻格做树
                local opts = {}
                for _, j in ipairs(neighbours4(n, i)) do
                    if not tree[j] and not tents[j] then opts[#opts + 1] = j end
                end
                if #opts > 0 then
                    tents[i] = true
                    list[#list + 1] = i
                    tree[opts[rng:int(#opts)]] = true
                end
            end
        end
        -- 树格不能与后来放的帐篷重叠
        local clash = false
        for i in pairs(tents) do if tree[i] then clash = true end end
        if not clash and #list >= math.max(3, target - 2) then
            local rows, cols = {}, {}
            for k = 1, n do rows[k], cols[k] = 0, 0 end
            for i in pairs(tents) do
                local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
                rows[r], cols[c] = rows[r] + 1, cols[c] + 1
            end
            local user = {}
            for i = 1, n * n do
                user[i] = 0
                tents[i], tree[i] = tents[i] or false, tree[i] or false
            end
            best = { n = n, tree = tree, sol = tents, rows = rows, cols = cols, user = user }
            local cnt = Core.solve(n, tree, rows, cols, 2)
            if cnt == 1 then break end
        end
    end
    return best
end

local function userTents(s)
    local t = {}
    for i = 1, s.n * s.n do if s.user[i] == 1 then t[i] = true end end
    return t
end

--- 与别的帐篷相邻的帐篷（冲突）。
local function conflict(s, i)
    for j = 1, s.n * s.n do
        if s.user[j] == 1 and touches(s.n, i, j) then return true end
    end
    return false
end

local M = { id = "tents", title = T("帐篷"), icon = "apps", art = "icon_tents", tier = "A", desc = T("给每棵树搭一顶帐篷"), help = T("给每棵树的上下左右相邻处搭一顶帐篷，树和帐篷一一对应。\n帐篷之间不能相邻，斜角也不行；棋盘外的数字是该行/列的帐篷数。\n点按格子依次切换：帐篷 ▲、草地 ·、空；长按直接标草地。\n数字变灰表示该行/列已放够。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, started

    local function persist() ctx:save({ state = s, started = started }) end

    local function newGame(n)
        s, started = Core.fresh(ctx.rng, n), ctx.host:now()
        persist()
        self.render()
    end

    local function check()
        if s.done or not Core.valid(s, userTents(s)) then return end
        s.done = true
        s.time = math.floor(ctx.host:now() - started)
        if ctx:record("best_" .. s.n, s.time, true) then
            ctx:notify((T("新纪录：%d 分 %d 秒")):format(math.floor(s.time / 60), s.time % 60))
        end
    end

    local function setCell(i, v)
        if s.done or s.tree[i] then return end
        s.user[i] = v
        check()
        persist()
        self.render()
    end

    local function toIndex(r, c)
        if r < 2 or c < 2 then return nil end
        return (r - 2) * s.n + c - 1
    end

    function self.render()
        local n = s.n
        local rc, cc = {}, {}
        for k = 1, n do rc[k], cc[k] = 0, 0 end
        for i = 1, n * n do
            if s.user[i] == 1 then
                local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
                rc[r], cc[c] = rc[r] + 1, cc[c] + 1
            end
        end
        local status = T("%d×%d", n, n)
        if s.done then status = status .. T("    完成！") .. (T("    用时 %d:%02d")):format(math.floor(s.time / 60), s.time % 60) end
        local best = ctx:best("best_" .. n)
        if best then status = status .. (T("    最佳 %d:%02d")):format(math.floor(best / 60), best % 60) end
        local size_row = {}
        for _, k in ipairs(SIZES) do
            size_row[#size_row + 1] = { text = k .. "×" .. k, selected = k == n, callback = function() if k ~= n then newGame(k) end end }
        end
        ctx:render({
            title = T("帐篷"),
            status = status,
            grid = {
                rows = n + 1, cols = n + 1,
                cell = function(r, c)
                    if r == 1 and c == 1 then return nil end
                    if r == 1 then
                        return { text = tostring(s.cols[c - 1]), scale = 0.5, color = cc[c - 1] == s.cols[c - 1] and "grey" or "black" }
                    end
                    if c == 1 then
                        return { text = tostring(s.rows[r - 1]), scale = 0.5, color = rc[r - 1] == s.rows[r - 1] and "grey" or "black" }
                    end
                    local i = toIndex(r, c)
                    if s.tree[i] then return { text = T("树"), fill = "dark", color = "white", scale = 0.5 } end
                    local v = s.user[i]
                    if v == 1 then
                        return { text = "▲", scale = 0.55, fill = conflict(s, i) and "dark" or nil, color = conflict(s, i) and "white" or "black" }
                    end
                    if v == 2 then return { text = "·", color = "grey", scale = 0.7 } end
                    return nil
                end,
                on_tap = function(r, c)
                    local i = toIndex(r, c)
                    if i then setCell(i, (s.user[i] + 1) % 3) end
                end,
                on_hold = function(r, c)
                    local i = toIndex(r, c)
                    if i then setCell(i, s.user[i] == 2 and 0 or 2) end
                end,
            },
            buttons = {
                size_row,
                {
                    { text = T("重新开始"), callback = function()
                        if s.done then return end
                        for i = 1, n * n do s.user[i] = 0 end
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
        if saved and saved.state and saved.state.tree then
            s, started = saved.state, saved.started or ctx.host:now()
        else
            s, started = Core.fresh(ctx.rng, 6), ctx.host:now()
        end
        self.render()
    end

    self.state = function() return s end
    return self
end

return M
