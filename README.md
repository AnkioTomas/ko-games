# ko-games

适合墨水屏的 KOReader 离线小游戏合集：一个 `games.koplugin` 内含框架和多个游戏，并可作为[月读 moon](https://github.com/AnkioTomas/moon) 扩展使用。

已有：2048、扫雷、数独、五子棋、推箱子。调研与排期见 [docs/games.md](docs/games.md)。

## 安装
把 `games.koplugin/` 放进 KOReader 的 `plugins/`，重启。入口：主菜单「工具 → 游戏」。
装了月读时，首页可添加「游戏」组件，快捷面板多一个「游戏」动作；没装月读也完全可用。

## 存档
`<数据目录>/.moon/game/kogames/save.lua`：`state_<游戏id>`（存档）、`state_stats_<游戏id>`（最佳成绩）、`setting_*`。两种宿主共用。

## 结构
```
games.koplugin/
  main.lua / _meta.lua       KOReader 入口
  moon_source.lua            月读扩展（ext.kogames）
  kogames/
    host/                    interface + koreader + moon 宿主
    ui/screen.lua            通用全屏界面：标题、状态、棋盘、按钮行（view 表契约见文件头）
    ctx.lua                  游戏会话：render / save / record / rng
    registry.lua lobby.lua launcher.lua
    games/<id>.lua           每个游戏：Core（纯逻辑）+ new(ctx)（产出 view）
spec/run.lua                 离线测试
tools/package.sh             打包
```
游戏核心只产出 `view` 表，界面由 `ui/screen.lua` 渲染，所以核心逻辑可以在没有 KOReader 的环境里测试。

## 开发
```bash
luajit spec/run.lua        # 离线测试（KOReader 用 LuaJIT，不要用 5.3 的位运算 / // 语法）
tools/package.sh 0.1.0     # 生成 dist/games.koplugin-0.1.0.zip
```
新增游戏见 [docs/games.md](docs/games.md) 末尾的「原则」。

## 许可
自写代码的许可证待作者确定；移植第三方代码时按其许可证写入 NOTICE。
