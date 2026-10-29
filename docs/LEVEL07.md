# 第七关、火枪塔与分支升级

基准为 Dove 2.1.0.3／`1a863df00b08f6bf1018ae0b0e7e4e106b939082`。战役、英雄挑战、钢铁挑战均使用普通难度 2、默认科技方案 1，无英雄参战。初始金币 700／1000／1200，生命 20／1／1，波数 16／6／1。第八关仍为地图预览。

三级箭塔的 `upgrade_targets` 为有序数组 `["tower_ranger", "tower_musketeer"]`，仍兼容旧字符串。`upgrade_options(tower)` 返回完整候选；`upgrade_target(tower)` 仅在一个候选时返回目标。交易必须传入 `upgrade_to` 并检查候选、锁定、资金和施工状态。菜单使用源位置 5／6，逐项显示锁、价格、说明和范围预览。第四至六关补齐所需模板和图集，回玩时按存档与源禁塔生效。

第七关布局立即允许火枪塔；胜利先写入 `last_victory`，返回地图后才提交永久解锁。沿用现有槽位格式和两阶段结算。钢铁挑战保留三座免费二级兵营，禁建兵营与炮塔。

`dove_musketeer.gd` 对应源塔协程及 shotgun、bomb 弹丸：双射手交替；秒杀、狙击、霰弹、普通射击依次检查；技能结束后继续本轮攻击；保留严格冷却比较、射击等待、Boss／秒杀禁用例外、目标死亡重选。霰弹的远距离减伤、冷却修正和散布在开始瞄准时确定，六弹的落点预测在发射时确定。霰弹沿源离散重力积分及提前一 tick 的停止条件运行。炮兵效率按源共用 bomb 脚本影响霰弹，但炮兵伤害科技不将火枪弹归入炮塔组。枪弹接入精准、破甲、流血及伤害倍率。瞄准标记按 mod_track_target 的持续时间结束；射手临时绘制顺序在动作结束后恢复。

`dove_snow.gd` 复用源 tunnel、aura_unit_regen、粒子和洞口灯光语义。隧道按移除状态前的实际速度计算通过时间；移出战斗实体表，清除状态／光环、解除阻挡，保留实体及子路线，逆序释放队列并恢复回血光环。洞内单位不能被选择或攻击，仍阻止胜利。重开清空队列。巨魔回血遵循源冷却、沉默重置、忽略眩晕与 F_MOD 禁用；白狼复用近战闪避／魔抗，死亡动画结束隐藏，按尸体寿命清理实体。雪地塔基、洞口遮挡、占用灯光、降雪、山羊八次点击及源音乐均有运行时消费者。

行为由统一目录注册，使用默认控制器，主循环没有第七关编号分支。目录 `runtime_dependencies` 为跨模块隐式资源提供入口与导出阻断检查。

## 验证与重现

```powershell
python tools/prepare_level01.py --level 7
python tools/prepare_level07_reference.py
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level07.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x720 --script tests/level07_visual.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1024x768 --script tests/level07_visual.gd -- --layout-only
python tools/verify_level01_assets.py --level 7
python tools/verify_level07_delivery.py
```

独立样本执行冻结源的实际波次、火枪塔、shotgun、bomb、tunnel、aura_unit_regen 函数／协程。三个模式全部 708 条出生记录按波次比较；随机子路线比较合法范围。机制样本隔离引擎服务与随机选择，逐帧／逐事件保存完整预期、实际及首次差异。`reports/level07_logic.json` 计数独立模式和场景；完整比较保存在本地 `level07_timelines.json`、`level07_comparisons.json`。

原生主分辨率覆盖分支菜单、技能购买、动作关键帧与结束状态、隧道灯光及出洞、白狼死亡隐藏／清理、山羊、音乐和入口／重开／结算。额外分辨率只检查受影响布局。使用独立测试存档，构造胜利结果验证结算，不代表 AI 完整通关。

旧关零科技战斗快照保持原样。`tests/fixtures/level07_additions.json` 明确枚举新增键及升级边转换；旧单位属性、波次、布局、界面元数据及源像素单独核对，图集重新打包不更新历史预期。发布检查要求第七关逻辑、两份原生报告、像素检查和回归均有效且哈希未过期。集中导出一次 release 包 `build/KingdomRush-KR1-Levels01-07-Web.zip`，隔离 PCK 与 ZIP 完整性由脚本检查，浏览器由用户手动验收。

后续八项反馈修复见 [FEEDBACK_REPAIRS.md](FEEDBACK_REPAIRS.md)。旧零科技基准文件仍保持原样；普通炮弹的源行为修正通过逐采样审计覆盖，新增门禁要求专项逻辑、原生界面和资源报告有效。
