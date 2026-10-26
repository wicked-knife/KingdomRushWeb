# 弓箭塔一级升二级

2026-10-26。基准为冻结 Dove `2.1.0.2 / e29ece82939fd73fb69bfc4b469d484a72e4dfd2`。只新增二级弓箭塔；正式首关保留四类二级塔锁定。未扩展其他塔、英雄或可玩关卡，未导出 Web。

## 行为和来源

| 项目 | 还原结果 | 来源 |
| --- | --- | --- |
| 价格 | 建造 70，一级升二级 110，累计投入 180 | `kr1/foundamental_towers.lua` |
| 攻击 | 8–13 物理伤害，射程 160，间隔 0.6 秒（18 帧），第 5 帧出箭，21 帧飞行 | 二级塔、`arrow_2` 及继承的攻击/弹道定义 |
| 外观 | `archer_tower_0002`，两名 `shooterarcherlvl2` 射手，显示偏移 ±9/52，出箭偏移 ±10/50 | 原模板与图集，保留不同的显示/发射挂点 |
| 动画 | 两名射手轮值，上下方向各完整 8 帧攻击，水平翻转，结束回对应待机 | `all/scripts.lua`、原动画表 |
| 升级 | 即时替换为新塔并重新开始冷却；旧待发攻击取消，已发箭继续使用一级模板结算 | `all/tower_utils.lua`、`tower_archer.update` |
| 退款 | 开波前全退，开波后按累计投入的 60% 四舍五入；二级箭塔退 180/108 | `all/tower_utils.lua`，四类现有塔共用 |
| 菜单 | 原升级图标、110 价格牌和中文提示；金币不足禁用；成功关闭；二级无三级按钮 | `tower_menus_data.lua` 与模板 |

`level01_sim.gd` 的 `upgrade` 命令接收 `id` 和 `upgrade_to`，本批仅允许 `tower_archer_1 → tower_archer_2`。命令层重新检查目标、建造状态、关卡限制和金币，沿用教程/暂停/结算拦截；失败不扣款、不改变塔。实例记录当前 `template`、`spent`、`holder`，升级保留塔位、位置、地形和集结点；出售恢复干净的 holder。显示与攻击读取当前模板，退款提示与命令使用同一计算入口。

`Battle.initialize` 新增可选的第三个 definition 参数，默认仍使用首关；模拟对注入数据深拷贝。测试场仅在自己的定义副本中解除二级箭塔锁定，正式首关读取源战役 override 的 `locked_towers`，开发加钱也无法绕过。

## 独立测试场

在 Godot 中打开 `tests/archer_upgrade_arena.tscn` 后按 F6，或运行：

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . res://tests/archer_upgrade_arena.tscn
```

沿用已有战场、路径、敌人、七波数据和战斗 UI，初始 270 金币。点击空塔位建箭塔，完成后点击升级；可以开波、出售、重开和使用原调试菜单。暂停或结算中的“退出测试场”关闭运行窗口。该场景没有战役进度对象或结果保存监听，不出现在地图，不写入战役存档；音量设置使用独立文件。

## 验证

```powershell
python tools/verify_level01_assets.py
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_archer_upgrade.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/archer_upgrade_visual.gd --resolution 1280x720
```

原生检查同时运行 `1920x1080`、`1024x768`；首关回归采用 RUNNING.md 中的 `verify_level01`、`verify_battle_details`、`verify_campaign_map`、`verify_playtest_tools` 和三分辨率 `battle_visual_smoke`。

升级逻辑检查覆盖 109/110 金币边界、无效/重复目标、建造中、模态通知、暂停及结算后事务、完整攻击时序、射程边界、朝向、物理护甲、升级时待发/已发箭、四类一级塔及升级塔退款、出售后重建、首关开发加钱锁定和重开隔离。

原生脚本通过 `_gui_input` 和绘制出的点击区域操作按钮，逐状态截图，检查两名射手各方向的 8 帧攻击与待机，共 36 个原生采样帧，并检查真实模拟杀敌、退款、锁定及三次重开。它是可复跑的 Godot 原生输入/渲染回放；不属于真人实时游玩或逐音效听辨。截图在完成后实际打开查看。

精简结果保存在 `reports/archer_upgrade_report.json`；详细逻辑、原生审计和截图按需生成于 `reports/archer_*`，不提交 Git。图集更新后为 1058 个帧 ID、577 个唯一帧、72 段动画，仍为 5 张图集及 49 个音频文件；35 项冻结输入哈希与全部派生像素检查通过。

本轮实际结果：升级逻辑 166 项、战斗细节 485 项、地图战役 36063 项、试玩工具 69 项全部通过；三种分辨率的升级原生回放各 196 项全部通过，并逐项查看了菜单、退款、首关锁定及攻击帧对照图。首关七波逻辑和三分辨率完整原生回放通过，包含胜负、教程、技能、返回地图及三次重开；headless 基准为 56 次出怪、55 击杀、1 漏怪、19 生命胜利。重新生成的数据与修改前比较，布局、路径、地形、波次、规则及所有既有模板完全一致，仅增加二级箭塔与箭弹模板。最终没有未通过项。
