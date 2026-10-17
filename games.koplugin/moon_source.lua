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
    heightRange = function() return { height = 150 } end,
    build = function(_ctx, w, h)
        local L = require("kogames.launcher")
        local items = {}
        -- 置顶的游戏优先（最多 3 个），不够用热门游戏补齐
        local ok, picks = pcall(L.pinned, "moon")
        picks = ok and picks or {}
        local seen = {}
        for _i, d in ipairs(picks) do seen[d.id] = true end
        for _i, d in ipairs(require("kogames.registry").all()) do
            if #picks >= 3 then break end
            if not seen[d.id] then picks[#picks + 1] = d end
        end
        for i = 1, math.min(#picks, 3) do
            local def = picks[i]
            items[#items + 1] = { title = def.title, icon = def.art, callback = function() pcall(L.play, "moon", def.id) end }
        end
        items[#items + 1] = { title = _("更多"), icon = PLUGIN_DIR .. "/assets/more.svg", callback = openLobby }
        return require("kogames.ui.screen").shelf(items, w, h)
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
