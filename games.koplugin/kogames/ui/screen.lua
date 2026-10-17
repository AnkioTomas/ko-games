--[[--
通用全屏界面：标题栏 + 状态行 + 可选棋盘 + 按钮行。游戏核心只产出 view 表：

view = {
  title   = "2048",
  status  = "得分 120",                       -- 可选，一行
  grid    = {                                  -- 可选
    rows = 4, cols = 4,
    cell = function(r, c) return { text = "2", fill = "grey"|"dark"|"black", color = "white", shape = "black"|"white", scale = 0.5 } end,
    on_tap = function(r, c) end, on_hold = function(r, c) end,
    thick = 3,                                 -- 可选：每 3 格画粗线（数独）
    ratio = 0.7,                               -- 可选：格高/格宽，默认 1（方格）；设置后按整屏宽高分别适配
  },
  on_swipe = function(dir) end,                -- dir = "north"|"south"|"east"|"west"
  buttons = { { {text=, callback=, enabled=, selected=}, ... } 一行, { label = "分组标题" } },
  pager   = { page=, pages=, on_prev=fn, on_next=fn },   -- 翻页条（主题 pager，无月读时回落为按钮）
  cards   = { cols = 2, items = { {title=, caption=, callback=, pin={on=, callback=}} | {label=} } },   -- 大厅卡片
  back    = function() end,                    -- 有则标题栏左侧是返回，否则右侧是关闭
  on_close = function() end,                   -- 点右上角 × 或返回键关闭时
}
--]]
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local function px(n) return Screen:scaleBySize(n) end

local FILLS = {
    grey = Blitbuffer.Color8(0xE0),
    dark = Blitbuffer.Color8(0x88),
    black = Blitbuffer.COLOR_BLACK,
}
local TEXT_COLORS = {
    white = Blitbuffer.COLOR_WHITE,
    grey = Blitbuffer.Color8(0x66),
    black = Blitbuffer.COLOR_BLACK,
}
local RULE = Blitbuffer.Color8(0xA0)

-- 组件工具箱：有月读主题就用主题组件（标题栏、按钮、卡片），每个组件单独兜底到原生控件 ---------

local function tap(child, w, h, cb)
    local box = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = w, h = h }, child }
    box.ges_events = { TapKG = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } } }
    function box:onTapKG() if cb then cb() end return true end
    return box
end

