--[[--
大厅：按分级列出游戏，每页最多 PER_PAGE 个，两列。
--]]
local T = require("kogames.l10n")
local Registry = require("kogames.registry")

local Lobby = {}
Lobby.__index = Lobby

local PER_PAGE = 6

function Lobby.new(host)
    return setmetatable({ host = host, page = 1 }, Lobby)
end

function Lobby:show()
    Lobby.current = self
    self:render()
    return self
end

function Lobby:render()
    local defs = Registry.all()
    local pages = math.max(1, math.ceil(#defs / PER_PAGE))
    self.page = math.min(self.page, pages)
    local items, last_tier = {}, nil
    local multi = false
    for _, d in ipairs(defs) do if d.tier ~= defs[1].tier then multi = true end end
    for i = (self.page - 1) * PER_PAGE + 1, math.min(#defs, self.page * PER_PAGE) do
        local def = defs[i]
        if multi and def.tier ~= last_tier then
            items[#items + 1] = { label = Registry.TIERS[def.tier] or def.tier }
        end
        last_tier = def.tier
        items[#items + 1] = { title = def.title, caption = def.desc, icon = def.art, callback = function() self:play(def) end }
    end
    self.host:showScreen({
        title = T("游戏"),
        cards = { cols = 2, items = items },
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
