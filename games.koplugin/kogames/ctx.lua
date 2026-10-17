--[[--
游戏会话上下文：游戏核心只通过它渲染、存档、记最佳成绩，便于 headless 测试。
  ctx:render(view)      显示/刷新界面
  ctx:exit()            回到大厅（没有大厅时关闭）
  ctx:load() / ctx:save(t)    本游戏存档
  ctx:record(key, value, lower_better) -> 是否刷新纪录；ctx:best(key)
  ctx:notify(text)
  ctx.rng               随机数，种子取自当前时间
--]]
local Rng = require("kogames.rng")

local Ctx = {}
Ctx.__index = Ctx

function Ctx.new(host, def, exit)
    return setmetatable({
        host = host, def = def, id = def.id, _exit = exit,
        rng = Rng.new(math.floor(host:now()) + math.floor(os.clock() * 1000)),
    }, Ctx)
end

function Ctx:render(view)
    view.assets = view.assets or self.def.assets
    view.on_close = view.on_close or function() if self.on_closed then self.on_closed() end end
    view.back = view.back or function() self:exit() end
    local help_pending
    if self.def.help and not view.help then
        view.help = { title = self.def.title, text = self.def.help }
        local key = "help_seen_" .. self.id
        if not self.host:getSetting(key) then
            self.host:setSetting(key, true)
            help_pending = true -- 第一次进入自动弹出玩法
        end
        view.help_now = help_pending
    end
    -- 有设置的游戏：首次进入弹出设置弹窗（含玩法），确认后开新局
    if view.settings and help_pending then
        view.help_now, view.settings_now = nil, true
    end
    if view.settings and view.buttons then
        -- 标了 menu 的按钮（撤销、新游戏等）移进设置弹窗
        local rows, actions = {}, {}
        for _, row in ipairs(view.buttons) do
            local keep = {}
            for _, b in ipairs(row) do table.insert(b.menu and actions or keep, b) end
            if #keep > 0 or row.label then rows[#rows + 1] = #keep > 0 and keep or row end
        end
        view.buttons = rows
        view.settings.actions = actions
    end
    self.host:showScreen(view)
end

function Ctx:exit()
    if self.on_closed then self.on_closed() end
    if self._exit then self._exit() else self.host:closeScreen() end
end

function Ctx:load() return self.host:load(self.id) end
function Ctx:save(t) self.host:save(self.id, t) end

function Ctx:best(key)
    local s = self.host:load("stats_" .. self.id)
    return s and s[key]
end

function Ctx:record(key, value, lower_better)
    local s = self.host:load("stats_" .. self.id) or {}
    local old = s[key]
    if old ~= nil and ((lower_better and value >= old) or (not lower_better and value <= old)) then
        return false
    end
    s[key] = value
    self.host:save("stats_" .. self.id, s)
    return true
end

function Ctx:notify(text) self.host:notify(text) end

return Ctx
