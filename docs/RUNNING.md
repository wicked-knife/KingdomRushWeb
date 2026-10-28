# 启动与验证

项目与 Web 页面显示名称为 **Kingdom Rush Web**。桌面端固定沿用原 `Kingdom Rush Dove Web` 用户数据目录，音量设置保留，存档采用下述统一槽位新格式。

## Godot 中运行

使用 **Godot 4.7.2 stable** 打开项目根目录的 `project.godot`，按 **F5**。
默认入口为 `scenes/app_root.tscn`，无需手动选择主场景。启动后依次显示加载进度与主菜单。

首页使用 Dove 2.1.0.2 原版背景、17 帧 Logo、中文按钮和音乐。点击“开始”展开三个存档槽；选择新游戏或已有存档后进入一代大地图，再点击首关“南港”旗帜与“进入战斗”。选项支持即时调节音乐、音效并保存；制作人员入口暂未开放。
设计尺寸为 1920×1080，默认窗口为 1280×720。菜单内容等比适配窗口；战场固定逻辑高度 768，按宽高比扩展可见区域，支持 4:3 和 16:9。

首关固定普通难度、无英雄、零科技、未选第三法术；初始 20 生命、270 金币、8 塔位，7 波共 48 个哥布林、8 个兽人。点击塔位建造四类一级塔；选中已建塔可出售，兵营可调整集结点。二级塔锁定。

第二、第三关普通战役已接通。第二关初始 240 金币、7 塔位、7 波 154 个敌人；第三关初始 330 金币、12 塔位、11 波 329 个敌人，支持双路同时出怪。两关均为 20 生命，开放四类二级塔并锁定三级塔，发送第一波后解锁援军与火雨；小狼、萨满与食人魔沿用源属性及技能。实现、验证边界和重新生成命令见 [LEVEL02_03_DELIVERY.md](LEVEL02_03_DELIVERY.md)。

第四关「双子河畔」普通战役已接通，第三关胜利返回地图结算后开放。初始 520 金币、20 生命，15 个塔位、双入口、13 波共 339 个敌人，首次开放四类三级塔。盗贼拥有 50% 近战闪避，强盗拥有 50% 物理护甲；沿用源版背景、音乐、动画与通知。第四关胜利先保存待结算结果，返回地图后更新最好星级并开放第五关。历史实现和验证见 [LEVEL04_TIER3_DELIVERY.md](LEVEL04_TIER3_DELIVERY.md)。

第五关「银橡森林」普通战役已接通，第四关胜利返回地图结算后开放。初始 700 金币、20 生命，14 个塔位包含免费三级箭塔和精灵营地废墟，15 波共 242 名敌人，另统计母蛛孵化的小蜘蛛。三级箭塔可花 230 升游侠并购买毒箭／森林之怒。精灵营地修复费 190，初始为空；每花 100 招募一个永久兵位，上限四个，阵亡后待尸体消失自动补员。流血价格 100／100／100，致残 200／125／125；招募费不参与出售退款。第五关胜利返回地图后保存最好星级并解锁第六关，英雄不参战、零科技，前五关英雄／钢铁挑战已接入，配置和功能验收状态见下方。战役历史说明见 [LEVEL05_ELF_DELIVERY.md](LEVEL05_ELF_DELIVERY.md)。

第六关「城堡之战」三模式已接通，第五关战役返回地图结算后开放。战役初始 700 金币、20 生命、17 波、15 塔位、7 名皇家卫兵，末波为毁灭者；卫兵永久阵亡。第六关内开放圣骑士（三级兵营花 185 升级）、奥术塔（三级法师塔花 290 升级）及全部源版技能，游侠仍可用。包含飞行石像鬼、暗影弓箭手、Boss 导弹与投弹召唤，仍为零科技、无英雄参战。实现与验证边界见 [LEVEL06_DELIVERY.md](LEVEL06_DELIVERY.md)。第六关胜利结算后开放第七关预览。

