--[[--
KOReader 插件入口：顶部菜单的游戏标签页打开大厅。游戏逻辑在 kogames/ 下，宿主差异由 kogames.host.* 适配。
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

local TAB_ICON = "kogames"

-- IconWidget 只在固定目录找图标；把插件自带的 SVG 直接登记进它的路径缓存。
local function registerIcon()
    local ok, IconWidget = pcall(require, "ui/widget/iconwidget")
    if not ok then return end
    local i = 1
    while true do
        local name, value = debug.getupvalue(IconWidget.init, i)
        if not name then return end
        if name == "ICONS_PATH" then
            value[TAB_ICON] = PLUGIN_DIR .. "/assets/tab.svg"
            return
        end
        i = i + 1
    end
end

local function buildTab()
    local L = require("kogames.launcher")
    local tab = {
        icon = TAB_ICON,
        remember = false,
        { text = _("全部游戏"), callback = function() L.open("koreader") end },
    }
    for _i, def in ipairs(L.pinned("koreader")) do
        tab[#tab + 1] = { text = def.title, callback = function() L.play("koreader", def.id) end }
    end
    return tab
end

-- 顶部菜单的标签页由排序器按固定表生成，插件菜单只能进已有标签；这里在生成之后补一个独立标签页，
-- 放在月读面板标签（有的话）之后，否则放最前。
function Games:init()
    registerIcon()
    local menu = self.ui.menu
    local build = menu.setUpdateItemTable
    function menu:setUpdateItemTable(...)
        build(self, ...)
        local tabs = self.tab_item_table
        if not tabs then return end
        local at = 1
        for i, t in ipairs(tabs) do
            if t.icon == "appbar.pokeball" then at = i + 1 end
        end
        table.insert(tabs, at, buildTab())
    end
end

return Games
