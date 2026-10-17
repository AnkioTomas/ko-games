--[[--
大厅：按分级列出游戏，每页最多 PER_PAGE 个，两列。
--]]
local T = require("kogames.l10n")
local Registry = require("kogames.registry")

local Lobby = {}
Lobby.__index = Lobby

local PER_PAGE = 8

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
    for i = (self.page - 1) * PER_PAGE + 1, math.min(#defs, self.page * PER_PAGE) do
        local def = defs[i]
        if def.tier ~= last_tier then
            last_tier = def.tier
            items[#items + 1] = { label = Registry.TIERS[def.tier] or def.tier }
        end
        items[#items + 1] = { title = def.title, caption = def.desc, icon = def.art, callback = function() self:play(def) end }
    end
    local buttons = {}
    if pages > 1 then
        buttons[#buttons + 1] = {
            { text = T("上一页"), enabled = self.page > 1, callback = function() self.page = self.page - 1 self:render() end },
            { text = ("%d / %d"):format(self.page, pages) },
            { text = T("下一页"), enabled = self.page < pages, callback = function() self.page = self.page + 1 self:render() end },
        }
    end
    self.host:showScreen({
        title = T("游戏"),
        status = T("选一个玩吧"),
        cards = { cols = 2, items = items },
        buttons = buttons,
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
