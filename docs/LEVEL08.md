# 第八关、野蛮人、大贝莎与雪人营地

基准为 Dove 2.1.0.3／`1a863df00b08f6bf1018ae0b0e7e4e106b939082`，普通难度 2、默认科技方案 1。第一至八关共 24 个可玩关卡／模式组合，第九关保留地图预览。

| 模式 | 初始金币 | 生命 | 波数 | 科技上限 | 英雄 |
| --- | ---: | ---: | ---: | ---: | --- |
| 战役 | 800 | 20 | 18 | 6 | 允许 |
| 英雄挑战 | 1100 | 1 | 6 | 5 | 禁用 |
| 钢铁挑战 | 1200 | 1 | 1 | 5 | 禁用 |

布局包含 13 处站位和路径 2→5 的隧道。钢铁挑战保留 ID 20 的免费二级法师塔，禁止新建箭塔和法师塔。关卡直接允许新塔；胜利先记录 `last_victory`，返回地图后才永久解锁野蛮人和大贝莎。第 4–7 关已补齐回玩所需资源，仍按源禁塔、科技限制和存档锁定执行。

## 防御塔与营地

三级兵营新增野蛮人分支（195），保留圣骑士分支。四名野蛮人支持双斧、旋风和投斧，三级价格分别为 225／100／100、150／100／100、150／100／100。双斧与旋风保留源实际购买顺序对属性和动画的影响。士兵攻击前摇、命中、投斧追踪距离、眩晕／集结中断和攻击冷却均有运行时消费者；尸体保留源不透明度，十秒后清理并补员。

三级炮塔新增大贝莎（400）。龙息导弹价格 175／150／150，集束弹价格 175／210／210；普通炮弹、导弹和集束弹按源顺序选择，射手按源动画发射并回到 idle。导弹跟踪、加速、实际命中伤害、震荡眩晕、未命中时的三枚子导弹，以及集束弹的抛物线、分裂和弹片数量均按实际源函数比较。

新防御塔解锁通知按 Dove `NotificationView` 的单卡／双卡布局绘制：标题为“新防御塔解锁”，确认按钮为正文体“好的！”，分类、塔名和介绍使用 `body_slides`。照片逆时针倾斜，标题下缘和按钮上缘由纸张覆盖；双卡按钮按源中心锚点定位。第六、七、八关的真实开局通知在 1280×720、1024×768 原生窗口分别通过 117 项检查，覆盖文字布局、字体、可点击区域和确认关闭；本地截图及专项结果见 `reports/feedback_tower_notice_*.png`、`reports/tower_notice_*.json`。此次为局部 UI 验证，未重新导出 Web 包。

站位 91 初始为冰冻营地。火雨弹丸在营地范围爆炸后解冻；花费 400 招募一只雪人，阵亡后等待十二秒免费补员。招募费用不计入卖塔退款，重开恢复冰冻状态。雪人的范围攻击、攻击动画结束、尸体保留与实体清理均在原生窗口检查。

冰封营地本体按 Dove 保留可点击、可选中，点击会打开圆环；其中只有 `tw_none` 灰色占位图标，无购买边框、价格、集结或可用的雇佣操作。该图标禁用点击，悬停无说明。源菜单残留精灵营地的修复文案，但 `game_gui.lua` 的该分支未绑定点击与悬停回调，实际不显示这些文本；复刻保留隐藏解锁方式，不额外提供火雨解冻教程。火雨解冻后才显示 400 金币雇佣和集结按钮。

## 敌人和源协程

巨魔首领的三次连续施法按源前摇、循环和动画等待执行：前摇期间眩晕取消，施法当帧眩晕仍发出效果，效果发出后的动画等待继续；沉默阻止开始，不取消已开始的连续施法。首领可影响自己，并保留允许模板、减速／狂暴排斥和可见性筛选。巨魔、投斧巨魔、首领分别按源频率回血；隧道入口移除回血光环与增益并撤销属性，出口恢复光环和协程，保留子路线。

`dove_enemy_melee.gd` 消费本关雪怪和投斧巨魔的混合攻击。雪怪以开始攻击时的位置及朝向确定椭圆范围，按源士兵顺序最多命中十人；主目标死亡或闪避不取消其他范围目标，命中时生成震地效果和贴花。投斧巨魔保留近战优先、远程等待、射击时刻、目标移远／死亡后的投射物语义。命中前、命中当帧和命中后的眩晕分别对照源协程，攻击结束后恢复循环 idle。

目录中的 `runtime_dependencies` 检查双斧投斧弹等隐式资源，`runtime_callbacks` 检查大贝莎导弹移除回调。正式运行时与导出共用校验规则；删除所需资源或回调必须拒绝加载／发布。

## 验证与重现

```powershell
python tools/prepare_level08_reference.py
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level08.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_advanced_barrack_cooldown.gd
python tools/prepare_upgrades.py --check --reference --reference-level 8
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level08_upgrades.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x720 --script tests/level08_visual.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1024x768 --script tests/level08_visual.gd -- --layout-only
python tools/verify_level01_assets.py --level 8
python tools/verify_level08_compatibility.py
python tools/verify_level08_delivery.py
```

