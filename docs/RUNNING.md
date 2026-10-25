# 启动与验证

## Godot 中运行

使用 **Godot 4.7.2 stable** 打开项目根目录的 `project.godot`，按 **F5**。
默认入口为 `scenes/app_root.tscn`，无需手动选择主场景。启动后依次显示加载进度与主菜单。

首页使用 Dove 2.1.0.2 原版背景、17 帧 Logo、中文按钮和音乐。点击“开始”直接进入第一代第一关“南部港口”战役。选项支持即时调节音乐、音效并保存；制作人员入口暂未开放。
设计尺寸为 1920×1080，默认窗口为 1280×720。菜单内容等比适配窗口；战场固定逻辑高度 768，按宽高比扩展可见区域，支持 4:3 和 16:9。

首关固定普通难度、无英雄、零科技、未选第三法术；初始 20 生命、270 金币、8 塔位，7 波共 48 个哥布林、8 个兽人。点击塔位建造四类一级塔；选中已建塔可出售，兵营可调整集结点。二级塔锁定。
读完开场教学后手动开始第一波，后续有倒计时，可提前开波获得金币及技能冷却奖励。援军、火雨分别在第三、七波的教学确认后解锁。生命归零失败；最后一波清场后胜利，均可重开或返回菜单。

| 操作 | 输入 |
| --- | --- |
| 选择、建造、出售、集结、施法 | 鼠标左键 |
| 取消选择或落点模式 | 鼠标右键 |
| 关闭教学、取消选择、暂停或继续 | Esc |
| 火雨 / 援军 | 1 / 2，再左键选择道路落点 |
| 开波 | HUD 按钮或空格 |
| 暂停 / 速度 | HUD 右上角按钮；P 可暂停 |

运行首关无需 Python、LÖVE 或原游戏安装目录，这些仅供重新生成数据使用。实现与验证报告见 [LEVEL01_DELIVERY.md](LEVEL01_DELIVERY.md)。

音量保存在 Godot 的 `user://settings.json`。设置损坏时恢复默认值，写入失败时保留本次运行中的调整并提示。自动检查使用单独的临时设置文件，不改动玩家设置。
无显示的 headless 运行不会播放音频；音频检查应使用 Godot 原生渲染窗口。

## 日常验证

依照根目录 `AGENTS.md`，日常验证在 Godot 内完成，浏览器验收由用户手动执行。
以下命令在项目根目录的 PowerShell 中运行：

```powershell
# 设置默认值、持久化、损坏恢复、写入失败、加载缺失资源与重试、图集裁切
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_menu_bootstrap.gd

# 防止零时长 OGG 再次卡住编辑器的音频预览
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_audio_compat.gd

# 原生渲染：主菜单、弹窗、Esc、音量总线和音乐播放；截图保存到 reports/
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1280x720
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1920x1080
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1024x768

# 首关数据、源哈希、动画引用与派生图集像素核对
python tools/verify_level01_assets.py

# 逻辑：逐波出怪时间、四类塔、伤害、阻挡、技能、胜负、暂停、倍速、重开
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level01.gd

# 兵营门、直线集结、弹道/爆炸、羊和单位属性回归
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_battle_details.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/battle_details_visual.gd --resolution 1280x720

# 原生窗口：地图、建塔、战斗、教学、集结、技能、胜负和三次重开；可更换上述三种 resolution
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/battle_visual_smoke.gd --resolution 1280x720

# 逐页 UI、悬停/禁用、建造关键帧、文字测量和可交互区域越界检查
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/battle_ui_gallery.gd --resolution 1280x720
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/battle_ui_gallery.gd --resolution 1920x1080
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/battle_ui_gallery.gd --resolution 1024x768
```

现有独立素材预览仍可选择 `scenes/asset_preview.tscn` 后按 F6 运行。
战斗动画与交互复用规则见 [BATTLE_BEHAVIOR.md](BATTLE_BEHAVIOR.md)。点击士兵、援军或敌人可查看底部实时属性；右键或 Esc 取消选择；绵羊点击 8 次会爆炸。
后续界面实现遵循 [UI_ADAPTATION.md](UI_ADAPTATION.md)；本轮已在首关接入统一图文与命中适配，原生截图为 `reports/ui_*`。

## Web 导出与手动验收

发布目标保持 Compatibility、单线程 Web，不要求 COOP/COEP，不启用 Service Worker。
仅在需要交付或用户准备手动验收时导出：

```powershell
python tools/web_bootstrap.py export
python tools/web_bootstrap.py serve
```

在浏览器打开 `http://127.0.0.1:8060/`，通过 Ctrl+C 停止服务；也可用 `serve --port 8061` 指定其他端口。
不能通过双击 HTML 的 `file://` 方式运行。其他机器可通过 `export --godot <Godot可执行文件路径>` 指定引擎。
需要安装与引擎匹配的 Web 导出模板。

导出目录为 `build/web/`，可整体作为静态站点发布。本地服务器已经设置 WASM、PCK、JS 的 MIME 类型，并关闭本地缓存以方便手动验收。
浏览器首次点击或按键后启用声音。存储受到限制时会提示设置可能无法保留，不影响主菜单使用。

导出由 `data/menu_manifest.json` 与 `data/level01/manifest.json` 控制，只包含菜单和首关使用的脚本、场景、字体、图集、声音及 JSON。首关使用 5 张 2048×2048 派生图集，包含完整首关 UI 层和建造反馈，不打包完整素材库。
`export_presets.cfg` 由工具生成；修改依赖时先更新对应 manifest，再运行 `python tools/web_bootstrap.py preset`。
导出工具会用隔离的 Godot 工程检查 PCK，防止漏文件被开发目录掩盖；实际文件清单写入 `build/web/pack_files.json`。
此检查不会启动浏览器，也不替代用户的 Web 功能验收。

本轮可直接使用 `build/KingdomRush-Level01-Web.zip`。解压后运行 `start_server.cmd`，在浏览器打开其中提示的本地地址；保持命令窗口开启。首次点击、声音开启、页面切后台与浏览器兼容性由用户手动检查。

## 生成文件与版本管理

版本库只保留源码、运行资源、来源清单和少量验证汇总。`reports/` 中的截图、逐帧动画、原始日志和逐状态审计，`output/` 中的中间导出，以及 `build/` 中的试玩包均由工具生成，不提交 Git。临时验证产物清理后，可按上面的命令重新生成。

`reports/assets_migration_state.jsonl` 是增量搬运检查点，保留在本地并忽略；首次克隆时导入器会自行创建。最终 Web 包保留在本地，重新制作使用 `python tools/web_bootstrap.py export` 和 `python tools/package_level01.py`。
