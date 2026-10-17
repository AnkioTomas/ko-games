--[[--
宿主抽象。游戏只通过 host 访问外部世界：
  host:showScreen(view)   再次调用即刷新；view 见 ui/screen.lua 头注释
  host:closeScreen()
  host:schedule(seconds, fn) -> 句柄 / host:unschedule(句柄)
  host:load(id) -> table|nil / host:save(id, table)   每个游戏一份存档
  host:getSetting(key, default) / host:setSetting(key, value)
  host:notify(text)
  host:now() -> 秒
--]]
local Interface = {}

Interface.METHODS = {
    "showScreen", "closeScreen", "schedule", "unschedule",
    "load", "save", "getSetting", "setSetting", "notify", "now",
}

function Interface.check(host)
    for _, m in ipairs(Interface.METHODS) do
        if type(host[m]) ~= "function" then error("kogames host missing method: " .. m) end
    end
    return host
end

return Interface
