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
        -- 有置顶游戏时每个置顶游戏一个按钮（最多 3 个）加「更多」；没有则只放「玩两把」
        local L = require("kogames.launcher")
        local ok2, pinned = pcall(L.pinned, "moon")
        local btns = {}
        if ok2 then
            for i = 1, math.min(#pinned, 3) do
                local def = pinned[i]
                btns[#btns + 1] = { text = def.title, callback = function() pcall(L.play, "moon", def.id) end }
            end
        end
        if #btns > 0 then btns[#btns + 1] = { text = _("更多"), callback = openLobby } else btns[1] = { text = _("玩两把"), callback = openLobby } end
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan = require("ui/widget/horizontalspan")
        local gap = 8
        local bw = math.floor((w * 0.9 - gap * (#btns - 1)) / #btns)
        local row = HorizontalGroup:new{}
        for i, b in ipairs(btns) do
            if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
            row[#row + 1] = Button:new{ text = b.text, width = bw, callback = b.callback }
        end
        return CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, row }
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
