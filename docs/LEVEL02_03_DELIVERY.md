# 一代第二、第三关普通战役

基准为只读 Dove `2.1.0.2`，提交 `e29ece82939fd73fb69bfc4b469d484a72e4dfd2`。关卡定义、布局、路径、波次、模板、动画与声音由离线求值器导出，各输入与源图集记录 SHA-256。

后续已按 Dove 修正地图旗帜高亮、兵营/援军重新寻敌动画，并将开波操作改为出怪口图标、圆环倒计时及分路敌人/路径提示，见 [交互修正报告](INTERACTION_FIXES.md)。下方为战役实现阶段的验证记录；当前试玩包信息统一见 `reports/map_kr1_web.json`。

| 关卡 | 初始生命／金币 | 塔位／波数 | 完整出怪 |
| --- | --- | --- | --- |
| 第二关 | 20／240 | 7／7 | 哥布林 106、兽人 26、小狼 22，共 154 |
| 第三关 | 20／330 | 12／11 | 哥布林 224、兽人 58、小狼 32、萨满 12、食人魔 3，共 329 |

普通难度沿用源模板的生命倍率 1.65、移动速度倍率 1.2。两关开放四类二级塔，三级塔锁定；援军、火雨在发送第一波后解锁。首关仍保留原教学与塔级限制。本次无英雄参战、科技、第三法术或挑战模式。

## 实现

- `campaign_levels.gd` 统一按关卡、模式、难度加载；地图在资源检查成功后进入战斗。原战斗初始化和模拟器构造入口兼容，背景、图集、音乐、塔限制、总波数与结算关卡身份由定义决定。
- 三关分别裁剪资源与 manifest；布局实例的 sprite、延迟播放等覆盖值保留为独立模板。第二关沿用源默认流程；第三关使用原图，并接入船、磨坊、水面、鱼与羊等装饰。鱼按源 5–10 秒间隔跳跃，关联成就系统尚未迁移。
- 波次保留主路径与子路径，第三关双路并发；支持 `creep_aux / max_same` 交替和零数量等待段，同 tick 出怪保持导出顺序。独立随机源、30 Hz 模拟、提前开波奖励与倒计时保持共用行为。
- 小狼快速移动、仅近战闪避；萨满保留魔抗、冷却、14 tick 前摇、命中时重新选敌、最多三个单位与每个 50 点治疗，治疗不超过生命上限，施法中死亡取消。索敌按源空间网格顺序，治疗效果跟随目标及体型。食人魔保留原攻击与体型，漏怪扣三命。
- HUD 与结算显示实际总波数，单位属性与血条随模板变化；接通策略、魔抗和三种新敌人通知。敌人已见状态与英雄选择统一保存到当前槽位，现行规则见 [统一槽位交付](DOVE_SAVES_DELIVERY.md)。
- 前三关按顺序解锁，保存实际关卡的最佳星数；第三关胜利解锁第四面预览旗，第四关战斗仍未开放。返回地图释放战斗、音频与关卡目录引用。

源第二关请求 `TOWER_LEVEL2`，但冻结版本的 GUI 数据没有对应页面。本实现以原纸张、标题和按钮资源补充二级塔说明文字；这是明确的适配补充，不作为原版逐像素页面复刻。独立随机源不保证与 Lua 使用相同随机序列；弹道继续沿用既有解析采样实现。

## 验证与交付

战役实现阶段的结果记录于 `reports/campaign_levels_delivery.json`；逐项逻辑结果见 `reports/campaign_levels_logic.json`，三关源哈希与裁剪像素检查见 `reports/level01_assets.json`、`level02_assets.json`、`level03_assets.json`。后续专项修正分别记录在交互修正文档及对应报告中。

2026-10-26 检查全部通过：新战役逻辑 577 项，另有交互修正专项 448 项，三关裁剪像素与来源哈希一致；首关、战斗细节、箭塔升级、四类二级塔、地图与开发工具已回归，初次交付另验证了三槽存档、菜单、英雄选择与音频兼容。原生 `1280×720`、`1920×1080`、`1024×768` 各保存战役 25 张、交互专项 31 张关键截图，文字及点击区审计无失败；另回归首关 UI 与四类二级塔原生操作。

| 正常金币回放（seed 42） | 击杀／漏怪 | 剩余生命／金币 | 结束 tick |
| --- | --- | --- | --- |
| 第二关胜利 | 139／15 | 5／82 | 9037 |
| 第三关胜利 | 320／9 | 11／19 | 19175 |

空防分别在 tick 1984、2360 失败。两关均验证三次重开，另完成六次跨关切换及实例释放；退出战斗后立即释放战斗音乐，避免地图加载期间保留上局音轨。

战役实现阶段的 release 导出及隔离 PCK 检查通过。当前发布包的大小、SHA-256 和资源检查结果以 `reports/map_kr1_web.json` 为准，避免重复记录过期包信息。

原生检查使用固定种子与正常金币，通过合法操作完成两关，再检查空防失败、暂停、倍速、三次重开、跨关释放、实际关卡存档和第四旗状态。原生窗口采用加速模拟回放，并包含实际输入处理路径的建造、升级与弹窗点击；不等同于人工实时通关。音频检查核对播放器与播放调用，不声称逐音人工听辨。

```powershell
# 重新导出两关，旧命令不带 --level 时仍导出首关
python tools/prepare_level01.py --level 2
python tools/prepare_level01.py --level 3
python tools/verify_level01_assets.py --level 2
python tools/verify_level01_assets.py --level 3
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import --quit
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_campaign_levels.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/campaign_levels_visual.gd --resolution 1280x720
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/campaign_levels_visual.gd --resolution 1920x1080
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/campaign_levels_visual.gd --resolution 1024x768
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
```

交付为 `build/KingdomRush-KR1-Levels01-03-Web.zip`，release、Compatibility、单线程 Web，按入口、地图、英雄房间与前三关 manifest 裁剪。解压后运行 `start_server.cmd`，按窗口提示打开本地地址。隔离 PCK 检查核对资源及三关初始化；浏览器玩法、声音解锁、后台切换、存储与兼容性由用户手动验收。
