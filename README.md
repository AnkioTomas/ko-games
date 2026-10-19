<p align="center"><img src="docs/logo.png" width="160" alt="ko-games"></p>

# ko-games

适合墨水屏的 KOReader 离线小游戏合集：一个 `games.koplugin` 内含框架和 30 个游戏，界面全部用 SVG 素材绘制，支持简体中文 / 繁体中文 / English（跟随 KOReader 语言）。也可作为[月读 moon](https://github.com/AnkioTomas/moon) 扩展使用。

## 游戏
| 类别 | 游戏 |
|---|---|
| 益智 | 2048（3×3 到 6×6）、扫雷、数独、华容道（数字）、记忆翻牌、推箱子、消消乐、连连看、井字棋（3×3 / 4×4 / 5×5）、倒水排序 |
| 牌类（人机） | 斗地主（叫地主、倍数、春天）、跑得快（48 张，三带二、飞机、炸弹） |
| 实时动作 | 黄金矿工（摆钩、抓取、炸药）、泡泡龙（六边形网格、反弹瞄准）、小恐龙跳跳、跳跳冒险（横版闯关）、像素鸟、打砖块 |
| 棋类（人机） | 中国象棋、国际象棋、围棋 9×9、跳棋、五子棋、四子棋、黑白棋 |
| 纸牌 | Klondike、空当接龙、蜘蛛纸牌 |
| 实时 | 俄罗斯方块、贪吃蛇（可调速度，墨水屏建议慢速） |

每个游戏都有玩法说明（首次进入自动弹出）；带难度、大小、规则的游戏，右上角是设置按钮，选项与撤销 / 新游戏都在设置弹窗里。

## 安装
下载 [Releases](../../releases) 里的 `games.koplugin-*.zip`，解压后把 `games.koplugin/` 放进 KOReader 的 `plugins/`，重启。
入口：顶部菜单里的手柄图标标签页。长按大厅里的图钉可以置顶游戏，置顶的游戏会列在该标签页里，点一下直接开玩。

装了月读时，首页可添加「游戏」组件（显示置顶游戏的图标卡片和「更多」），快捷面板多一个「游戏」动作；没装月读也完全可用。 月读的设置里会多一页「游戏 - Games（版本号）」，可开关自动检查更新或手动检查：复用月读的 GitHub Release 检查、镜像竞速下载与校验，发现新版本后一键下载安装并重启。Release 附件需命名为 `games.koplugin-<版本>.zip`（`tools/package.sh <版本>` 会注入版本号）。

## 存档
`<数据目录>/.moon/game/kogames/save.lua`：`state_<游戏id>`（存档）、`state_stats_<游戏id>`（最佳成绩）、`setting_*`。两种宿主共用。

## 结构
```
games.koplugin/
  main.lua / _meta.lua       KOReader 入口
  moon_source.lua            月读扩展（ext.kogames）
  assets/                    共享素材（图钉、棋子、花色）
  kogames/
    host/                    interface + koreader + moon 宿主
    ui/screen.lua            通用全屏界面：标题、状态、棋盘、按钮、设置弹窗（view 表契约见文件头）
    ctx.lua                  游戏会话：render / save / record / rng
    registry.lua lobby.lua launcher.lua l10n/
    games/<id>/              main.lua（Core 纯逻辑 + new(ctx) 产出 view）、assets/、spec.lua
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
[AGPL-3.0](LICENSE)，与 KOReader 一致，也兼容月读的 GPL-3.0。第三方素材见 [NOTICE](NOTICE)。
