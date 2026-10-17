local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end
local _ = require("kogames.l10n")
return {
    fullname = _("小游戏合集"),
    description = _("适合墨水屏的离线小游戏：2048、扫雷、数独、五子棋、推箱子。也可作为月读扩展，在月读首页和快捷面板添加入口。"),
}
