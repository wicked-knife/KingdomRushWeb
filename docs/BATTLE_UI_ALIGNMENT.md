# 前六关战斗交互与 UI 修正

实施日期：2026-10-28。源基准为 Dove `2.1.0.2`，冻结提交 `e29ece82939fd73fb69bfc4b469d484a72e4dfd2`。第六关功能先提交为 `5490ef9`；本批在该基线上修正共用表现与输入，覆盖前六关和游侠测试场。固定普通难度、无英雄参战、零科技，第七关保持预览。

## 本次行为

| 项目 | 完成内容 |
| --- | --- |
| 单位选择 | 使用源 `selected_small/med/big` 和友军标记，叠加单位 `marker_offset`，在地面贴花层绘制；取消选择、死亡和隐藏时移除，飞行单位及 Boss 共用 |
| 兵营集结 | 当前点使用源 `decal_rally_feedback` 循环；设置时播放 10 帧鼠标；成功后在解析后的实际落点播放 `rally_feedback`，1.5 秒内淡出；范围和落点修正规则不变 |
| 火雨／援军 | 分别使用 32 帧火雨、10 帧橙色落点动画，叠加源技能图标和锚点；无效点仍播放 14 帧红叉，不消耗技能或战斗 RNG |
| 系统鼠标 | 进入落点模式立即定位自绘指示器并隐藏鼠标；取消、成功、暂停、通知、结算、重开、返回地图、移出窗口和失焦时恢复，重新进入后同步当前模式 |
| 开波 | 首波单击，后续提前开波双击同一入口，空格保留；第一次点击只保留预告，波次／入口身份和 Godot 双击事件共同确认，模式切换及失焦等清除确认 |
| 不可用按钮 | 锁定、金币不足、满级按钮静默消费点击并保留选中与说明；命令校验继续生效，拒绝塔交易时不弹通用错误文字 |
| 下一波预告 | 按源字体、标题及敌人列表测量宽高和行距；四向箭头与背景合并后一次绘制，透明度一致，消除接缝，边缘整组避让 |
| 胜利与技能菜单 | 恢复三模式徽章、弧形标题、星星、链条及继续／重开按钮；高级塔与营地共用源边框、等级灯偏移和 23 帧购买动画，满级隐藏价格／光晕，保留正常图标及已亮等级 |

胜利弹出为 0.6 秒，0.65 秒开始星星与原音效，随后两个链条各用 0.5 秒展开；展开完成才接受按钮点击。普通胜利页移除生命／击杀／波数统计，开发局标识独立保留。胜利粒子使用独立随机数。既有 `finished → last_victory → Continue → map` 两阶段存档链不变，重开仍沿用原语义。

新增动画使用表现时钟；本批没有修改模拟器及战斗行为模块、更新顺序、公开命令、关卡加载接口或存档结构。所有源版参照来自 `all-desktop/game_gui.lua` 的 MousePointer、IncomingTooltip、VictoryView、VictoryParticles、TowerMenu，`all/scripts.lua` 的 entity_marker_controller，以及 `kr1-desktop/data/game_gui_data.lua` 的技能等级灯偏移。提前开波双击按本次确认的交互规则实现。

## 数据与资源

导出器新增 `ui.selection_markers` 和 `ui.tower_menu_power_offset`；前六关与测试场统一再生成。七份定义的所有非 UI 玩法字段和原有 UI 字段均与 `5490ef9` 的哈希一致。绑定元数据单独处理：旧定义补齐空 `callbacks`，游侠补齐已有荆棘光环依赖，第五关精灵致残箭补齐已有粒子依赖；没有新增玩法模板或更改数值。

共用指示器等新增帧导致图集重新排布，原 74 份资源中 20 份字节不变，其余用新资源基线和冻结源像素验证。历史玩法金样未重写；新增 `tests/fixtures/battle_ui_baseline.json` 记录提交基线玩法哈希、原 UI 哈希及当前 99 份资源哈希。

