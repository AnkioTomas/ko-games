--[[--
猜数字（1A2B）。答案是 4 个互不相同的数字；每次提交猜测后给出 xAyB：
A = 数字和位置都对，B = 数字对但位置不对。最多 10 次，可提示一位、认输看答案。
--]]
local T = require("kogames.l10n")
local LEN, MAX_TRIES = 4, 10

local Core = {}

function Core.secret(rng)
    local pool = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }
    rng:shuffle(pool)
    local t = {}
    for i = 1, LEN do t[i] = pool[i] end
    return table.concat(t)
end

--- 返回 A（位置和数字都对）、B（数字对位置不对）。
function Core.score(secret, guess)
    local a, b = 0, 0
    for i = 1, LEN do
        local g = guess:sub(i, i)
        if g == secret:sub(i, i) then a = a + 1
        elseif secret:find(g, 1, true) then b = b + 1 end
    end
    return a, b
end

function Core.validGuess(g)
    if #g ~= LEN or not g:match("^%d+$") then return false end
    for i = 1, LEN do
        if g:find(g:sub(i, i), i + 1, true) then return false end
    end
    return true
end

local M = { id = "mastermind", title = T("猜数字"), icon = "apps", art = "icon_mastermind", tier = "A", desc = T("4 位不重复数字，猜 1A2B"), help = T("答案是 4 个互不相同的数字。用数字键输入 4 位猜测后点提交。\n结果 xAyB：A 表示数字和位置都对，B 表示数字对但位置不对。\n最多猜 10 次；提示会揭示一位数字，认输会显示答案。"), core = Core }

function M.new(ctx)
    local self = {}
    local s

    local function persist() ctx:save({ state = s }) end

    local function fresh()
        s = { secret = Core.secret(ctx.rng), guesses = {}, input = "", reveal = {} }
        persist()
        self.render()
    end

    local function press(d)
        if s.done or #s.input >= LEN then return end
        if s.input:find(d, 1, true) then
            ctx:notify(T("数字不能重复"))
            return
        end
        s.input = s.input .. d
        persist()
        self.render()
    end

    local function delete()
        if s.done or #s.input == 0 then return end
        s.input = s.input:sub(1, -2)
        persist()
        self.render()
    end

    local function submit()
        if s.done or #s.input ~= LEN then return end
        local a, b = Core.score(s.secret, s.input)
        s.guesses[#s.guesses + 1] = { g = s.input, a = a, b = b }
        s.input = ""
        if a == LEN then
            s.done, s.won = true, true
            if not s.hinted and ctx:record("best_tries", #s.guesses, true) then ctx:notify(T("新纪录：%d", #s.guesses)) end
        elseif #s.guesses >= MAX_TRIES then
            s.done = true
        end
        persist()
        self.render()
    end

    local function hint()
        if s.done then return end
        local free = {}
        for i = 1, LEN do if not s.reveal[i] then free[#free + 1] = i end end
        if #free <= 1 then return end
        s.reveal[free[ctx.rng:int(#free)]] = true
        s.hinted = true
        persist()
        self.render()
    end

    local function giveUp()
        if s.done then return end
        s.done = true
        persist()
        self.render()
    end

    function self.render()
        local n = #s.guesses
        local status
        if s.won then status = T("答对了！用了 %d 次", n)
        elseif s.done then status = T("答案是 %s", s.secret)
        else
            local mask = {}
            for i = 1, LEN do mask[i] = s.reveal[i] and s.secret:sub(i, i) or "*" end
            status = T("第 %d / %d 次", n + 1, MAX_TRIES)
            if s.hinted then status = status .. T("    提示 ") .. table.concat(mask) end
        end
        local best = ctx:best("best_tries")
        if best then status = status .. T("    最少 %d", best) end

        local function pad(from, to)
            local row = {}
            for d = from, to do
                local k = d % 10
                row[#row + 1] = { text = tostring(k), enabled = not s.done and #s.input < LEN, callback = function() press(tostring(k)) end }
            end
            return row
        end
        ctx:render({
            title = T("猜数字"),
            status = status,
            grid = {
                rows = MAX_TRIES, cols = 2, gap = true, ratio = 0.3,
                cell = function(r, c)
                    local h = s.guesses[r]
                    if h then
                        if c == 1 then return { text = h.g, fill = "grey", scale = 0.5 } end
                        return { text = h.a .. "A" .. h.b .. "B", fill = h.a == LEN and "dark" or "grey", color = h.a == LEN and "white" or "black", scale = 0.5 }
                    end
                    if r == n + 1 and not s.done and c == 1 then
                        local shown = s.input .. string.rep("_", LEN - #s.input)
                        return { text = shown, scale = 0.5 }
                    end
                    return nil
                end,
            },
            buttons = {
                pad(1, 5),
                pad(6, 10),
                {
                    { text = T("删除"), enabled = not s.done and #s.input > 0, callback = delete },
                    { text = T("提交"), enabled = not s.done and #s.input == LEN, callback = submit },
                },
                {
                    { text = T("提示"), enabled = not s.done, callback = hint },
                    { text = T("认输"), enabled = not s.done, callback = giveUp },
                    { text = T("新游戏"), callback = fresh },
                },
            },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.secret then
            s = saved.state
            s.reveal = s.reveal or {}
            self.render()
        else
            fresh()
        end
    end

    self.state = function() return s end
    self.press, self.submit, self.delete = press, submit, delete
    return self
end

return M
