--[[--
填数分区（Fillomino）。把棋盘划分成若干区域，每个区域的格子数等于区域内所写的数字。
val[i] 为 0 表示空；相邻且数字相同的格子视为同一区域。生成：随机把棋盘切成不超过 9 格的块，
再逐步揭示数字，用回溯求解器保证唯一解（求解器给出另一解时就把差异格揭示出来）。
--]]
local T = require("kogames.l10n")
local SIZES = { 6, 8 }
local MAX = 9
local NODE_CAP = 1500

local Core = {}

local function neighbours(n, i)
    local out = {}
    local r, c = math.floor((i - 1) / n), (i - 1) % n
    if r > 0 then out[#out + 1] = i - n end
    if c > 0 then out[#out + 1] = i - 1 end
    if c < n - 1 then out[#out + 1] = i + 1 end
    if r < n - 1 then out[#out + 1] = i + n end
    return out
end

--- 从 i 出发的同数字连通块：返回 格子表, 是否还有空邻格。
local function component(n, val, i)
    local v = val[i]
    local seen, list, stack, open = { [i] = true }, { i }, { i }, false
    while #stack > 0 do
        local k = table.remove(stack)
        for _, j in ipairs(neighbours(n, k)) do
            if val[j] == 0 then open = true
            elseif val[j] == v and not seen[j] then
                seen[j] = true
                list[#list + 1] = j
                stack[#stack + 1] = j
            end
        end
    end
    return list, open
end

--- 格子 i 当前所在区域的状态："ok" 已完成且正确，"bad" 已冲突，nil 未定。
function Core.status(n, val, i)
    local v = val[i]
    if v == 0 then return nil end
    local list, open = component(n, val, i)
    if #list > v or (#list < v and not open) then return "bad" end
    if #list == v then return "ok" end
    return nil
end

--- 全部填满且每个区域大小都等于数字。
function Core.solved(n, val)
    for i = 1, n * n do
        if val[i] == 0 or Core.status(n, val, i) ~= "ok" then return false end
    end
    return true
end

--- 随机切分：返回每格的数字（所在区域大小）；相邻区域大小互不相同，避免合并成一个区域。
function Core.partition(rng, n)
    local N = n * n
    local weights = { 1, 2, 3, 4, 4, 5, 5, 6, 7 }
    local sol
    for _ = 1, 100 do
        local reg, sizes = {}, {}
        for i = 1, N do reg[i] = 0 end
        local order = {}
        for i = 1, N do order[i] = i end
        rng:shuffle(order)
        local bad = false
        for _, start in ipairs(order) do
            if reg[start] == 0 then
                local id = #sizes + 1
                local cells
                for _ = 1, 12 do
                    local target = weights[rng:int(#weights)]
                    cells = { start }
                    reg[start] = id
                    while #cells < target do
                        local opts = {}
                        for _, k in ipairs(cells) do
                            for _, j in ipairs(neighbours(n, k)) do
                                if reg[j] == 0 then opts[#opts + 1] = j end
                            end
                        end
                        if #opts == 0 then break end
                        local j = opts[rng:int(#opts)]
                        reg[j] = id
                        cells[#cells + 1] = j
                    end
                    local clash = false
                    for _, k in ipairs(cells) do
                        for _, j in ipairs(neighbours(n, k)) do
                            if reg[j] ~= 0 and reg[j] ~= id and sizes[reg[j]] == #cells then clash = true end
                        end
                    end
                    if not clash then break end
                    for _, k in ipairs(cells) do reg[k] = 0 end
                    cells = nil
                end
                if not cells then bad = true break end
                sizes[id] = #cells
            end
        end
        if not bad then
            sol = {}
            for i = 1, N do sol[i] = sizes[reg[i]] end
            break
        end
    end
    return sol
end

--- 回溯数解（最多 limit 个）。返回 解数, 第一个与 avoid 不同的解（若给出 avoid）, 是否超出节点上限。
function Core.solve(n, given, limit)
    local N = n * n
    local val = {}
    for i = 1, N do val[i] = given[i] end
    local empties = 0
    for i = 1, N do if val[i] == 0 then empties = empties + 1 end end
    local count, other, nodes, capped, firstSol = 0, nil, 0, false, nil

    -- 未满的区域能否经由空格与同数字格长到目标大小
    local function reachable(i)
        local v = val[i]
        local seen, stack, got = { [i] = true }, { i }, 1
        while #stack > 0 and got < v do
            local k = table.remove(stack)
            for _, j in ipairs(neighbours(n, k)) do
                if not seen[j] and (val[j] == 0 or val[j] == v) then seen[j] = true stack[#stack + 1] = j got = got + 1 end
            end
        end
        return got >= v
    end

    local function fine(i)
        if Core.status(n, val, i) == "bad" or not reachable(i) then return false end
        for _, j in ipairs(neighbours(n, i)) do
            if val[j] ~= 0 and val[j] ~= val[i] and (Core.status(n, val, j) == "bad" or not reachable(j)) then return false end
        end
        return true
    end

    local function dfs(left)
        if capped or count >= limit then return end
        nodes = nodes + 1
        if nodes > NODE_CAP then capped = true return end
        if left == 0 then
            count = count + 1
            local copy = {}
            for i = 1, N do copy[i] = val[i] end
            if count == 1 then firstSol = copy else other = copy end
            return
        end
        -- 选已填邻格最多的空格
        local pick, bestN = nil, -1
        for i = 1, N do
            if val[i] == 0 then
                local k = 0
                for _, j in ipairs(neighbours(n, i)) do if val[j] ~= 0 then k = k + 1 end end
                if k > bestN then pick, bestN = i, k end
            end
        end
        local i = pick
        for v = 1, MAX do
            val[i] = v
            if fine(i) then dfs(left - 1) end
        end
        val[i] = 0
    end
    dfs(empties)
    return count, firstSol, other, capped
end

function Core.fresh(rng, n)
    n = n or 6
    local N = n * n
    local sol = Core.partition(rng, n)
    local given = {}
    for i = 1, N do given[i] = sol[i] end
    -- 从全部给出开始，逐个尝试隐藏数字，解不再唯一（或求解超限）就保留
    local order = {}
    for i = 1, N do order[i] = i end
    rng:shuffle(order)
    local want = math.floor(N * 0.4)
    local hidden = 0
    for _, i in ipairs(order) do
        if hidden >= want then break end
        given[i] = 0
        local count, _, _, capped = Core.solve(n, given, 2)
        if count == 1 and not capped then hidden = hidden + 1 else given[i] = sol[i] end
    end
    local val = {}
    for i = 1, N do val[i] = given[i] end
    return { n = n, sol = sol, given = given, val = val }
end

local M = { id = "filling", title = T("填数分区"), icon = "grid_view", art = "icon_filling", tier = "A", desc = T("按数字把棋盘划成区域"), help = T("把棋盘划分成若干区域，每个区域的格子数必须等于区域里写的数字，相邻的同数字格子算同一个区域。\n点按空格选中，再点下方数字填入；「清除」擦掉所填的数字，题目给出的数字不能改。\n大小正确的区域会变灰，明显冲突的格子会变深。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, started

    local function persist() ctx:save({ state = s, started = started }) end

    local function newGame(n)
        s, started = Core.fresh(ctx.rng, n), ctx.host:now()
        s.sel = nil
        persist()
        self.render()
    end

    local function check()
        if s.done or not Core.solved(s.n, s.val) then return end
        s.done = true
        s.time = math.floor(ctx.host:now() - started)
        if ctx:record("best_" .. s.n, s.time, true) then
            ctx:notify((T("新纪录：%d 分 %d 秒")):format(math.floor(s.time / 60), s.time % 60))
        end
    end

    local function put(v)
        if not s.sel or s.done or s.given[s.sel] ~= 0 then return end
        s.val[s.sel] = v
        check()
        persist()
        self.render()
    end

    function self.render()
        local n = s.n
        local status = T("%d×%d", n, n)
        if s.done then status = status .. T("    完成！") .. (T("    用时 %d:%02d")):format(math.floor(s.time / 60), s.time % 60) end
        local best = ctx:best("best_" .. n)
        if best then status = status .. (T("    最佳 %d:%02d")):format(math.floor(best / 60), best % 60) end
        local nums1, nums2 = {}, {}
        for v = 1, 5 do nums1[#nums1 + 1] = { text = tostring(v), callback = function() put(v) end } end
        for v = 6, 9 do nums2[#nums2 + 1] = { text = tostring(v), callback = function() put(v) end } end
        nums2[#nums2 + 1] = { text = T("清除"), callback = function() put(0) end }
        local size_row = {}
        for _, k in ipairs(SIZES) do
            size_row[#size_row + 1] = { text = k .. "×" .. k, selected = k == n, callback = function() if k ~= n then newGame(k) end end }
        end
        size_row[#size_row + 1] = { text = T("新游戏"), callback = function() newGame(s.n) end }
        ctx:render({
            title = T("填数分区"),
            status = status,
            grid = {
                rows = n, cols = n,
                on_tap = function(r, c) s.sel = (r - 1) * n + c self.render() end,
                cell = function(r, c)
                    local i = (r - 1) * n + c
                    local v = s.val[i]
                    local cell = { text = v ~= 0 and tostring(v) or "", scale = 0.6 }
                    if s.given[i] == 0 then cell.color = "grey" end
                    local st = Core.status(n, s.val, i)
                    if st == "bad" then cell.fill, cell.color = "dark", "white"
                    elseif i == s.sel then cell.fill = "raised"
                    elseif st == "ok" then cell.fill = "grey" end
                    return cell
                end,
            },
            buttons = { nums1, nums2, size_row },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.sol then
            s, started = saved.state, saved.started or ctx.host:now()
        else
            return newGame(6)
        end
        self.render()
    end

    self.put, self.state = put, function() return s end
    return self
end

return M
