--[[--
24 点。四张牌（A~K 对应 1~13），点一个数、点运算符、再点另一个数，二者合成新数（可以是分数）；
最后得到 24 即过关。只发有解的牌，可重选、跳过、提示（显示一种解法），统计过关数和连胜。
--]]
local T = require("kogames.l10n")
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
local OPS = { "+", "-", "×", "÷" }

local Core = {}

local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

--- 有理数 {n, d}，d > 0 且已约分。
function Core.rat(n, d)
    d = d or 1
    if d < 0 then n, d = -n, -d end
    local g = gcd(n, d)
    if g > 1 then n, d = n / g, d / g end
    return { n = n, d = d }
end

--- 运算；除数为 0 返回 nil。
function Core.apply(op, a, b)
    if op == "+" then return Core.rat(a.n * b.d + b.n * a.d, a.d * b.d)
    elseif op == "-" then return Core.rat(a.n * b.d - b.n * a.d, a.d * b.d)
    elseif op == "×" then return Core.rat(a.n * b.n, a.d * b.d)
    elseif op == "÷" then
        if b.n == 0 then return nil end
        return Core.rat(a.n * b.d, a.d * b.n)
    end
end

function Core.fmt(r)
    if r.d == 1 then return tostring(r.n) end
    return r.n .. "/" .. r.d
end

function Core.isTarget(r) return r.d == 1 and r.n == 24 end

local function search(list)
    if #list == 1 then
        if Core.isTarget(list[1].v) then return list[1].e end
        return nil
    end
    for i = 1, #list - 1 do
        for j = i + 1, #list do
            local rest = {}
            for k = 1, #list do if k ~= i and k ~= j then rest[#rest + 1] = list[k] end end
            local a, b = list[i], list[j]
            for _, o in ipairs({ { "+", a, b }, { "×", a, b }, { "-", a, b }, { "-", b, a }, { "÷", a, b }, { "÷", b, a } }) do
                local v = Core.apply(o[1], o[2].v, o[3].v)
                if v then
                    rest[#rest + 1] = { v = v, e = "(" .. o[2].e .. o[1] .. o[3].e .. ")" }
                    local sol = search(rest)
                    if sol then return sol end
                    rest[#rest] = nil
                end
            end
        end
    end
end

--- 求解四个整数，返回算式字符串（外层括号已去掉）或 nil。
function Core.solve(nums)
    local list = {}
    for i, v in ipairs(nums) do list[i] = { v = Core.rat(v), e = tostring(v) } end
    local e = search(list)
    if e and e:sub(1, 1) == "(" then e = e:sub(2, -2) end
    return e
end

function Core.deal(rng)
    local nums
    repeat
        nums = {}
        for i = 1, 4 do nums[i] = rng:int(13) end
    until Core.solve(nums)
    return nums
end

--- items = { {n=, d=, card=rank 或 nil}, ... }
local function startItems(nums)
    local items = {}
    for i, v in ipairs(nums) do items[i] = { n = v, d = 1, card = RANKS[v] } end
    return items
end

Core.startItems = startItems

local M = { id = "twentyfour", title = T("24点"), icon = "apps", tier = "A", desc = T("四张牌算出 24"), help = T("用四张牌上的数（A=1，J=11，Q=12，K=13）通过加减乘除算出 24。\n先点一个数，再点运算符，最后点另一个数，它们会合成一个新数（可能是分数）。\n只剩一个数且等于 24 即过关。\n重选：重新开始本题；跳过：换一题；提示：显示一种解法。"), core = Core }

function M.new(ctx)
    local self = {}
    local s, undo

    local function persist() ctx:save({ state = s, undo = undo }) end

    local function copyItems(items)
        local t = {}
        for i, it in ipairs(items) do t[i] = { n = it.n, d = it.d, card = it.card } end
        return t
    end

    local function newHand(keepStreak)
        s = { nums = Core.deal(ctx.rng), streak = keepStreak and s and s.streak or 0 }
        s.items = startItems(s.nums)
        undo = {}
        persist()
        self.render()
    end

    local function restart()
        s.items, s.sel, s.op, s.hint, s.done = startItems(s.nums), nil, nil, nil, nil
        undo = {}
        persist()
        self.render()
    end

    local function tapItem(idx)
        if s.done then return end
        local it = s.items[idx]
        if not it then return end
        if s.sel == idx then
            s.sel, s.op = nil, nil
        elseif not s.sel or not s.op then
            s.sel = idx
        else
            local a, b = s.items[s.sel], it
            local v = Core.apply(s.op, a, b)
            if not v then
                ctx:notify(T("除数不能为 0"))
                s.sel, s.op = nil, nil
            else
                undo[#undo + 1] = copyItems(s.items)
                local rest = {}
                for k, x in ipairs(s.items) do
                    if k ~= s.sel and k ~= idx then rest[#rest + 1] = x end
                end
                table.insert(rest, math.min(s.sel, idx), { n = v.n, d = v.d })
                s.items, s.sel, s.op = rest, nil, nil
                if #rest == 1 and Core.isTarget(rest[1]) then
                    s.done = true
                    s.streak = (s.streak or 0) + 1
                    local total = (ctx:best("solved") or 0) + 1
                    ctx:record("solved", total)
                    ctx:record("streak", s.streak)
                end
            end
        end
        persist()
        self.render()
    end

    local function setOp(op)
        if s.done or not s.sel then return end
        s.op = s.op ~= op and op or nil
        persist()
        self.render()
    end

    function self.render()
        local status
        if s.done then
            status = T("完成！")
        elseif s.hint then
            status = T("提示：") .. s.hint
        elseif #s.items == 1 then
            status = T("得到 %s，不是 24，请重选或撤销", Core.fmt(s.items[1]))
        else
            status = T("目标 24")
        end
        status = status .. T("    连胜 %d", s.streak or 0)
        local best = ctx:best("solved")
        if best then status = status .. T("    已解 %d", best) end
        local ops = {}
        for _, op in ipairs(OPS) do
            ops[#ops + 1] = { text = op, selected = s.op == op, enabled = not s.done and s.sel ~= nil, callback = function() setOp(op) end }
        end
        ctx:render({
            title = T("24点"),
            status = status,
            grid = {
                rows = 1, cols = 4, gap = true, slots = true,
                cell = function(_, c)
                    local it = s.items[c]
                    if not it then return nil end
                    local text = it.card or Core.fmt(it)
                    return { text = text, fill = s.sel == c and "dark" or "grey", color = s.sel == c and "white" or "black", scale = #text > 3 and 0.4 or 0.55 }
                end,
                on_tap = function(_, c) tapItem(c) end,
            },
            buttons = {
                ops,
                {
                    { text = T("撤销"), enabled = #undo > 0 and not s.done, callback = function()
                        s.items, s.sel, s.op = table.remove(undo), nil, nil
                        persist()
                        self.render()
                    end },
                    { text = T("重选"), callback = restart },
                    { text = T("提示"), enabled = not s.done, callback = function()
                        s.hint = Core.solve(s.nums)
                        s.streak = 0
                        persist()
                        self.render()
                    end },
                    { text = s.done and T("下一题") or T("跳过"), callback = function() newHand(s.done) end },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.items then
            s, undo = saved.state, saved.undo or {}
        else
            newHand(false)
            return
        end
        self.render()
    end

    self.state = function() return s end
    self.tap = tapItem
    self.op = setOp
    return self
end

return M