前六关现在各有战役、英雄挑战、钢铁挑战三个入口，共 18 个关卡／模式组合，固定普通难度 `2`、无英雄参战、零科技。对应战役三星后开放挑战；英雄挑战 6 波、钢铁挑战 1 波，均为 1 生命。英雄／钢铁初始金币依次为 `230/360、310/275、400/660、750/1500、1000/1500、1200/800`。钢铁依次禁止新建箭塔＋法师塔、兵营、炮塔、法师塔＋炮塔、兵营、箭塔＋法师塔＋炮塔；第五关钢铁的三个免费三级箭塔与两处精灵废墟使用独立布局，营地修复、招募和技能仍允许。第六关钢铁没有卫兵，有两座可升奥术的免费三级法师塔。

挑战胜利通过 `last_victory → 返回地图` 结算数字模式成绩；首次通过各奖励一星，重复通过只保留最高难度，战役最好星级不变。前六关战役三星加十二个挑战应为 30 星。地图有英雄翅膀、钢铁旗帜、首次完成动画、面板完成徽章及难度印章；重开保留当前模式。

**验收口径：** 按 Dove 配置和功能一致性验收，不要求 AI 打通挑战。首关双挑战和第四关钢铁的 3 份回放保留作补充回归，其余 7 份无需补齐，不阻塞交付。1280×720 原生交互与 1024×768 新界面布局检查通过。详情和复现命令见 [CHALLENGES_DELIVERY.md](CHALLENGES_DELIVERY.md)。

四类塔二升三费用：兵营 150、箭塔 160、炮塔 320、法师塔 240。兵营更换为三名满血骑士，保留集结点；累计投入分别为 330/340/665/500，开波后退款分别为 198/204/399/300。三级独立测试场 `tests/tier3_upgrade_arena.tscn` 使用第四关地图和 2500 初始金币，不接入战役存档；原二级测试场保留。

游侠塔与两项三级技能也保留独立场地。打开 `tests/ranger_arena.tscn` 按 **F6**：初始 10000 金币，箭塔升至三级后花 230 升游侠，再选中购买毒箭／森林之怒；顶部可选敌人、数量与路线，手动出怪、补钱、清场及完整重置。场地不保存战役进度，前四关塔级限制保持原状。行为差异、来源与验证范围见 [RANGER_DELIVERY.md](RANGER_DELIVERY.md)。最新 Web 包包含第五关中的正式游侠。

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . res://tests/ranger_arena.tscn --resolution 1280x720
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_ranger.gd
python tools/verify_level01_assets.py --ranger-arena
```

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . res://tests/tier3_upgrade_arena.tscn
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_tier3_upgrades.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/level04_visual.gd --resolution 1280x720
# 另两种尺寸只检查新增界面，不重复回放战役
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/level04_visual.gd --resolution 1920x1080 -- --layout-only
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/level04_visual.gd --resolution 1024x768 -- --layout-only
```

弓箭塔一级升二级已在独立测试场接通，正式首关仍锁定二级塔。Godot 打开 `tests/archer_upgrade_arena.tscn` 后按 F6，或运行下方命令。测试场沿用战场与波次，仅解除二级箭塔限制，不接入地图或战役存档。建造箭塔花费 70，升级花费 110；二级伤害 8–13、射程 160、攻击间隔 0.6 秒。四类塔共用源版退款：开波前返还全部投入，开波后返还累计投入的 60%（四舍五入）；升级箭塔分别返还 180/108。详情见 [ARCHER_UPGRADE_DELIVERY.md](ARCHER_UPGRADE_DELIVERY.md)。

