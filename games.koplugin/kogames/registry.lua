--[[--
游戏注册表。新增游戏 = games/<id>/main.lua（素材放 games/<id>/assets/，icon.svg 为大厅图标） + 在 LIST 里加一行。
游戏模块：{ id, title, icon, tier, desc, new = function(ctx) -> { start = fn, stop? = fn } }
tier：A 纯静态点按（墨水屏最佳）/ B 回合慢节奏 / C 实时（需实测刷新率）。
加载失败的游戏在大厅隐藏，不拖垮其它游戏。
--]]
local T = require("kogames.l10n")
local Registry = {}
local ROOT = (debug.getinfo(1, "S").source:match("^@(.*/)[^/]*$") or "./")

Registry.LIST = { "g2048", "minesweeper", "sudoku", "gomoku", "xiangqi",
    "chess", "go9", "checkers", "sokoban", "klondike",
    "freecell", "spider", "tetris", "snake", "connect4",
    "reversi", "fifteen",
    "goldminer", "lianliankan", "match3",
    "tictactoe",
    "doudizhu", "paodekuai", "bubbleshooter", "dino", "mario", "flappy", "breakout" }

function Registry.all()
    local out = {}
    for _, name in ipairs(Registry.LIST) do
        local ok, def = pcall(require, "kogames.games." .. name .. ".main")
        if ok and type(def) == "table" and def.id then
            def.assets = ROOT .. "games/" .. name .. "/assets/"
            def.art = def.assets .. "icon.svg"
            out[#out + 1] = def
        end
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
    ctx.pause_game, ctx.render_game = game.pause, game.render
    ctx.on_closed = function() if game.stop then game.stop() end end
    game.start()
    return game
end

return Registry
