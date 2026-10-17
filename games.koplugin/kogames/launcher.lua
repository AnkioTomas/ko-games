--[[--
启动器：保证全局只有一个游戏界面（菜单、月读首页入口都走这里）。
--]]
local M = {}

local hosts = {}

function M.open(kind)
    kind = kind or "koreader"
    for _, h in pairs(hosts) do h:closeScreen() end
    local host = hosts[kind] or require("kogames.host." .. kind).new()
    hosts[kind] = host
    return require("kogames.lobby").new(host):show()
end

return M
