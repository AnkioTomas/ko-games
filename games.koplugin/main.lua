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

local COLS, ROWS, ROW_H, GAP = 4, 2, 130, 10

local function buildShelf(menu)
    local L = require("kogames.launcher")
    local Screen = require("device").screen
    local function go(fn)
        return function()
            if menu.close_callback then menu.close_callback() end
            pcall(fn)
        end
    end
    local items = {}
    for _i, def in ipairs(L.picks("koreader", COLS * ROWS - 1)) do
        items[#items + 1] = { title = def.title, icon = def.art, callback = go(function() L.play("koreader", def.id) end) }
    end
    items[#items + 1] = { title = _("更多"), icon = PLUGIN_DIR .. "/assets/more.svg", callback = go(function() L.open("koreader") end) }
    local pad = Screen:scaleBySize(GAP)
    local h = Screen:scaleBySize(ROW_H) * ROWS + pad * (ROWS - 1)
    return require("kogames.ui.screen").shelf(items, menu.item_width - pad * 2, h, COLS), pad
end

-- 标签页内容用首页组件同款图标卡片自绘；TouchMenu 只认文字列表，所以在它渲染完空列表后把卡片插进去。
local function patchTouchMenu()
    local TouchMenu = require("ui/widget/touchmenu")
    if TouchMenu._kogames_patched then return end
    TouchMenu._kogames_patched = true
    local original = TouchMenu.updateItems
    TouchMenu.updateItems = function(self, ...)
        original(self, ...)
        if not (self.item_table and self.item_table._kogames) then return end
        local ok, shelf, pad = pcall(buildShelf, self)
        if not ok then return end
        local VerticalGroup = require("ui/widget/verticalgroup")
        local VerticalSpan = require("ui/widget/verticalspan")
        local body = VerticalGroup:new{ align = "left",
            VerticalSpan:new{ width = pad }, shelf, VerticalSpan:new{ width = pad } }
        -- 原生渲染完留下 bar、占位行、页脚边距、页脚；只留首尾，把占位行换成卡片
        for i = #self.item_group - 2, 2, -1 do table.remove(self.item_group, i) end
        table.insert(self.item_group, 2, body)
        self.item_group:resetLayout()
        self.page_info_text:setText("")
        self.page_info_left_chev:showHide(false)
        self.page_info_right_chev:showHide(false)
        local old = self.dimen:copy()
        self.dimen.h = self.item_group:getSize().h + self.bordersize * 2 + self.padding
        require("ui/uimanager"):setDirty("all", function() return "ui", old:combine(self.dimen) end)
    end
end

-- 顶部菜单的标签页由排序器按固定表生成，插件菜单只能进已有标签；这里在生成之后补一个独立标签页，
-- 放在月读面板标签（有的话）之后，否则放最前。
function Games:init()
    registerIcon()
    patchTouchMenu()
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
        table.insert(tabs, at, { icon = TAB_ICON, remember = false, _kogames = true, { text = " " } })
    end
end

return Games
