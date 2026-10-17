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
    view.on_close = view.on_close or function() if self.on_closed then self.on_closed() end end
    view.back = view.back or function() self:exit() end
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
