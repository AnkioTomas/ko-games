--[[--
月读宿主：存档与 KOReader 宿主共用；提示用月读 Toast，缺失时回落到 InfoMessage。
--]]
local KO = require("kogames.host.koreader")

local Host = setmetatable({}, { __index = KO })
Host.__index = Host

function Host.new()
    return setmetatable({}, Host)
end

function Host:notify(text)
    local ok, Toast = pcall(require, "ui.themes.widgets.toast")
    if ok and type(Toast) == "table" and Toast.new then
        if pcall(function() Toast:new{ text = text, timeout = 2 }:show() end) then return end
    end
    KO.notify(self, text)
end

return Host