四类基础塔现在均支持一级升二级。通用测试场 `tests/tower_upgrade_arena.tscn` 初始 1000 金币，可直接按 F6 运行；兵营/炮塔/法师塔升级费为 110/220/160，累计投入 180/345/260，开波后退款 108/207/156。正式首关仍禁止二级塔，旧箭塔专用测试场保留。详情见 [TOWER_UPGRADES_DELIVERY.md](TOWER_UPGRADES_DELIVERY.md)。

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . res://tests/tower_upgrade_arena.tscn
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_tower_upgrades.gd
# 同样检查 1920x1080、1024x768
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/tower_upgrade_visual.gd --resolution 1280x720
```

地图左下角“英雄”可浏览全部 79 名英雄的资料和技能数值，按原版通关条件解锁，最多选择两名并分别保存到当前槽位。首关通关解锁 12 名英雄；满员后选择新英雄替换第二名。Tab 切换已选英雄，完成/Esc/右键关闭。当前选择尚不影响前五关战斗，英雄不会参战。详情和资源兜底说明见 [HERO_SELECTION_DELIVERY.md](HERO_SELECTION_DELIVERY.md)。
读完开场教学后点击出怪口的骷髅图标开始第一波；后续图标以圆环填充显示倒计时，点击可提前开波并获得金币及技能冷却奖励。金币栏下方显示 `+N` 金币动画，正在冷却的技能上方显示 `-Ns` 上浮淡出动画。悬停显示该路的下一波敌人数量与行进路径；双路图标任意点击一个即可启动整波。选塔、施法或暂停时图标暂不可点击。援军、火雨分别在首关第三、七波的教学确认后解锁。生命归零失败；最后一波清场后胜利，均可重开或返回地图。旗帜高亮与士兵寻敌修正详见 [INTERACTION_FIXES.md](INTERACTION_FIXES.md)。

大地图保留一代 27 个节点的数据与 124 个动画实例。槽位采用 Dove 的统一数据：关卡记录缺失表示锁定，空记录表示已解锁，各模式以数字键保存最高通关难度。胜利先保存 `last_victory`，返回地图或下次启动进入地图时更新最好星级、解锁塔和下一关；胜利后直接重开并失败会清除尚未结算的胜利，已经结算的成绩保留。第五关结算后开放第六关，第六关结算后可查看第七关预览。地图齿轮/Esc 打开设置，可返回主菜单；鼠标边缘与滚轮平移，Shift＋滚轮横移，触屏拖动与捏合缩放。

三个槽位保存于 `user://saves/slot_1.json` 至 `slot_3.json`，每个槽位包含全部世代的数据，采用临时写入与有效备份恢复。新槽位从源模板创建，运行时仅支持统一格式。删除槽位需要确认；损坏或较新格式不能当空槽覆盖。已见状态使用通用 `seen` 表，重开或离开战斗时保存，不需要新增敌人白名单。最后选择的槽位与音量保存在 `user://settings.json`。详见 [统一槽位交付](DOVE_SAVES_DELIVERY.md)。

| 操作 | 输入 |
| --- | --- |
| 选择、建造、出售、集结、施法 | 鼠标左键 |
| 取消选择或落点模式 | 鼠标右键 |
| 关闭教学、取消选择、暂停或继续 | Esc |
| 火雨 / 援军 | 1 / 2，再左键选择道路落点 |
| 开波 | 出怪口骷髅图标或空格 |
| 暂停 / 速度 | HUD 右上角按钮；P 可暂停 |
| 开发者菜单（仅调试运行/调试包） | DEV 按钮或 F8；Esc 关闭 |

援军须位于有效主路径节点 42 单位以内，地形只允许陆地/冰面；火雨的路径距离为 60 单位以内，也允许水面，但不能落在悬崖或精灵地形。距离采用源代码的直线距离与严格小于判定。无效点击在鼠标处播放约 0.47 秒红叉，保留技能选择，不消耗冷却，也不显示文字提示。

兵营设置集结点时，超出范围或地形不合法的点击会沿该方向向内寻找最远的合法位置；范围中心包含塔模板的偏移，并与界面范围圈一致。仅当该方向没有合法落点时才显示红叉。士兵使用解析后的实际集结点移动。