重新导入资源时使用 `python tools/prepare_level01.py --level 8`。源采样要求冻结的 Dove 和 LÖVE；日常运行及已有样本的 Godot 检查不依赖它们。仅排查新敌人攻击时可给 headless 专项追加 `-- --enemies-only`，该快速模式不替代完整的第八关验收报告。

三个模式的 1097 条出生记录按 25 个波次保留完整比较；72 个独立行为场景覆盖塔协程、技能升级、弹丸、士兵和敌人的攻击中断、首领施法。逐帧／逐实体记录不是额外独立场景。完整比较写入忽略的 `reports/level08_timelines.json`、`reports/level08_comparisons.json`，简报保留在版本库。

1280×720 原生检查覆盖真实鼠标输入、两座塔及全部技能、效果和动画结束状态、火雨解冻、付费招募与免费补员、重开和三模式结算；1024×768 仅检查受影响布局。使用独立测试存档，构造胜利结果检查结算，不要求 AI 通关挑战。截图保留在本地 `reports/towers_eighth_*.png`。

`tests/fixtures/level08_additions.json` 以第八关前提交 `20f7188` 声明第 4–7 关 definition、animations、atlas、sounds、manifest 共 20 部分的允许增量。旧数值、旧动画帧和未声明升级边均有负向探针；旧战斗快照和源像素基准保持原样。发布检查还绑定旧内容、科技及相邻专项报告的当前文件哈希。

最终集中导出 release 包 `build/KingdomRush-KR1-Levels01-08-Web.zip`，执行隔离 PCK 与 ZIP 完整性检查。浏览器的实际运行、输入、音频和存档由用户手动验收，不将资源包检查描述为浏览器验收。

导出前逐项核对脚本和场景中的显式运行时引用，拒绝清单遗漏；第八关的六个新增运行时模块均列入 `runtime_scripts`。隔离 PCK 检查会在缺件或脚本编译失败时立即记录失败并退出，同时保留异常中断后的退出计时器。旧缺件包已用于负向回归，避免将开发目录中的资源误算为发布包自带资源。

## 野蛮人共用冷却修复（2026-10-31）

原选招表达式把 `a.cooldown` 用作 `Dictionary.get` 的默认参数。Godot 会提前求值这个参数，而旋风仅配置共用冷却，没有独立字段，因此连尚未解锁旋风的普通接战也会报错。现在按 Dove 的 `SU.soldier_pick_melee_attack` 依次使用适用的共用冷却、独立冷却、零值回退，保留严格冷却边界。

`tests/verify_advanced_barrack_cooldown.gd` 通过真实 `sim.step()` 进入士兵更新和选招，覆盖未解锁旋风、双斧、旋风、双斧旋风、雪人，以及三种冷却回退分支。修改前能复现缺少字段的报错；修改后 8 个代表场景、71 项断言通过，包括实际命中、共用时间戳和连续两次攻击的时刻。运行命令为 `Godot --headless --path . --script tests/verify_advanced_barrack_cooldown.gd`，简报为 `reports/advanced_barrack_cooldown.json`，后续发布检查会核对该证据及其源哈希。

原生主分辨率现在先用未购买技能的真实兵营生成野蛮人，让其自行走出兵营、接敌、选招、命中并再次攻击，再进行技能与生命周期抽样；不通过 `_begin` 注入这段普通接战。1280×720 通过 208 项断言，1024×768 布局通过 104 项。隔离 PCK 也新增正常士兵更新的选招探针。

## 第八关科技完整性补查（2026-10-31）

补查发现两项之前未被科技样本覆盖的适配缺项：二级炮兵射程科技除炮塔攻击范围外，还应增加大贝莎导弹的 `range_base`；六级炮兵科技应将导弹／集束弹冷却基数和每级减量同时乘以 0.88。现按 Dove `patch_engineer_range` 与 `patch_engineer_power_cooldown` 修复，回玩第 4–7 关时也生效。挑战的五级科技上限继续阻止六级冷却加成。

`level08_upgrades_source.json` 独立执行冻结 Dove 的实际科技补丁和大贝莎技能升级回调；16 组科技／上限配置、1472 条模板投影分别计数。投影包括健康、射程、攻击参数、技能价格和冷却，运行时重算的攻击排序由行为专项核对。Godot 通过 418 项检查，购买导弹／集束弹各三级，实际调用攻击选择消费者核对射程、冷却及地面目标的混合冷却。原 40 组默认科技样本和历史战斗快照未改写。

此次完整交付已替换 `657c3bd` 的旧 Web 包，隔离 PCK 实际选招探针和 ZIP 完整性检查均通过；新的包哈希及检查结果记录在 `reports/map_kr1_web.json` 和 [当前版本更新记录](DOVE_2106_UPDATE.md)。浏览器由用户手动验收。
