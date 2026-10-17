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
  },
  on_swipe = function(dir) end,                -- dir = "north"|"south"|"east"|"west"
  buttons = { { {text=, callback=, enabled=, selected=}, ... } 一行, { label = "分组标题" } },
  on_close = function() end,                   -- 点右上角 × 或返回键关闭时
}
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local FILLS = {
    grey = Blitbuffer.Color8(0xD8),
    dark = Blitbuffer.Color8(0x88),
    black = Blitbuffer.COLOR_BLACK,
}
local TEXT_COLORS = {
    white = Blitbuffer.COLOR_WHITE,
    grey = Blitbuffer.Color8(0x66),
    black = Blitbuffer.COLOR_BLACK,
}

local function px(n) return Screen:scaleBySize(n) end

-- 棋盘 ------------------------------------------------------------------

local Board = Widget:extend{}

function Board:init()
    local g = self.grid
    self.cs = math.max(1, math.floor(math.min(self.size / g.cols, self.size / g.rows)))
    self.dimen = Geom:new{ w = self.cs * g.cols, h = self.cs * g.rows }
    self.texts = {}
end

function Board:text(str, size, color)
    local key = str .. "|" .. size .. "|" .. color
    local w = self.texts[key]
    if not w then
        w = TextWidget:new{ text = str, face = Font:getFace("cfont", size), fgcolor = TEXT_COLORS[color] or TEXT_COLORS.black }
        self.texts[key] = w
    end
    return w
end

function Board:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local g, cs = self.grid, self.cs
    local ink = Blitbuffer.COLOR_BLACK
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    for r = 1, g.rows do
        for c = 1, g.cols do
            local cell = g.cell(r, c)
            local cx, cy = x + (c - 1) * cs, y + (r - 1) * cs
            if cell then
                if cell.fill and FILLS[cell.fill] then
                    bb:paintRect(cx, cy, cs, cs, FILLS[cell.fill])
                end
                if cell.shape then
                    local mid, rad = math.floor(cs / 2), math.floor(cs * 0.4)
                    bb:paintCircle(cx + mid, cy + mid, rad, ink)
                    if cell.shape == "white" then
                        bb:paintCircle(cx + mid, cy + mid, rad - math.max(2, px(2)), Blitbuffer.COLOR_WHITE)
                    end
                end
                if cell.text and cell.text ~= "" then
                    local size = math.max(8, math.floor(cs * (cell.scale or 0.5)))
                    local tw = self:text(cell.text, size, cell.color or (cell.fill == "black" and "white" or "black"))
                    local sz = tw:getSize()
                    tw:paintTo(bb, cx + math.floor((cs - sz.w) / 2), cy + math.floor((cs - sz.h) / 2))
                end
            end
        end
    end
    local thin = 1
    for i = 0, g.cols do
        local thick = g.thick and i % g.thick == 0
        local t = thick and math.max(2, px(2)) or thin
        bb:paintRect(x + i * cs - (thick and 1 or 0), y, t, self.dimen.h, ink)
    end
    for i = 0, g.rows do
        local thick = g.thick and i % g.thick == 0
        local t = thick and math.max(2, px(2)) or thin
        bb:paintRect(x, y + i * cs - (thick and 1 or 0), self.dimen.w, t, ink)
    end
end

function Board:cellAt(pos)
    local d = self.dimen
    if pos.x < d.x or pos.y < d.y or pos.x >= d.x + d.w or pos.y >= d.y + d.h then return end
    return math.floor((pos.y - d.y) / self.cs) + 1, math.floor((pos.x - d.x) / self.cs) + 1
end

-- 界面 ------------------------------------------------------------------

local GameScreen = InputContainer:extend{ covers_fullscreen = true }

-- 不能叫 new：会覆盖 InputContainer:new
function GameScreen.open(view, on_close)
    return GameScreen:new{ view = view, on_close = on_close }
end

local function buttonRow(entries, w)
    local gap = px(8)
    local n = #entries
    local bw = math.floor((w - gap * (n - 1)) / n)
    local row = HorizontalGroup:new{}
    for i, b in ipairs(entries) do
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
        row[#row + 1] = Button:new{
            text = b.text, width = bw, enabled = b.enabled ~= false and b.callback ~= nil,
            callback = b.callback, bordersize = b.selected and px(4) or px(1),
            radius = px(4), text_font_size = 20,
        }
    end
    return row
end

function GameScreen:init()
    local v = self.view
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    local margin = px(10)
    local inner = W - 2 * margin
    local btn_h, gap = px(60), px(8)

    local group = VerticalGroup:new{ align = "center" }
    local used = 0
    local function add(widget, h) group[#group + 1] = widget used = used + (h or widget:getSize().h) end

    local title_h = px(56)
    local close = Button:new{
        text = "×", width = title_h, bordersize = 0, text_font_size = 28,
        callback = function() self:onClose() end,
    }
    add(HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = inner - title_h, h = title_h },
            TextWidget:new{ text = v.title or "", face = Font:getFace("cfont", 24), max_width = inner - title_h },
        },
        close,
    }, title_h)

    if v.status then
        add(TextWidget:new{ text = v.status, face = Font:getFace("cfont", 20), max_width = inner })
    end

    local rows = {}
    for _, entry in ipairs(v.buttons or {}) do rows[#rows + 1] = entry end
    local btn_total = #rows * (btn_h + gap)

    if v.grid then
        add(VerticalSpan:new{ width = gap }, gap)
        local avail = H - used - btn_total - 2 * margin - gap
        local size = math.max(px(100), math.min(inner, avail))
        self.board = Board:new{ grid = v.grid, size = size }
        add(self.board, self.board.dimen.h)
        add(VerticalSpan:new{ width = gap }, gap)
    end

    for _, entry in ipairs(rows) do
        if entry.label then
            add(TextWidget:new{ text = entry.label, face = Font:getFace("cfont", 16), fgcolor = Blitbuffer.Color8(0x66), max_width = inner })
        else
            add(buttonRow(entry, inner), btn_h)
        end
        add(VerticalSpan:new{ width = gap }, gap)
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
        self.key_events = { Close = { { Device.input.group.Back } } }
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

function GameScreen:onClose()
    UIManager:close(self, "ui") -- 整屏刷新，回到下层时不留残影
    if self.on_close then self.on_close() end
    return true
end

return GameScreen