开发菜单支持 +10000 金币、+100 生命和跳过此波。打开时暂停，关闭恢复原状态；跳波清理当前敌人及剩余出怪并立即进入下一波，已有敌人结算金币，不发提前开波奖励。第三、七波仍须确认教学。调试局照常保存星级；正式包同时隐藏入口并拒绝开发命令。

标题、按钮使用 Dove 的 JIMOJW，正文使用微软雅黑，HUD 使用 TOONISH，普通数字使用 Comic Book Italic；全部字体与缺字回退都来自包内资源，统一测量排版。

存档统计按原版使用黑色斜体数字，并修正 KView 旋转方向。关卡书页统一首字、正文绕排、标题装饰、挑战规则、模式页签与开战按钮的内容区；短标题按可见字形测量，避免字体内部留白导致过度缩小。模式页签的普通、悬停、选中和锁定状态分别沿用源颜色与锚点。

运行前五关无需 Python、LÖVE 或原游戏安装目录，这些仅供重新生成数据使用。首关历史报告见 [LEVEL01_DELIVERY.md](LEVEL01_DELIVERY.md)，第二、三关见 [LEVEL02_03_DELIVERY.md](LEVEL02_03_DELIVERY.md)。

音量保存在 Godot 的 `user://settings.json`。设置损坏时恢复默认值，写入失败时保留本次运行中的调整并提示。自动检查使用单独的临时设置文件，不改动玩家设置。
无显示的 headless 运行不会播放音频；音频检查应使用 Godot 原生渲染窗口。

## 日常验证

依照根目录 `AGENTS.md`，日常验证在 Godot 内完成，浏览器验收由用户手动执行。
以下命令在项目根目录的 PowerShell 中运行：

前六关统一目录、控制器、行为分派及后续关卡接入方式见 [CONTENT_INTEGRATION.md](CONTENT_INTEGRATION.md)。共用机制迁移的代表检查如下；完整列表按受影响范围选用。

```powershell
# 统一接入：六份玩法定义、全部模式出生时间线、三个短战斗基线与萨满分派
python tools/verify_content_catalog.py
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_content_unification.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/content_tutorial_visual.gd --resolution 1280x720

# 第五关机制：精灵营地、状态、蜘蛛与结算；完整回放按需加 -- --full-replay
python tools/verify_level01_assets.py --level 5
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level05.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/level05_visual.gd --resolution 1280x720
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/level05_visual.gd --resolution 1024x768 -- --layout-only

# 挑战：默认只查配置、功能与代表场景，不运行完整通关回放
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_challenges.gd
# 仅需复现历史战斗或用户明确要求时，才在上述命令后加 -- --with-replays
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/challenges_visual.gd --resolution 1280x720
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/challenges_visual.gd --resolution 1024x768 -- --layout-only

# 第二至四关：源像素、逐 tick 波次与敌人机制、合法通关、原生画面和切关
python tools/verify_level01_assets.py --level 2
python tools/verify_level01_assets.py --level 3
python tools/verify_level01_assets.py --level 4
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_campaign_levels.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/campaign_levels_visual.gd --resolution 1280x720
# 同样运行 1920x1080、1024x768

# 英雄目录、资源像素、解锁、双选、存档与原生界面
python tests/verify_hero_assets.py
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_hero_room.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/hero_room_visual.gd --resolution 1280x720

# 设置默认值、持久化、损坏恢复、写入失败、加载缺失资源与重试、图集裁切
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_menu_bootstrap.gd

# 统一模板、五个世代解锁、两阶段结算、未知字段保留
python tools/prepare_saves.py
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_dove_saves.gd

# 三槽隔离、删除/恢复/写入失败、开发权限、跳波清理与完整调试通关
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_playtest_tools.gd

# 防止零时长 OGG 再次卡住编辑器的音频预览
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_audio_compat.gd

# 原生渲染：主菜单、弹窗、Esc、音量总线和音乐播放；截图保存到 reports/
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1280x720
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1920x1080
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1024x768

# 首关数据、源哈希、动画引用与派生图集像素核对
python tools/verify_level01_assets.py

# 独立箭塔测试场（交互运行，不保存战役进度）
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . res://tests/archer_upgrade_arena.tscn

# 箭塔升级事务、数值、攻击时序、首关锁定和累计退款
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_archer_upgrade.gd

# 原生按钮、禁用、退款和逐帧画面；同样运行 1920x1080、1024x768
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/archer_upgrade_visual.gd --resolution 1280x720

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
# 默认交付 release 包；显式加 --debug 可制作带开发菜单的调试包
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
# 用户需要本地服务器时自行运行
python tools/web_bootstrap.py serve
```

