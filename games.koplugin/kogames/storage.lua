--[[--
存档位置：<KOReader 数据目录>/.moon/game/kogames/save.lua。
键：state_<游戏id>（存档）、setting_<key>（设置）。KOReader 与月读两种宿主共用同一份。
--]]
local M = {}

M.deps = {
    dataDir = function() return require("datastorage"):getDataDir() end,
    open = function(path) return require("luasettings"):open(path) end,
    mkdirp = function(path)
        local ok, util = pcall(require, "util")
        if ok and util and util.makePath then util.makePath(path) return end
        local lfs = require("libs/libkoreader-lfs")
        local cur = ""
        for part in path:gmatch("[^/]+") do
            cur = cur .. "/" .. part
            if not lfs.attributes(cur, "mode") then lfs.mkdir(cur) end
        end
    end,
}

local store

function M.dir() return M.deps.dataDir() .. "/.moon/game/kogames" end

function M.open()
    if store then return store end
    M.deps.mkdirp(M.dir())
    store = M.deps.open(M.dir() .. "/save.lua")
    return store
end

function M._reset() store = nil end

return M