| 内容 | 模板 | 帧名 | 唯一帧 | 动画 | 图集 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 第一关 | 40 | 1533 | 812 | 97 | 6 |
| 第二关 | 39 | 1586 | 850 | 102 | 7 |
| 第三关 | 66 | 2045 | 1101 | 124 | 7 |
| 第四关 | 78 | 2457 | 1279 | 158 | 8 |
| 第五关 | 73 | 3143 | 1757 | 218 | 10 |
| 第六关 | 101 | 3696 | 2036 | 253 | 11 |
| 游侠测试场 | 85 | 2673 | 1392 | 181 | 8 |

`decal_rally_feedback` 是源动画 ID，对应 `rally_feedback` 的 17–25 帧循环，并非静态图片名。新关卡复用共用资源收集和表现模块，接入方式见 [CONTENT_INTEGRATION.md](CONTENT_INTEGRATION.md)。

## 验证证据

以下断言数为检查条数，截图数为画面采样数，均不表示独立完整战斗场景。

| 检查 | 结果与范围 |
| --- | --- |
| `battle_ui_logic.json` | 122 项通过：单／双击与空格、入口／波次确认、奖励一次、静默拒绝、鼠标生命周期、技能购买／满级／出售／重开清理、徽章／按钮时点／独立粒子，以及真正返回地图的存档事件链 |
| `battle_ui_1280x720.json` | 原生 130 项通过，26 张动画／布局截图；包含真实 viewport 点击与系统鼠标状态，战役一至三星、英雄／钢铁徽章及按钮开放时点 |
| `battle_ui_1024x768.json` | 原生布局 52 项通过，13 张截图；只补查预告、菜单、指示器和三模式胜利页，不重复战斗检查 |
| `battle_ui_assets.json` | 七份内容、99 份资源核对通过；每份内容检查完整 116 个指定 UI 帧及冻结源像素，玩法和原 UI 哈希一致 |
| 相邻专项 | 施法 185 项（820 个源落点样本）、技能 HUD 35 项、集结 129 项（80 个源案例）、胜利音频 29 项通过 |
| `content_catalog.json` | 全部 18 个组合及资源／行为注册校验通过 |

原生截图经过目视检查，包含游侠／圣骑士／奥术／营地菜单、购买阶段、飞行和 Boss 选择、预告以及胜利弹出／完成阶段；截图与日志留在忽略目录 `reports/`。构造状态和固定输入用于短专项，不宣称正常经济通关。玩法未改，继承第六关基线的时间线和短战斗证据；本批未重复完整战役或挑战回放。

```powershell
python tools/verify_battle_ui_assets.py
python tools/verify_content_catalog.py
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_battle_ui_alignment.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/verify_battle_ui_alignment.gd --resolution 1280x720
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/verify_battle_ui_alignment.gd --resolution 1024x768 -- --layout-only

# 最终集中导出一次，隔离 PCK 检查全部 18 个组合及新增 UI 资源
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
```

## 交付

最终包为 `build/KingdomRush-KR1-Levels01-06-Web.zip`，构建、隔离 PCK、资源及 ZIP 哈希记录在 `reports/battle_ui_delivery.json` 和 `reports/map_kr1_web.json`。导出前校验 UI 报告及其运行脚本哈希，避免使用过期验证结果。仅创建本地提交，不推送；构建包、原生截图和临时日志不入库。

交付阶段首包的隔离检查发现两个新 UI 脚本未登记到 Web 资源清单，已补入共用内容目录；同时修正检查器中 JSON 浮点字典与整数字典的偏移比较。该首包未交付，修正后重新导出并通过检查，共两次导出尝试、一次有效交付包。未为日常 UI 迭代重复导出。

Web 为 release 包，开发命令关闭。浏览器功能、音频解锁、切后台和存档持久化由用户手动验收，本批未自动操作浏览器。
