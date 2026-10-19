--[[--
大厅：按分级列出游戏，每页最多 PER_PAGE 个，两列。
--]]
local T = require("kogames.l10n")
local Registry = require("kogames.registry")

local Lobby = {}
Lobby.__index = Lobby

local PER_PAGE = 5

function Lobby.new(host)
    return setmetatable({ host = host, page = 1 }, Lobby)
end

function Lobby:show()
    Lobby.current = self
    self:render()
    return self
end

function Lobby:pinned()
    local set = {}
    for _, id in ipairs(self.host:getSetting("pinned", {})) do set[id] = true end
    return set
end

function Lobby:togglePin(id)
    local set = self:pinned()
    set[id] = not set[id] or nil
    local list = {}
    for _, d in ipairs(Registry.all()) do if set[d.id] then list[#list + 1] = d.id end end
    self.host:setSetting("pinned", list)
    self.page = 1
end

-- 置顶的游戏排最前，其余保持注册顺序
function Lobby:sorted()
    local set, top, rest = self:pinned(), {}, {}
    for _, d in ipairs(Registry.all()) do
        table.insert(set[d.id] and top or rest, d)
    end
    for _, d in ipairs(rest) do top[#top + 1] = d end
    return top
end

function Lobby:render()
    local defs = self:sorted()
    local pages = math.max(1, math.ceil(#defs / PER_PAGE))
    self.page = math.min(self.page, pages)
    local items = {}
    for i = (self.page - 1) * PER_PAGE + 1, math.min(#defs, self.page * PER_PAGE) do
        local def = defs[i]
        items[#items + 1] = { title = def.title, caption = def.desc, icon = def.art, callback = function() self:play(def) end,
            pin = { on = self:pinned()[def.id], callback = function() self:togglePin(def.id) self:render() end } }
    end
    self.host:showScreen({
        title = T("游戏"),
        cards = { cols = 1, items = items },
        pager = { page = self.page, pages = pages,
            on_prev = function() self.page = self.page - 1 self:render() end,
            on_next = function() self.page = self.page + 1 self:render() end },
        on_close = function() Lobby.current = nil end,
    })
end

function Lobby:play(def)
    Registry.launch(self.host, def, function() self:render() end)
end

function Lobby:close()
    Lobby.current = nil
    self.host:closeScreen()
end

return Lobby