在浏览器打开 `http://127.0.0.1:8060/`，通过 Ctrl+C 停止服务；也可用 `serve --port 8061` 指定其他端口。
不能通过双击 HTML 的 `file://` 方式运行。其他机器可通过 `export --godot <Godot可执行文件路径>` 指定引擎。
需要安装与引擎匹配的 Web 导出模板。

导出目录为 `build/web/`，可整体作为静态站点发布。本地服务器已经设置 WASM、PCK、JS 的 MIME 类型，并关闭本地缓存以方便手动验收。
浏览器首次点击或按键后启用声音。存储受到限制时会提示设置可能无法保留，不影响主菜单使用。
浏览器也接受触摸与手柄按钮解锁声音；首次交互后菜单音乐会自动开始，进入地图、备战和开波时切换对应音乐。Web 播放器显式使用 Godot Stream 路径，以避开 4.7 Sample 路径在本项目中的静音输出。

导出由 `data/campaign_content.json` 的内容／控制器／运行脚本登记，以及菜单、地图、英雄房间和各已登记关卡的 manifest 控制，只包含实际使用的脚本、场景、字体、图集、声音及 JSON。三个模式按资源依赖并集裁剪，前六关分别使用 6、6、7、8、9、11 张 2048×2048 派生图集，不打包完整素材库。
`export_presets.cfg` 由工具生成；修改依赖时先更新对应 manifest，再运行 `python tools/web_bootstrap.py preset`。
导出默认只生成文件；`export --check-pack` 另执行隔离 PCK 资源与全部 18 个关卡／模式组合初始化、禁塔、胜利徽章、第五关双营地及第六关免费法师塔／奥术升级检查。PCK 通过不代表十二个挑战的完整通关检查通过；以本次导出回执和挑战交付报告分别记录。未操作浏览器，Web 功能与兼容性由用户手动验收。
显式 `export --check-pack` 的结果写入 `build/web/pack_files.json`。每次导出先移除旧检查报告，避免沿用上一版结论；`export_receipt.json` 记录本次导出及检查状态。

本轮使用 `build/KingdomRush-KR1-Levels01-06-Web.zip`，为 release 包，开发菜单关闭。解压后运行 `start_server.cmd`，在浏览器打开其中提示的本地地址；保持命令窗口开启。首次点击、声音开启、页面切后台与浏览器兼容性由用户手动检查。

## 生成文件与版本管理

版本库只保留源码、运行资源、来源清单和少量验证汇总。`reports/` 中的截图、逐帧动画、原始日志和逐状态审计，`output/` 中的中间导出，以及 `build/` 中的试玩包均由工具生成，不提交 Git。临时验证产物清理后，可按上面的命令重新生成。

`reports/assets_migration_state.jsonl` 是增量搬运检查点，保留在本地并忽略；首次克隆时导入器会自行创建。最终 Web 包保留在本地，重新制作调试包使用 `python tools/web_bootstrap.py export --debug` 和 `python tools/package_level01.py`。

专项检查已按 [冗余审查实施记录](TEST_REDUNDANCY_REVIEW.md) 精简：挑战 290、地图 81、战斗细节 49 次断言。命令清单是按改动选择的工具，不要求每次全部执行；默认挑战验收不重跑完整回放。
