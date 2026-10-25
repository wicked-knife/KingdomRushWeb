# 启动与验证

项目与 Web 页面显示名称为 **Kingdom Rush Web**。桌面端固定沿用原 `Kingdom Rush Dove Web` 用户数据目录，改名后继续读取已有三槽存档和音量设置。

## Godot 中运行

使用 **Godot 4.7.2 stable** 打开项目根目录的 `project.godot`，按 **F5**。
默认入口为 `scenes/app_root.tscn`，无需手动选择主场景。启动后依次显示加载进度与主菜单。

首页使用 Dove 2.1.0.2 原版背景、17 帧 Logo、中文按钮和音乐。点击“开始”展开三个存档槽；选择新游戏或已有存档后进入一代大地图，再点击首关“南港”旗帜与“进入战斗”。选项支持即时调节音乐、音效并保存；制作人员入口暂未开放。
设计尺寸为 1920×1080，默认窗口为 1280×720。菜单内容等比适配窗口；战场固定逻辑高度 768，按宽高比扩展可见区域，支持 4:3 和 16:9。

首关固定普通难度、无英雄、零科技、未选第三法术；初始 20 生命、270 金币、8 塔位，7 波共 48 个哥布林、8 个兽人。点击塔位建造四类一级塔；选中已建塔可出售，兵营可调整集结点。二级塔锁定。

地图左下角“英雄”可浏览全部 79 名英雄的资料和技能数值，按原版通关条件解锁，最多选择两名并分别保存到当前槽位。首关通关解锁 12 名英雄；满员后选择新英雄替换第二名。Tab 切换已选英雄，完成/Esc/右键关闭。当前选择尚不影响首关战斗，英雄不会参战。详情和资源兜底说明见 [HERO_SELECTION_DELIVERY.md](HERO_SELECTION_DELIVERY.md)。
读完开场教学后手动开始第一波，后续有倒计时，可提前开波获得金币及技能冷却奖励。援军、火雨分别在第三、七波的教学确认后解锁。生命归零失败；最后一波清场后胜利，均可重开或返回地图。

大地图保留一代 27 个节点的数据与 124 个动画实例，按 Dove 逐步解锁。首关胜利立即保存最好星级并解锁第二关；第二关可查看详情但尚未实现战斗。地图齿轮/Esc 打开设置，可返回主菜单；鼠标边缘与滚轮平移，Shift＋滚轮横移，触屏拖动与捏合缩放。详情与验证见 [MAP_KR1_DELIVERY.md](MAP_KR1_DELIVERY.md)。三个槽位分别保存于 `user://saves/kr1/slot_1..3/campaign.json`，采用临时写入与有效备份恢复。旧 `user://campaign_kr1.json` 自动迁入槽位 1 并归档，不会在删除后再次迁入；删除槽位需要确认，损坏或较新版本存档不能作为空槽自动覆盖。

| 操作 | 输入 |
| --- | --- |
| 选择、建造、出售、集结、施法 | 鼠标左键 |
| 取消选择或落点模式 | 鼠标右键 |
| 关闭教学、取消选择、暂停或继续 | Esc |
| 火雨 / 援军 | 1 / 2，再左键选择道路落点 |
| 开波 | HUD 按钮或空格 |
| 暂停 / 速度 | HUD 右上角按钮；P 可暂停 |
| 开发者菜单（仅调试运行/调试包） | DEV 按钮或 F8；Esc 关闭 |

开发菜单支持 +10000 金币、+100 生命和跳过此波。打开时暂停，关闭恢复原状态；跳波清理当前敌人及剩余出怪并立即进入下一波，已有敌人结算金币，不发提前开波奖励。第三、七波仍须确认教学。调试局照常保存星级；正式包同时隐藏入口并拒绝开发命令。

标题、按钮使用 Dove 的 JIMOJW，正文使用微软雅黑，HUD 使用 TOONISH，普通数字使用 Comic Book Italic；全部字体与缺字回退都来自包内资源，统一测量排版。

存档统计按原版使用黑色斜体数字，并修正 KView 旋转方向。关卡书页统一首字、正文绕排、标题装饰、挑战规则、模式页签与开战按钮的内容区；短标题按可见字形测量，避免字体内部留白导致过度缩小。模式页签的普通、悬停、选中和锁定状态分别沿用源颜色与锚点。

