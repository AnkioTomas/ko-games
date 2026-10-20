--[[--
KOReader 宿主：UIManager 显示/定时，LuaSettings 存档。
--]]
local Interface = require("kogames.host.interface")

local Host = {}
Host.__index = Host

function Host.new()
    return Interface.check(setmetatable({}, Host))
end

function Host:showScreen(view)
    local UIManager = require("ui/uimanager")
    local old = self.widget
    if old and old.tryUpdate and old:tryUpdate(view) then return end
    self.widget = require("kogames.ui.screen").open(view, function()
        self.widget = nil
        if view.on_close then view.on_close() end
    end)
    UIManager:show(self.widget, "ui")
    if old then UIManager:close(old, "ui") end
end

function Host:closeScreen()
    if self.widget then
        local w = self.widget
        self.widget = nil
        w.on_close = nil
        require("ui/uimanager"):close(w, "ui")
    end
end

function Host:schedule(seconds, fn)
    require("ui/uimanager"):scheduleIn(seconds, fn)
    return fn
end

function Host:unschedule(handle) require("ui/uimanager"):unschedule(handle) end

function Host:_store() return require("kogames.storage").open() end

function Host:load(id) return self:_store():readSetting("state_" .. id) end

function Host:save(id, state)
    local s = self:_store()
    s:saveSetting("state_" .. id, state)
    s:flush()
end

function Host:getSetting(key, default)
    local v = self:_store():readSetting("setting_" .. key)
    if v == nil then return default end
    return v
end

function Host:setSetting(key, value)
    local s = self:_store()
    s:saveSetting("setting_" .. key, value)
    s:flush()
end

function Host:notify(text)
    local InfoMessage = require("ui/widget/infomessage")
    require("ui/uimanager"):show(InfoMessage:new{ text = text, timeout = 2 })
end

function Host:now() return os.time() end

return Host
