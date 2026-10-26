# 地图旗帜、士兵寻敌与出怪口开波修正

基准仍为 Dove `2.1.0.2 / e29ece82`，使用原版素材与背景。

各节及专项报告保留对应修正阶段的验证结果；当前发布包信息以 `reports/map_kr1_web.json` 为准。

## 兵营集结点范围外回退

已补齐 Dove `PickView:on_down` 的集结点解析：先检查原点击位置；若超出椭圆范围，将方向向量按直线长度归一至集结半径，再从 99% 到 1% 向内搜索，选择第一个同时满足范围、路径和地形的点。范围内的无效地形也沿原方向向内搜索；合法点击保持原位置。范围中心改为塔位加 `tower.range_offset`，与显示的范围圈一致。一、二级兵营分别读取源模板的 145/150 半径。整个方向无合法点时保留原集结点并显示红叉。

命令先解析实际落点，再更新兵营及所有存活士兵的集结中心、队形目的地和移动状态，并解除旧拦截关系。技能落点继续使用独立规则，不执行兵营的方向回退。

离线参考工具直接提取并执行源 GUI 的完整搜索代码及 `U.is_inside_ellipse`。`tests/fixtures/rally_clamp_reference.json` 的 80 个案例覆盖前三关、两个塔位、一/二级兵营、合法点击、四向与斜向超范围、无合法方向；首关仅验证实际开放的一级兵营。`tests/verify_rally_clamp.gd` 在 headless 与原生各 129 项通过，核对成功状态与实际坐标、三名士兵目的地和旧拦截解除。原生 `1280×720` 截图已查看，相邻落点专项 185 项也通过。未重复完整战役或浏览器验收；无资源变更，集中导出一次 release Web 并检查隔离 PCK。最新交付见 `reports/rally_clamp_delivery.json`。

## 技能落点与无效点击修正

原实现只要求地形含 `LAND` 且无 `NOWALK`，遗漏路径距离，也把援军与火雨混用同一判定，因此远离道路的草地可以部署援军。现逐项对照 `all-desktop/game_gui.lua` 的 `GUI_MODE_POWER_1/2`、`all/path_db.lua` 的 `valid_node_nearby`、`all/grid_db.lua` 的 `cell_is_only/get_coords`：援军必须在有效主路径节点 42 单位内，且地形不含陆地/冰面以外的标记；火雨为 60 单位内或水面，并排除悬崖/精灵地形。保持直线距离、严格小于、路径启用状态及节点禁用标记，网格使用源 ceil/clamp 坐标转换。前三关没有额外关卡施法回调或路径宽度覆盖。兵营集结点共用同样的路径/地形过滤，方向回退见上一节。

无效落点取消中央文字与整枚指针染红，改为 Dove `MousePointer:show_cross` 使用的 `error_feedback_0001–0014`，持续 `14/30` 秒并跟随鼠标，随后恢复施法指针。重复点击从头播放，成功施法、取消和重开清除反馈。失败不生成单位/弹丸，不消耗冷却或随机数，技能继续保持选中。三个关卡图集新增原版红叉帧，来源像素与哈希已核对。