运行首关无需 Python、LÖVE 或原游戏安装目录，这些仅供重新生成数据使用。实现与验证报告见 [LEVEL01_DELIVERY.md](LEVEL01_DELIVERY.md)。

音量保存在 Godot 的 `user://settings.json`。设置损坏时恢复默认值，写入失败时保留本次运行中的调整并提示。自动检查使用单独的临时设置文件，不改动玩家设置。
无显示的 headless 运行不会播放音频；音频检查应使用 Godot 原生渲染窗口。

## 日常验证

依照根目录 `AGENTS.md`，日常验证在 Godot 内完成，浏览器验收由用户手动执行。
以下命令在项目根目录的 PowerShell 中运行：

```powershell
# 英雄目录、资源像素、解锁、双选、存档与原生界面
python tests/verify_hero_assets.py
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_hero_room.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/hero_room_visual.gd --resolution 1280x720

# 设置默认值、持久化、损坏恢复、写入失败、加载缺失资源与重试、图集裁切
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_menu_bootstrap.gd

# 三槽隔离、迁移/删除/恢复/写入失败、开发权限、跳波清理与完整调试通关
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_playtest_tools.gd

# 防止零时长 OGG 再次卡住编辑器的音频预览
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_audio_compat.gd

# 原生渲染：主菜单、弹窗、Esc、音量总线和音乐播放；截图保存到 reports/
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1280x720
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1920x1080
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1024x768

# 首关数据、源哈希、动画引用与派生图集像素核对
python tools/verify_level01_assets.py

# 一代地图数据、像素、解锁、存档异常、完整战役与三次场景切换
python tests/verify_map_assets.py
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_campaign_map.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/map_visual_smoke.gd --resolution 1280x720

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
# 本轮交付调试包，含开发菜单；正式包去掉 --debug
python tools/web_bootstrap.py export --debug
python tools/package_level01.py
# 用户需要本地服务器时自行运行
python tools/web_bootstrap.py serve
```

在浏览器打开 `http://127.0.0.1:8060/`，通过 Ctrl+C 停止服务；也可用 `serve --port 8061` 指定其他端口。
不能通过双击 HTML 的 `file://` 方式运行。其他机器可通过 `export --godot <Godot可执行文件路径>` 指定引擎。
需要安装与引擎匹配的 Web 导出模板。

导出目录为 `build/web/`，可整体作为静态站点发布。本地服务器已经设置 WASM、PCK、JS 的 MIME 类型，并关闭本地缓存以方便手动验收。
浏览器首次点击或按键后启用声音。存储受到限制时会提示设置可能无法保留，不影响主菜单使用。

导出由菜单、`data/map_kr1/manifest.json`、`data/heroes/manifest.json` 和首关 manifest 控制，只包含菜单、地图、英雄房间和首关使用的脚本、场景、字体、图集、声音及 JSON。首关使用 5 张、一代地图使用 13 张、英雄房间使用 4 张 2048×2048 派生图集，不打包完整素材库。
`export_presets.cfg` 由工具生成；修改依赖时先更新对应 manifest，再运行 `python tools/web_bootstrap.py preset`。
导出默认只生成文件；本次英雄选择交付使用 `export --debug --check-pack`，已通过隔离 PCK 资源完整性检查，共 411 个文件。未操作浏览器，Web 功能与兼容性由用户手动验收。
显式 `export --check-pack` 的结果写入 `build/web/pack_files.json`。每次导出先移除旧检查报告，避免沿用上一版结论；`export_receipt.json` 记录本次导出及检查状态。

本轮可直接使用 `build/KingdomRush-KR1-Playtest-Debug-Web.zip`。解压后运行 `start_server.cmd`，在浏览器打开其中提示的本地地址；保持命令窗口开启。首次点击、声音开启、页面切后台与浏览器兼容性由用户手动检查。

## 生成文件与版本管理

版本库只保留源码、运行资源、来源清单和少量验证汇总。`reports/` 中的截图、逐帧动画、原始日志和逐状态审计，`output/` 中的中间导出，以及 `build/` 中的试玩包均由工具生成，不提交 Git。临时验证产物清理后，可按上面的命令重新生成。

`reports/assets_migration_state.jsonl` 是增量搬运检查点，保留在本地并忽略；首次克隆时导入器会自行创建。最终 Web 包保留在本地，重新制作调试包使用 `python tools/web_bootstrap.py export --debug` 和 `python tools/package_level01.py`。
