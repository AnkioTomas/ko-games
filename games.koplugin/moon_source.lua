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

local widget = {
    id = "entry", -- 月读补成 ext.kogames.entry
    title = _("游戏"),
    icon = "sports_esports",
    heightRange = function() return { height = 110 } end,
    build = function(_ctx, w, h)
        local ok, Button = pcall(require, "ui.themes.widgets.button")
        if not ok then Button = require("ui/widget/button") end
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom = require("ui/geometry")
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            Button:new{ text = _("玩两把"), width = math.floor(w * 0.8), callback = openLobby },
        }
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
