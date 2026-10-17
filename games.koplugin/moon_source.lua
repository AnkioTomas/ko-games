--[[--
月读扩展描述：不是书源，只在月读首页加一个「游戏」入口组件，并在快捷面板加一个动作，点一下打开游戏大厅。
契约见月读 examples/moonwidget-demo.koplugin/moon_source.lua（api = 1，id = ext.<name>）。
没装月读时 KOReader 不会读本文件，插件照常从主菜单启动。
--]]
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end
local _ = require("kogames.l10n")

local ID = "ext.kogames"

local function openLobby()
    require("kogames.launcher").open("moon")
end

local COLS, ROW_H, GAP = 4, 130, 10

local function rows()
    local n = math.floor(tonumber(require("utils.settings").getSource(ID).rows) or 1)
    return math.max(1, math.min(3, n))
end

local widget = {
    id = "entry", -- 月读补成 ext.kogames.entry
    title = _("游戏"),
    icon = "sports_esports",
    heightRange = function() return { height = rows() * ROW_H + (rows() - 1) * GAP } end,
    build = function(_ctx, w, h)
        local L = require("kogames.launcher")
        -- 置顶的游戏优先，不够用热门游戏补齐；最后一格固定是「更多」
        local picks = L.picks("moon", rows() * COLS - 1)
        local items = {}
        for i = 1, #picks do
            local def = picks[i]
            items[#items + 1] = { title = def.title, icon = def.art, callback = function() pcall(L.play, "moon", def.id) end }
        end
        items[#items + 1] = { title = _("更多"), icon = PLUGIN_DIR .. "/assets/more.svg", callback = openLobby }
        return require("kogames.ui.screen").shelf(items, w, h, COLS)
    end,
    settings = function(desktop, _id)
        local Settings = require("utils.settings")
        local items = { { buttons = {} } }
        for n = 1, 3 do
            table.insert(items[1].buttons, {
                text = (rows() == n and "✓ " or "") .. string.format(_("%d 行"), n),
                callback = function()
                    Settings.getSource(ID).rows = n
                    Settings.saveSource(ID)
                    desktop:onEvent("home_refresh")
                end,
            })
        end
        require("ui.themes.widgets.sheet"):new{ title = _("游戏"), items = items }:show()
    end,
}

return {
    api = 1,
    id = ID,
    provides = {
        source = false,
        home_widgets = { widget },
        features = { panel = { actions = function()
            return { {
                id = "play", scope = "desktop", title = _("游戏"), icon = "sports_esports",
                run = function() pcall(openLobby) end,
            } }
        end } },
    },
}