local function kit()
    local k = {
        moon = false, px = px, ink = Blitbuffer.COLOR_BLACK, muted = Blitbuffer.Color8(0x66),
        btn_h = px(52), title_h = px(52),
    }
    local native = {}
    local function face(role)
        return Font:getFace("cfont", role == "caption" and 15 or (role == "title" and 22 or 19))
    end
    function native.line(role, text, w, muted, bold)
        return TextWidget:new{ text = text, face = face(role), bold = bold, max_width = w, fgcolor = muted and k.muted or k.ink }
    end
    function native.button(text, w, cb, opts)
        local selected = opts and opts.selected
        local enabled = not (opts and opts.enabled == false)
        local b = require("ui/widget/button"):new{ text = text, width = w, enabled = enabled and cb ~= nil, callback = cb,
            bordersize = selected and px(3) or px(1), radius = px(6), text_font_size = 19 }
        return b
    end
    function native.title(w, title, left, right)
        local sd = left or right
        local slot = k.title_h
        local function side(d)
            if not d then return HorizontalSpan:new{ width = slot } end
            return tap(CenterContainer:new{ dimen = Geom:new{ w = slot, h = slot },
                TextWidget:new{ text = d.text, face = face("title"), fgcolor = k.ink } }, slot, slot, d.callback)
        end
        return VerticalGroup:new{ align = "left",
            HorizontalGroup:new{ align = "center", side(left),
                CenterContainer:new{ dimen = Geom:new{ w = w - slot * 2, h = slot },
                    TextWidget:new{ text = title or "", face = face("title"), bold = true, max_width = w - slot * 2 } },
                side(right) },
            require("ui/widget/linewidget"):new{ dimen = Geom:new{ w = w, h = px(1) }, background = RULE } }
    end
    function native.card(child, w, h)
        return FrameContainer:new{ width = w, height = h, padding = 0, bordersize = px(1), radius = px(8), color = RULE,
            background = Blitbuffer.COLOR_WHITE, CenterContainer:new{ dimen = Geom:new{ w = w - px(2), h = h - px(2) }, child } }
    end
    for name, fn in pairs(native) do k[name] = fn end

    local ok, Theme = pcall(require, "ui.themes")
    local t = ok and Theme and select(2, pcall(Theme.current))
    if not (ok and type(t) == "table") then return k end
    k.moon = true
    k.px = Theme.px
    pcall(function()
        k.ink, k.muted = Blitbuffer.Color8(t.color.ink), Blitbuffer.Color8(t.color.muted)
        k.btn_h = Theme.px(t.control.height) + px(12)
        k.title_h = Theme.px(t.control.height) + Theme.px(t.space.sm) * 2
    end)
    local function guarded(name, fn)
        k[name] = function(...)
            local ok2, r = pcall(fn, ...)
            if ok2 and r then return r end
            return native[name](...)
        end
    end
    guarded("line", function(role, text, w, muted, bold)
        return require("ui.themes.widgets.text").line(role, text, { width = w, color = muted and t.color.muted or nil, bold = bold })
    end)
    guarded("button", function(text, w, cb, opts)
        opts = opts or {}
        return require("ui.themes.widgets.button"):new{ text = text, width = w, height = k.btn_h, callback = cb,
            variant = opts.selected and "primary" or "normal", enabled = opts.enabled ~= false and cb ~= nil }
    end)
    guarded("title", function(w, title, left, right)
        return require("ui.themes.widgets.titlebar").widget{ width = w, title = title or "",
            left_icon = left and left.icon, left_callback = left and left.callback,
            right_icon = right and right.icon, right_callback = right and right.callback }
    end)
    guarded("card", function(child, w, h)
        local Box = require("ui.themes.widgets.box")
        local style = {}
        for kk, vv in pairs(t.card) do style[kk] = vv end
        style.border = math.max(style.border or 0, 1)
        style.border_color = style.border_color or 0x99
        style.shadow = 0
        return Box:new{ style = style, width = w, height = h,
            CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, child } }
    end)
    return k
end


-- SVG 素材：按 名称|边长 缓存渲染结果；渲染失败返回 nil，调用方退回文字
local ASSETS = (debug.getinfo(1, "S").source:match("^@(.*)/kogames/ui/screen%.lua$") or ".") .. "/assets/"
local icon_cache = {}
local function loadIcon(name, size)
    local key = name .. "|" .. size
    local hit = icon_cache[key]
    if hit == nil then
        local ok, bb = pcall(function()
            return require("ui/renderimage"):renderSVGImageFile(ASSETS .. name .. ".svg", size, size)
        end)
        hit = ok and bb or false
        icon_cache[key] = hit
    end
    return hit or nil
end

local function paintIcon(bb, name, x, y, size)
    local img = loadIcon(name, size)
    if not img then return false end
    bb:alphablitFrom(img, x + math.floor((size - img:getWidth()) / 2), y + math.floor((size - img:getHeight()) / 2),
        0, 0, img:getWidth(), img:getHeight())
    return true
end

local OverlapGroup = require("ui/widget/overlapgroup")
local IconWidget = Widget:extend{ name = nil, size = 48 }
function IconWidget:init() self.dimen = Geom:new{ w = self.size, h = self.size } end
function IconWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    paintIcon(bb, self.name, x, y, self.size)
end

-- 棋盘 ------------------------------------------------------------------

local Board = Widget:extend{}

function Board:init()
    local g = self.grid
    local ratio = g.ratio or 1
    local w, h = self.width or self.size, self.height or self.size
    self.cs = math.max(1, math.floor(math.min(w / g.cols, h / (g.rows * ratio))))
    self.ch = math.max(1, math.floor(self.cs * ratio))
    self.dimen = Geom:new{ w = self.cs * g.cols, h = self.ch * g.rows }
    self.texts = {}
end