`tools/skill_placement_reference` 在离线 LÖVE 环境直接执行冻结源的网格/路径模块，并从源 GUI 文件提取原始判定表达式，生成 `tests/fixtures/skill_placement_reference.json`。前三关共 820 个采样点、两种技能的判定均一致。`tests/verify_skill_placement.gd` 的 headless 与 Godot 原生各 185 项专项检查通过，覆盖道路边缘、不同地形、无效点击无副作用、红叉时序与恢复、有效重试、取消/重开、默认集结点及三关四条路径上的援军实际拦截。原生 `1280×720` 的两张截图已查看；未重复完整战役、多分辨率或浏览器验收。最新交付信息见 `reports/skill_placement_delivery.json`。

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_skill_placement.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/verify_skill_placement.gd --resolution 1280x720
```

地图旗帜原先在普通静止状态使用 `0180/0181` 悬停发光帧，并按全局时间循环播放动画，移出时没有重新计时。现按 `all-desktop/screen_map.lua` 的 `LevelFlagView` 管理独立状态：悬停固定高亮并停止随机动画；移出从 `24` 或 `90` 重播，停在普通的 `64` 或 `134`；间隔 3–10 秒再次飘动。平移、缩放、关闭弹窗和鼠标离开窗口时同步更新悬停。

士兵原先以“到敌人的椭圆距离是否超过 20”判定到达，却向固定横向偏移点移动；此外，到达时如果近战仍在冷却，跑步状态可能保留。现按 `all/script_utils.lua` 的 `soldier_pick_melee_target`、`soldier_move_to_slot_step`、`soldier_go_back_step` 及 `all/utils.lua` 的 `melee_slot_position` 读取源站位参数，依据敌人朝向、体型和拦截排名移动到实际近战位置，到达即停步。寻敌中心使用共同集结点，非第一拦截者可改拦空闲敌人，目标死亡后重新寻敌或返回队形。兵营两级士兵和援军共用修正。

提前开波现按 `all-desktop/game_gui.lua` 的 `WaveFlag` 与 `IncomingTooltip`，在下一波使用的入口显示原版骷髅圆环、方向箭头与悬停光晕。入口位置和方向来自关卡的 `editor_wave_flag` 数据；首波等待手动点击，后续圆环随模拟时间填充，倒计时结束自动开波。悬停显示该路敌人种类、数量与移动虚线路径，双路任一图标可启动整波并同时收起图标。选塔、施法、弹窗和暂停期间图标变暗且不可点击。空格快捷键、原金币奖励和技能冷却奖励保留。首关开始提示移至入口旁，并翻转原纸张使箭头指向图标。

新增专项检查 `tests/verify_interaction_fixes.gd`：448 项通过，涵盖旗帜反复进入/移出、三种士兵与五种敌人、左右朝向、三种拦截排名、冷却期间到达、击杀后再寻敌、无目标回队、双入口报告、奖励和提示淡出。源素材哈希与裁剪像素检查、首关、战斗细节、四类二级塔、箭塔、地图和开发工具回归通过。

Godot 原生窗口在 `1280×720`、`1920×1080`、`1024×768` 检查入口倒计时、路径提示、旗帜状态和士兵动画；开波点击经过引擎输入流程，悬停截图使用鼠标输入回调与受控坐标，避免桌面真实鼠标事件干扰。两关合法通关、空防失败、暂停、倍速、连续重开与切关回放通过。专项原生检查使用受控场景观察特定状态，完整战役检查使用合法命令加速回放。汇总见 `reports/interaction_fixes_delivery.json`，专项明细见 `reports/interaction_fixes_logic.json`，原生截图与 JSON 保存在 `reports/interaction_*`。

更新后的 release Web 包为 `build/KingdomRush-KR1-Levels01-03-Web.zip`。使用 Compatibility、单线程，导出后执行隔离 PCK 检查；浏览器玩法和兼容性由用户手动验收。

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_interaction_fixes.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/interaction_fixes_visual.gd --resolution 1280x720
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
```

## 提前开波奖励反馈更新

金币栏下方显示原版旋转金币与 `+N` 数字，1.5 秒淡出；正在冷却的技能上方显示蓝色 `-Ns` 数字，1 秒上浮淡出，取消中央文字提示。素材、0.7 字距、二次缓出与时长来自 `all-desktop/game_gui.lua` 的 `WaveRewardFx`、`TimeRewardFx` 和 `PowerButton:early_wave_bonus`；金币反馈按本项目要求改为锚定金币栏。倒计时奖励只对开波前正在冷却的已解锁技能显示，提前时间不超过 1 秒时沿用源行为省略冷却浮字。金币奖励音使用 `GUICoins`。

这次局部修复执行 `tests/verify_wave_rewards.gd` 的 27 项专项检查，覆盖奖励金额、冷却扣减及归零、已就绪/锁定技能、首波/自动开波/零奖励、动画消退、连续奖励和重开清理。Godot 原生窗口 `1280×720` 保存 4 张奖励动画截图；三个参考宽度的边界检查通过。新增素材随三关图集重新裁剪，已对照来源像素及哈希。奖励反馈报告为 `reports/wave_rewards_delivery.json`，上面的完整战役及交互报告保留为此前的验证基线。本轮交付集中导出一次 release Web，并检查隔离 PCK。项目规则已要求按变更范围做专项回归。

```powershell
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_wave_rewards.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/verify_wave_rewards.gd --resolution 1280x720 -- --visual
```

