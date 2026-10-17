--[[--
KOReader 插件入口：主菜单「工具 → 游戏」打开大厅。游戏逻辑在 kogames/ 下，宿主差异由 kogames.host.* 适配。
--]]
local WidgetContainer = require("ui/widget/container/widgetcontainer")

-- KOReader 只在加载插件那一刻把插件目录放进 package.path；之后（菜单回调、月读首页点按）要自己补上。
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end
local _ = require("kogames.l10n")

local Games = WidgetContainer:extend{
    name = "kogames",
    is_doc_only = false,
}

function Games:init()
    self.ui.menu:registerToMainMenu(self)
end

function Games:addToMainMenu(menu_items)
    menu_items.kogames = {
        text = _("游戏"),
        sorting_hint = "tools",
        callback = function() require("kogames.launcher").open("koreader") end,
    }
end

return Games