function Board:text(str, size, color)
    local key = str .. "|" .. size .. "|" .. color
    local w = self.texts[key]
    if not w then
        w = TextWidget:new{ text = str, face = Font:getFace("cfont", size), fgcolor = TEXT_COLORS[color] or TEXT_COLORS.black, bold = true }
        self.texts[key] = w
    end
    return w
end

function Board:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local g, cs, ch = self.grid, self.cs, self.ch
    local m = math.min(cs, ch)
    local ink = Blitbuffer.COLOR_BLACK
    local white = Blitbuffer.COLOR_WHITE
    local gap = g.gap and math.max(2, px(3)) or 0
    local radius = g.gap and math.floor(m * 0.12) or 0
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, g.gap and Blitbuffer.Color8(0xF2) or white)
    local go = g.style == "go"
    if go then
        local half = math.floor(cs / 2)
        local lw = math.max(1, math.floor(px(1)))
        for i = 0, g.cols - 1 do
            local edge = i == 0 or i == g.cols - 1
            bb:paintRect(x + i * cs + half - (edge and 1 or 0), y + half, edge and lw + 2 or lw, (g.rows - 1) * cs + 1, ink)
        end
        for i = 0, g.rows - 1 do
            local edge = i == 0 or i == g.rows - 1
            bb:paintRect(x + half, y + i * cs + half - (edge and 1 or 0), (g.cols - 1) * cs + 1, edge and lw + 2 or lw, ink)
        end
        for _, p in ipairs(g.stars or {}) do
            bb:paintCircle(x + (p[2] - 1) * cs + half, y + (p[1] - 1) * cs + half, math.max(3, math.floor(cs * 0.09)), ink)
        end
    end
    for r = 1, g.rows do
        for c = 1, g.cols do
            local cell = g.cell(r, c)
            local cx, cy = x + (c - 1) * cs, y + (r - 1) * ch
            if cell then
                if cell.fill and FILLS[cell.fill] and not go then
                    if g.gap then
                        bb:paintRoundedRect(cx + gap, cy + gap, cs - gap * 2, ch - gap * 2, FILLS[cell.fill], radius)
                    else
                        bb:paintRect(cx, cy, cs, ch, FILLS[cell.fill])
                    end
                end
                if cell.fill == "raised" then
                    local e = math.max(2, math.floor(m * 0.07))
                    bb:paintRect(cx, cy, cs, ch, Blitbuffer.Color8(0xB8))
                    bb:paintRect(cx, cy, cs - e, e, white)
                    bb:paintRect(cx, cy, e, ch - e, white)
                    bb:paintRect(cx + e, cy + ch - e, cs - e, e, Blitbuffer.Color8(0x66))
                    bb:paintRect(cx + cs - e, cy + e, e, ch - e, Blitbuffer.Color8(0x66))
                end
                if cell.icon then
                    local isz = math.floor(m * (cell.icon_scale or 0.8))
                    if not paintIcon(bb, cell.icon, cx + math.floor((cs - isz) / 2), cy + math.floor((ch - isz) / 2), isz)
                        and cell.text then
                        cell.text_fallback = true
                    end
                end
                if cell.shape then
                    local mid, rad = math.floor(cs / 2), math.floor(cs * 0.4)
                    bb:paintCircle(cx + mid, cy + mid, rad, ink)
                    if cell.shape == "white" then
                        bb:paintCircle(cx + mid, cy + mid, rad - math.max(2, px(2)), white)
                    end
                end
                if cell.mark then
                    local mk = math.floor(m * 0.16)
                    bb:paintRect(cx + math.floor((cs - mk) / 2), cy + math.floor((ch - mk) / 2), mk, mk, cell.mark == "white" and white or ink)
                end
                if cell.text and cell.text ~= "" and (not cell.icon or cell.text_fallback) then
                    local size = math.max(8, math.floor(m * (cell.scale or 0.5)))
                    local tw = self:text(cell.text, size, cell.color or (cell.fill == "black" and "white" or "black"))
                    local sz = tw:getSize()
                    tw:paintTo(bb, cx + math.floor((cs - sz.w) / 2), cy + math.floor((ch - sz.h) / 2))
                end
            end
        end
    end
    if g.gap or go then return end
    -- 细线用浅灰，粗线（数独宫格）与外框用黑色
    local thin, bold = 1, math.max(2, px(2))
    for i = 0, g.cols do
        local edge = i == 0 or i == g.cols
        local thick = edge or (g.thick and i % g.thick == 0)
        bb:paintRect(x + i * cs - (thick and 1 or 0), y, thick and bold or thin, self.dimen.h, thick and ink or RULE)
    end
    for i = 0, g.rows do
        local edge = i == 0 or i == g.rows
        local thick = edge or (g.thick and i % g.thick == 0)
        bb:paintRect(x, y + i * ch - (thick and 1 or 0), self.dimen.w, thick and bold or thin, thick and ink or RULE)
    end
