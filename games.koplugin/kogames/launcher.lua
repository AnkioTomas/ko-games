--[[--
启动器：保证全局只有一个游戏界面（菜单、月读首页入口都走这里）。
--]]
local M = {}

local hosts = {}

local function hostFor(kind)
    kind = kind or "koreader"
    for _, h in pairs(hosts) do h:closeScreen() end
    local host = hosts[kind] or require("kogames.host." .. kind).new()
    hosts[kind] = host
    return host
end

function M.open(kind)
    return require("kogames.lobby").new(hostFor(kind)):show()
end

--- 置顶的游戏定义列表（菜单、月读首页入口用）
function M.pinned(kind)
    kind = kind or "koreader"
    local host = hosts[kind] or require("kogames.host." .. kind).new()
    hosts[kind] = host
    local Registry = require("kogames.registry")
    local out = {}
    for _, id in ipairs(host:getSetting("pinned", {})) do
        local def = Registry.get(id)
        if def then out[#out + 1] = def end
    end
    return out
end

--- 卡片列表用：置顶游戏优先，不够用注册表顺序补齐到 count 个。
function M.picks(kind, count)
    local ok, out = pcall(M.pinned, kind)
    out = ok and out or {}
    local seen = {}
    for _i, d in ipairs(out) do seen[d.id] = true end
    for _i, d in ipairs(require("kogames.registry").all()) do
        if #out >= count then break end
        if not seen[d.id] then out[#out + 1] = d end
    end
    while #out > count do out[#out] = nil end
    return out
end

--- 直接打开某个游戏，返回即关闭界面
function M.play(kind, id)
    local def = require("kogames.registry").get(id)
    if not def then return end
    return require("kogames.registry").launch(hostFor(kind), def, nil)
end

return M