## 胜利音效补全

原实现结算时仅播放一次 `GUIWinStars`，遗漏了 `GUIQuestCompleted` 胜利主音效，且战斗音乐继续播放。现按 Dove `VictoryView:show` 停止战斗音频并播放主音效；星星动画及第一颗星音效延后 0.65 秒，之后每隔 0.7 秒播放一颗，次数与实际星级一致。重开会清除结算音频进度并恢复备战音乐，结算期间的输入解锁不会重新启动战斗背景音乐。

仅补充前三关声音清单与音频资源依赖，未重新裁剪图集。`tests/verify_victory_audio.gd` 的 headless 29 项和 Godot 原生 34 项专项检查通过，覆盖 1–3 星、重复结算、重开清理、实际播放器及音频解锁；这些检查使用受控结算状态，不重复完整战役。该轮交付与资源校验结果见 `reports/victory_audio_delivery.json`，浏览器验收仍由用户手动完成。

## 技能冷却结束与禁用点击

原实现把每次进入可用状态都映射为 `fire_ready` / `reinforcement_ready` 的 30–44 帧，因此冷却结束和取消选中也会播放首次解锁的开门动画。现按 Dove `PowerButton`、`Power1Button`、`Power2Button` 区分转换：冷却归零使用 1–28 帧就绪闪光和 `GUISpellRefresh` 音效；30–44 帧只用于真正的锁定到解锁（首关教学，或第二、三关发送第一波）；备战期显示锁定帧，取消选中直接恢复正常按钮。冷却遮罩和选中帧保留。提前开波奖励使冷却归零时也走就绪转换。

按 Dove 桌面行为忽略冷却中、未解锁技能的点击和快捷键，保留当前选择与瞄准状态，不弹中央文字、不播放点击音，并消费禁用按钮点击，避免将其当作战场落点。

本轮仅运行 `tests/verify_power_feedback.gd`：headless 29 项及 Godot 原生 34 项通过，原生窗口保存冷却、就绪闪光及可用状态 3 张截图。声音清单补充刷新音效，图集保持不变；集中导出一次 release Web 并检查隔离 PCK。最新交付报告为 `reports/power_feedback_delivery.json`。

## 技能落点提示与 Web 音乐

Dove 的 `TB_ROAD` 属于首关新技能教学链：`TB_POWER1` / `TB_POWER2` 被首次选中后才衔接一次，并在技能使用或取消时移除。原实现把它直接绑定到 `targeting != ""`，导致前三关每次选择技能都显示“单击道路”。按本项目交互要求已取消该落点文字气泡；技能指针、合法落点判断及首关新技能提示保留。

Web 音乐现统一由 `menu_audio.gd` 管理流切换、循环、音量、停止和释放。浏览器首次鼠标、键盘、触摸或手柄输入会解锁声音；首次解锁在后续两帧重新挂载当前音乐，地图和战斗切换继续沿用同一播放器。触摸输入此前未纳入全局解锁，本轮一并补上。

初次探针只确认 OGG 已解码和 `AudioBufferSourceNode` 已启动，不能证明最终有声；用户复验及目的端分析器均确认该包仍为静音。根因位于 Godot 4.7 Web 的 Sample 播放路径：采样节点具备非零缓冲，但送到最终输出的信号为零。现将运行时创建的音乐、公共点击、地图、英雄房间和战斗音效播放器显式设置为 `AudioServer.PLAYBACK_TYPE_STREAM`，并把 Web 默认播放类型同步设为 Stream。修复后的 release 包在不使用自动播放豁免参数时，首次点击后 `AudioContext` 为 `running`，最终 `AudioWorkletNode` 实测 RMS `0.05134`、峰值 `0.11197`，不再用解码缓冲数值代替输出结论。

同时按 Dove `next-wave-sent` 修正技能时机：第二、三关备战期两项技能均锁定，第一波实际发送后一起解锁；模拟器命令、按钮和快捷键均执行该约束。首关第三/第七波教学解锁保持不变。`tests/verify_targeting_music.gd` headless 26 项、`tests/verify_power_feedback.gd` headless 35 项及 Godot 原生 40 项专项检查通过，隔离 PCK 479 个文件检查通过；未重复完整战役与多分辨率回归。结果见 `reports/targeting_music_delivery.json`。