end

function Board:cellAt(pos)
    local d = self.dimen
    if pos.x < d.x or pos.y < d.y or pos.x >= d.x + d.w or pos.y >= d.y + d.h then return end
    return math.floor((pos.y - d.y) / self.ch) + 1, math.floor((pos.x - d.x) / self.cs) + 1
end

-- 界面 ------------------------------------------------------------------

local GameScreen = InputContainer:extend{ covers_fullscreen = true }

-- 不能叫 new：会覆盖 InputContainer:new
function GameScreen.open(view, on_close)
    return GameScreen:new{ view = view, on_close = on_close }
end

local function buttonRow(k, entries, w)
    local gap = px(8)
    local n = #entries
    local bw = math.floor((w - gap * (n - 1)) / n)
    local row = HorizontalGroup:new{ align = "center" }
    for i, b in ipairs(entries) do
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
        row[#row + 1] = k.button(b.text, bw, b.callback, b)
    end
    return row
end

--- 大厅卡片网格：每张卡片 = 标题 + 说明，整张可点
local function cardGrid(k, cards, w, add)
    local gap = px(12)
    local cols = cards.cols or 2
    local cw = math.floor((w - gap * (cols - 1)) / cols)
    local ch = px(140)
    local row, n = nil, 0
    local function flush()
        if row then add(row, ch) add(VerticalSpan:new{ width = gap }, gap) row, n = nil, 0 end
    end
    for _, item in ipairs(cards.items) do
        if item.label then
            flush()
            add(VerticalSpan:new{ width = px(4) }, px(4))
            add(k.line("caption", item.label, w, true), nil)
            add(VerticalSpan:new{ width = px(8) }, px(8))
        else
            row = row or HorizontalGroup:new{ align = "top" }
            if n > 0 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
            local inner = VerticalGroup:new{ align = "center",
                item.icon and IconWidget:new{ name = item.icon, size = px(44) } or VerticalSpan:new{ width = 0 },
                VerticalSpan:new{ width = px(4) },
                k.line("title", item.title, cw - px(16), false, true),
                VerticalSpan:new{ width = px(6) },
                k.line("caption", item.caption or "", cw - px(16), true) }
            local card = k.card(inner, cw, ch)
            if item.pin then
                local ps = px(32)
                local pin = IconWidget:new{ name = item.pin.on and "pin_on" or "pin_off", size = ps }
                pin.overlap_offset = { cw - ps - px(10), px(8) }
                card = OverlapGroup:new{ dimen = Geom:new{ w = cw, h = ch }, card, pin }
            end
            local box = tap(card, cw, ch, item.callback)
            if item.pin then
                function box:onTapKG(_, ges)
                    local d, ps = self.dimen, px(56)
                    if ges and ges.pos and ges.pos.x >= d.x + d.w - ps and ges.pos.y <= d.y + ps then
                        item.pin.callback()
                    elseif item.callback then
                        item.callback()
                    end
                    return true
                end
            end
            row[#row + 1] = box
            n = n + 1
            if n == cols then flush() end
        end
    end
    flush()
end

function GameScreen:init()
    local v = self.view
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    local k = kit()
    local margin = px(14)
    local inner = W - 2 * margin
    local gap = px(8)

    local group = VerticalGroup:new{ align = "left" }
    local used = 0
    local function add(widget, h) group[#group + 1] = widget used = used + (h or widget:getSize().h) end

    local left, right
    if v.back then
        left = { icon = "arrow_back", text = "‹", callback = function() self:goBack() end }
    else
        right = { icon = "close", text = "✕", callback = function() self:onClose() end }
    end
    add(k.title(W - 2 * margin, v.title or "", left, right), k.title_h)
    add(VerticalSpan:new{ width = px(10) }, px(10))

    if v.status then
        add(CenterContainer:new{ dimen = Geom:new{ w = inner, h = px(32) }, k.line("body", v.status, inner) }, px(32))
        add(VerticalSpan:new{ width = px(6) }, px(6))
    end

    local rows = {}
    for _, entry in ipairs(v.buttons or {}) do rows[#rows + 1] = entry end
    local btn_total = 0
    for _, entry in ipairs(rows) do btn_total = btn_total + (entry.label and px(26) or (k.btn_h + gap)) end

    if v.grid then
        local avail = H - used - btn_total - 2 * margin - gap * 2
        local size = math.max(px(100), math.min(inner, avail))
        self.board = Board:new{ grid = v.grid, size = size,
            width = v.grid.ratio and inner or nil, height = v.grid.ratio and math.max(px(100), avail) or nil }
        add(CenterContainer:new{ dimen = Geom:new{ w = inner, h = self.board.dimen.h }, self.board }, self.board.dimen.h)
        add(VerticalSpan:new{ width = px(14) }, px(14))
    end

    if v.cards then cardGrid(k, v.cards, inner, add) end

    local pg = v.pager
    if pg and pg.pages > 1 then
        local widget
        if k.moon then
            local ok, w = pcall(function()
                return require("ui.themes.widgets.pager").widget{ width = inner, page = pg.page, pages = pg.pages,
                    on_prev = pg.on_prev, on_next = pg.on_next }
            end)
            widget = ok and w or nil
        end
        local ph = widget and widget:getSize().h or k.btn_h
        local fill = H - 2 * margin - used - ph - gap
        if fill > 0 then add(VerticalSpan:new{ width = fill }, fill) end
        if widget then
            add(widget, ph)
        else
            add(buttonRow(k, {
                { text = "‹", enabled = pg.page > 1, callback = pg.on_prev },
                { text = ("%d / %d"):format(pg.page, pg.pages) },
                { text = "›", enabled = pg.page < pg.pages, callback = pg.on_next },
            }, inner), k.btn_h)
        end
        add(VerticalSpan:new{ width = gap }, gap)
    end

    for _, entry in ipairs(rows) do
        if entry.label then
            add(k.line("caption", entry.label, inner, true), nil)
            add(VerticalSpan:new{ width = px(6) }, px(6))
        else
            add(buttonRow(k, entry, inner), k.btn_h)
            add(VerticalSpan:new{ width = gap }, gap)
        end
    end

    self[1] = FrameContainer:new{
        width = W, height = H, padding = margin, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        group,
    }

    local full = Geom:new{ x = 0, y = 0, w = W, h = H }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = full } },
        Hold = { GestureRange:new{ ges = "hold", range = full } },
        Swipe = { GestureRange:new{ ges = "swipe", range = full } },
    }
    if Device:hasKeys() then
        self.key_events = { BackKG = { { Device.input.group.Back } } }
    end
end

function GameScreen:onTap(_, ges)
    local g = self.view.grid
    if g and g.on_tap and self.board then
        local r, c = self.board:cellAt(ges.pos)
        if r then g.on_tap(r, c) return true end
    end
end

function GameScreen:onHold(_, ges)
    local g = self.view.grid
    if g and g.on_hold and self.board then
        local r, c = self.board:cellAt(ges.pos)
        if r then g.on_hold(r, c) return true end
    end
end

function GameScreen:onSwipe(_, ges)
    if self.view.on_swipe then
        self.view.on_swipe(ges.direction)
        return true
    end
end

function GameScreen:goBack()
    if self.view.back then self.view.back() else self:onClose() end
    return true
end

function GameScreen:onBackKG() return self:goBack() end

function GameScreen:onClose()
    UIManager:close(self, "ui") -- 整屏刷新，回到下层时不留残影
    if self.on_close then self.on_close() end
    return true
end

return GameScreen
