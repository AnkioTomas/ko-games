--[[--
游戏注册表。新增游戏 = games/<id>/init.lua + 在 LIST 里加一行。
游戏模块：{ id, title, icon, tier, desc, new = function(ctx) -> { start = fn, stop? = fn } }
tier：A 纯静态点按（墨水屏最佳）/ B 回合慢节奏 / C 实时（需实测刷新率）。
加载失败的游戏在大厅隐藏，不拖垮其它游戏。
--]]
local T = require("kogames.l10n")
local Registry = {}

Registry.LIST = { "g2048", "minesweeper", "sudoku", "gomoku", "sokoban" }

Registry.TIERS = {
    A = T("静态益智 · 墨水屏最佳"),
    B = T("回合制 · 慢节奏"),
    C = T("实时 · 需实测刷新"),
}

function Registry.all()
    local out = {}
    for _, name in ipairs(Registry.LIST) do
        local ok, def = pcall(require, "kogames.games." .. name)
        if ok and type(def) == "table" and def.id then out[#out + 1] = def end
    end
    return out
end

function Registry.get(id)
    for _, def in ipairs(Registry.all()) do
        if def.id == id then return def end
    end
end

--- 启动一个游戏；exit 为返回大厅的回调。
function Registry.launch(host, def, exit)
    local ctx = require("kogames.ctx").new(host, def, exit)
    local game = def.new(ctx)
    ctx.on_closed = function() if game.stop then game.stop() end end
    game.start()
    return game
end

return Registry
