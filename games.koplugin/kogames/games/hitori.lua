--[[--
数壹（Hitori）。num 为数字，user：0 空，1 涂黑，2 圈定（确认保留）。
规则：未涂黑的格子行列内数字不重复；涂黑格不相邻；未涂黑格连成一片。
生成：拉丁方 -> 随机选不相邻且不割裂的涂黑位 -> 涂黑格改写成同行/列已有的数字 -> 求解器验证唯一。
--]]
local T = require("kogames.l10n")
local SIZES = { 5, 6, 8 }

local Core = {}
local DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local function neighbors(n, i)
    local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
    local out = {}
    for _, d in ipairs(DIRS) do
        local rr, cc = r + d[1], c + d[2]
        if rr >= 1 and rr <= n and cc >= 1 and cc <= n then out[#out + 1] = (rr - 1) * n + cc end
    end
    return out
end

-- 每个格子同行/同列的其他格子
local PEERS = {}
local function peers(n)
    if not PEERS[n] then
        local p = {}
        for i = 1, n * n do
            local r, c = math.floor((i - 1) / n) + 1, (i - 1) % n + 1
            local l = {}
            for k = 1, n do
                if k ~= c then l[#l + 1] = (r - 1) * n + k end
                if k ~= r then l[#l + 1] = (k - 1) * n + c end
            end
            p[i] = l
        end
        PEERS[n] = p
    end
    return PEERS[n]
end

--- 所有非涂黑（shaded[i] ~= 1）且 mustKeep 的格子是否都连通；connected 只检查 alive 格
local function connected(n, state, strict)
    -- strict：只看已确认保留(2)的格；否则看全部非涂黑格
    local start, total = nil, 0
    for i = 1, n * n do
        if state[i] ~= 1 and (not strict or state[i] == 2) then total = total + 1 start = start or i end
    end
    if not start then return true end
    local seen, stack, got = { [start] = true }, { start }, 1
    while #stack > 0 do
        local i = table.remove(stack)
        for _, j in ipairs(neighbors(n, i)) do
            if not seen[j] and state[j] ~= 1 then
                seen[j] = true
                if not strict or state[j] == 2 then got = got + 1 end
                stack[#stack + 1] = j
            end
        end
    end
    if strict then return got >= total end
    return got == total
end

--- 当前 user 的违规：dup 重复数字的未涂黑格，adj 相邻涂黑格
function Core.analyze(num, n, user)
    local dup, adj = {}, {}
    local pe = peers(n)
    for i = 1, n * n do
        if user[i] ~= 1 then
            for _, j in ipairs(pe[i]) do
                if user[j] ~= 1 and num[j] == num[i] then dup[i] = true break end
            end
        else
            for _, j in ipairs(neighbors(n, i)) do
                if user[j] == 1 then adj[i] = true break end
            end
        end
    end
    local solved = not next(dup) and not next(adj)
    if solved then
        local st = {}
        for i = 1, n * n do st[i] = user[i] == 1 and 1 or 2 end
        solved = connected(n, st, false)
    end
    return { dup = dup, adj = adj, solved = solved }
end

function Core.solved(num, n, user) return Core.analyze(num, n, user).solved end

--- 求解：返回解个数（至多 limit）与第一个解（1 涂黑 2 保留）
function Core.solve(num, n, limit)
    local pe = peers(n)
    local nb = {}
    for i = 1, n * n do nb[i] = neighbors(n, i) end
    local count, first = 0, nil

    local function propagate(a)
        local changed = true
        while changed do
            changed = false
            for i = 1, n * n do
                if a[i] == 1 then
                    for _, j in ipairs(nb[i]) do
                        if a[j] == 1 then return false end
                        if a[j] == 0 then a[j] = 2 changed = true end
                    end
                elseif a[i] == 2 then
                    for _, j in ipairs(pe[i]) do
                        if num[j] == num[i] then
                            if a[j] == 2 then return false end
                            if a[j] == 0 then a[j] = 1 changed = true end
                        end
                    end
                end
            end
        end
        return true
    end

    local function go(a)
        if not propagate(a) then return end
        if not connected(n, a, true) then return end
        local pick
        for i = 1, n * n do
            if a[i] == 0 then
                for _, j in ipairs(pe[i]) do
                    if num[j] == num[i] and a[j] ~= 1 then pick = i break end
                end
                if pick then break end
            end
        end
        pick = pick or (function() for i = 1, n * n do if a[i] == 0 then return i end end end)()
        if not pick then
            if connected(n, a, false) then
                count = count + 1
                first = first or a
            end
            return
        end
        for _, v in ipairs({ 1, 2 }) do
            local h = {}
            for i = 1, n * n do h[i] = a[i] end
            h[pick] = v
            go(h)
            if count >= limit then return end
        end
    end

    local a = {}
    for i = 1, n * n do a[i] = 0 end
    go(a)
    return count, first
end

local function latin(rng, n)
    local rp, cp, sp = {}, {}, {}
    for i = 1, n do rp[i], cp[i], sp[i] = i, i, i end
    rng:shuffle(rp) rng:shuffle(cp) rng:shuffle(sp)
    local g = {}
    for r = 1, n do
        for c = 1, n do g[(r - 1) * n + c] = sp[(rp[r] + cp[c] - 2) % n + 1] end
    end
    return g
end

--- 选涂黑位：互不相邻且剩余连通
local function pickShaded(rng, n, target)
    local st = {}
    for i = 1, n * n do st[i] = 2 end
    local order = {}
    for i = 1, n * n do order[i] = i end
    rng:shuffle(order)
    local cnt = 0
    for _, i in ipairs(order) do
        if cnt >= target then break end
        local ok = true
        for _, j in ipairs(neighbors(n, i)) do if st[j] == 1 then ok = false break end end
        if ok then
            st[i] = 1
            if connected(n, st, false) then cnt = cnt + 1 else st[i] = 2 end
        end
    end
    return st
end

function Core.fresh(rng, n)
    n = n or 5
    local num, shade
    local pe = peers(n)
    for attempt = 1, 60 do
        local sh = pickShaded(rng, n, math.floor(n * n * (0.26 + 0.04 * rng:float())))
        local g = latin(rng, n)
        for i = 1, n * n do
            if sh[i] == 1 then
                local opts = {}
                for _, j in ipairs(pe[i]) do if sh[j] ~= 1 then opts[#opts + 1] = g[j] end end
                g[i] = opts[rng:int(#opts)]
            end
        end
        num, shade = g, sh
        if Core.solve(g, n, 2) == 1 then break end
    end
    local user = {}
    for i = 1, n * n do user[i] = 0 end
    return { n = n, num = num, sol = shade, user = user }
end

local M = { id = "hitori", title = T("数壹"), icon = "grid_view", art = "icon_hitori", tier = "A", desc = T("涂黑重复数字"), help = T("涂黑一些格子，使每行每列中未涂黑的数字都不重复。\n涂黑的格子不能上下左右相邻，且所有未涂黑的格子必须连成一片。\n点按涂黑/取消，长按把格子圈定为「确定保留」（灰底）。\n涂黑格相邻时会变成深灰色提示。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, started, undo

    local function persist() ctx:save({ state = s, started = started, undo = undo }) end

    local function newGame(n)
        s, started, undo = Core.fresh(ctx.rng, n), ctx.host:now(), {}
        persist()
        self.render()
    end

    local function setCell(i, v)
        if s.done then return end
        undo[#undo + 1] = { i, s.user[i] }
        if #undo > 200 then table.remove(undo, 1) end
        s.user[i] = s.user[i] == v and 0 or v
        if Core.solved(s.num, s.n, s.user) then
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
        local an = Core.analyze(s.num, n, s.user)
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
            title = T("数壹"),
            status = status,
            grid = {
                rows = n, cols = n,
                cell = function(r, c)
                    local i = (r - 1) * n + c
                    local v = s.user[i]
                    local text = tostring(s.num[i])
                    if v == 1 then
                        return { text = text, fill = an.adj[i] and "dark" or "black", color = "white", scale = 0.55 }
                    elseif v == 2 then
                        return { text = text, fill = "grey", scale = 0.55 }
                    end
                    return { text = text, scale = 0.55 }
                end,
                on_tap = function(r, c) setCell((r - 1) * n + c, 1) end,
                on_hold = function(r, c) setCell((r - 1) * n + c, 2) end,
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
                    { text = T("清除"), callback = function()
                        for i = 1, n * n do s.user[i] = 0 end
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
            s, started, undo = Core.fresh(ctx.rng, 5), ctx.host:now(), {}
        end
        self.render()
    end

    self.state = function() return s end
    return self
end

return M
