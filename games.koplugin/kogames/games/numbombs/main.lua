--[[--
数字炸弹。1–99 里藏着一个炸弹数字，你和电脑轮流报一个在当前范围内的数字：
没猜中就把范围缩小（比炸弹大的作为新上界，小的作为新下界），猜中炸弹的一方输。
--]]
local T = require("kogames.l10n")
local MAX = 99

local Core = {}

function Core.fresh(rng) return { bomb = rng:int(MAX), lo = 0, hi = MAX + 1, turn = 1, rounds = 0 } end

--- 猜 n：返回 "boom" 或 "ok"，范围外无效返回 nil。
function Core.guess(s, n)
    if s.over or n <= s.lo or n >= s.hi then return nil end
    s.rounds = s.rounds + 1
    if n == s.bomb then
        s.over, s.loser = true, s.turn
        return "boom"
    end
    if n < s.bomb then s.lo = n else s.hi = n end
    s.turn = 3 - s.turn
    return "ok"
end

--- 电脑在范围内随机选，范围缩到一个数时只能硬着头皮选它。
function Core.aiPick(s, rng)
    local count = s.hi - s.lo - 1
    if count <= 0 then return nil end
    return s.lo + 1 + rng:int(count) - 1
end

local M = { id = "numbombs", title = T("数字炸弹"), icon = "apps", tier = "A", desc = T("别猜中藏起来的数字"), help = T("1 到 99 里藏着一个炸弹数字。你和电脑轮流点一个数字：没猜中，范围就会缩小（小于炸弹的变成新的下限，大于炸弹的变成新的上限）；谁猜中炸弹，谁就输。\n只有白底的数字还能点，灰色的已经排除。范围越小越要小心！"), core = Core }

function M.new(ctx)
    local self = {}
    local s

    local function persist() ctx:save({ state = s }) end

    local function fresh()
        s = Core.fresh(ctx.rng)
        persist()
        self.render()
    end

    local function aiTurn()
        local n = Core.aiPick(s, ctx.rng)
        if n then Core.guess(s, n) end
    end

    local function tap(r, c)
        if s.over or s.turn ~= 1 then return end
        local n = (r - 1) * 10 + c
        if n > MAX or not Core.guess(s, n) then return end
        if not s.over then aiTurn() end
        if s.over then
            local stats = ctx.host:load("stats_" .. ctx.id) or {}
            if s.loser == 2 then ctx:record("wins", (stats.wins or 0) + 1) end
        end
        persist()
        self.render()
    end

    function self.render()
        local status
        if s.over then
            status = (s.loser == 1 and T("你踩到炸弹了！") or T("电脑踩到炸弹，你赢了！")) .. T("    炸弹是 %d", s.bomb)
        else
            status = T("范围 %d – %d", s.lo + 1, s.hi - 1)
        end
        local wins = ctx:best("wins")
        if wins then status = status .. T("    胜场 %d", wins) end
        ctx:render({
            title = T("数字炸弹"),
            status = status,
            grid = {
                rows = 10, cols = 10, gap = true,
                cell = function(r, c)
                    local n = (r - 1) * 10 + c
                    if n > MAX then return nil end
                    if s.over and n == s.bomb then return { text = tostring(n), fill = "black", scale = 0.4 } end
                    if n <= s.lo or n >= s.hi then return { text = tostring(n), fill = "dark", color = "white", scale = 0.4 } end
                    return { text = tostring(n), scale = 0.4 }
                end,
                on_tap = tap,
            },
            buttons = { { { text = T("新游戏"), callback = fresh } } },
        })
    end

    function self.start()
        local saved = ctx:load()
        if saved and saved.state and saved.state.bomb then
            s = saved.state
            self.render()
        else
            fresh()
        end
    end

    self.state = function() return s end
    self.tap = tap
    return self
end

return M
