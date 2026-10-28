# 关卡统一接入与行为复用

实施日期：2026-10-28。玩法基准保持 Dove `2.1.0.2` / `e29ece82939fd73fb69bfc4b469d484a72e4dfd2`。本文件包含前五关迁移历史与第六关增量；当前范围以开头的 18 个组合为准。

前六关的战役、英雄挑战、钢铁挑战共 **18 个组合**使用同一内容目录、加载器和控制器接口。游侠测试场也通过同一导出链路生成。第六关增加飞行、敌方远程、独立卫兵、圣骑士、奥术塔与毁灭者，见 [第六关交付](LEVEL06_DELIVERY.md)。第七关保持预览；英雄参战与科技尚未开放。存档格式、公开的 `CampaignLevels.supports()` / `load_definition()` 和原有工具参数保持兼容。

## 接入结构

| 入口 | 职责 |
| --- | --- |
| `data/campaign_content.json` | 登记开放关卡、模式、难度、文件夹、控制器、导出能力及源行为别名；不存金币、生命或波次数值 |
| `tools/campaign_content.py` | 共用目录读取、能力合并、模板引用及源行为验证 |
| `tools/level01_export/capabilities.lua` | 按来源装载普通单位、专属塔与 Boss 模板及回调，供多个关卡复用 |
| `tools/level01_export/main.lua` | 安全求值源模板、布局、路径、网格和波次，输出行为 ID 与模板依赖 |
| `tools/prepare_level01.py` | 转换三种模式、布局覆盖、规则、图集、动画和声音；验证后生成关卡资源 |
| `scripts/services/campaign_levels.gd` | 读取同一目录，加载独立模式数据并检查资源、控制器、行为和依赖；地图高频查询使用内存目录 |
| `scripts/battle/dove_level_controller.gd` | 控制器契约与注册控制器工厂 |
| `scripts/battle/dove_behaviors.gd` | 显式源行为 ID → 现有 Godot 模块分派；不按函数后缀猜测等价关系 |
| `tools/web_bootstrap.py` | 从同一目录及各资源 manifest 生成发布文件列表与组合回执 |

金币、生命、波次、出生时间、布局、禁塔和升级限制仍来自源数据。两处源 GUI 缺少定义的通知适配记录在内容登记中；游侠测试场保留已有的图集子集，排除不使用的战役／挑战图标，避免无必要重打包。

## 运行时约定

每局拥有独立控制器实例，不保存模拟器引用。默认控制器负责首波前的通知和普通胜利条件；首关控制器负责三页教学及首波通知差异。源布局中的技能锁定仍由共用开波流程处理。

| 钩子 | 调用位置 |
| --- | --- |
| `reset(sim)` | 清理旧实体后，初始化本局通知；不改变原 RNG 和装饰初始化顺序 |
| `wave_notification(sim, entry)` | 每条路线原通知位置，紧接着仍发出原 `tip` 事件，保留通知／提示顺序 |
| `wave_started(sim, group)` | 出生队列排序、更新该波结束时间后，发出原开波事件前 |
| `step(sim)` | 定时出生及自动开波之后、装饰和战斗更新之前；现有两个控制器此处为空 |
| `enemy_died(sim, enemy)` | 源行为死亡分支调用一次；默认空实现，第六关在毁灭者完成不可中断的施法后清场 |
| `can_finish(sim)` | 本帧所有实体更新和清理之后；生命耗尽仍优先判负 |

保留现有共用模拟器 `level01_sim.gd` 的路径和算法。每帧按「状态 → 上帧待插入实体 → 定时出生／开波 → 控制器 → 装饰 → 蜘蛛卵／生成器／光环 → 空间索引 → 塔 → 士兵 → 敌人 → 弹丸 → 清理 → 结算」执行。未孵化蜘蛛卵不阻止胜利；同帧到期孵化的小蜘蛛先插入，再参与胜利判断。第六关还检查待插入实体及尚未执行死亡分支的 Boss，生命归零始终优先判负；不等待完整尸体时间。

游侠升级／技能／攻击、精灵营地修复／招募／技能／远程、母蛛初始化／产卵、萨满治疗与弹丸类别均经注册表调用原实现。状态、光环、孵化器的源更新 ID 也纳入登记检查；其计算仍由既有模块处理，没有新建完整 ECS。普通移动、攻击、伤害和状态计算未重写。

源脚本存在经过继承转发的名称，例如 `game_scripts.arrow_missile.update` 与 `scripts.arrow_missile.update`；只接受目录中明确登记的等价别名。未知名称、缺少模板依赖或控制器、缺少模式和必需资源会报内容 ID、引用者及缺项，阻止对应内容加载／发布。

新增能力按组件和源 ID 分派：`dove_targeting.gd` 处理敌我、可见性及伤害过滤；`dove_enemy_ranged.gd` 处理远程敌人；`dove_paladin.gd` 处理多招式近战和圣骑士技能；`dove_arcane.gd` 处理射线、死亡射线、传送与光环；`dove_enemy_projectiles.gd` 和 `dove_spawner.gd` 分别处理导弹／投弹、待插入召唤；`dove_juggernaut.gd` 保留 Boss 动作顺序。场景清场属于 `controllers/level06.gd`，主循环不判断关卡编号。

目录的 `features` 合并可购买塔、菜单、升级目标、动态文案前缀、模板引用字段和已检查回调。导出器逐个装载来源模板，递归收集 `hit_payload`、光环、生成器、粒子与分解特效；源回调使用显式 allowlist，未知行为、回调或组件拒绝导出。只在适用能力中声明新增引用字段，避免无关旧关卡扩包。

共用战斗表现由 `battle_feedback.gd`（选择贴花、集结与施法指示器、系统鼠标生命周期）、`battle_wave_flags.gd`（开波确认与预告弹窗）、`battle_ui.gd`（塔菜单与购买动画）及 `battle_victory.gd`（胜利徽章、星星、链条和独立粒子）处理。动画使用表现时钟，不增加模拟步骤或战斗随机数调用；前六关及游侠测试场共用，无关卡编号分支。

导出 `ui.selection_markers` 保存源选择贴花的名称、锚点和地面层级，单位位置再叠加既有 `unit.marker_offset`；`ui.tower_menu_power_offset` 保存源技能等级灯的三个偏移。`decal_rally_feedback` 是动画 ID，须连同实际 `rally_feedback` 帧族导出。新增关卡沿用转换器共用 UI 资源收集，不手填这两份元数据。具体行为与再生成后的资源核对见 [战斗 UI 修正](BATTLE_UI_ALIGNMENT.md)。

## 后续关卡怎么接

1. 在 `campaign_content.json` 的 `levels` 增加登记，填写源关卡 ID、资源文件夹、模式／难度、复用的 `features` 和控制器。现有流程选择 `default`，有专属脚本才声明新控制器；控制器路径登记在 `controllers`，Web 工具自动收集。
2. 运行 `python tools/prepare_level01.py --level N`。波次与布局为依赖入口，递归收集弹丸、士兵、召唤物、状态、特效，再追踪动画与声音。目录中的能力模板列表补充可购买但未在初始布局中的塔和技能。实例覆盖后会重新计算依赖。
3. 核对来源、数据、时间线与受影响机制。确认可开放后保留内容登记，交付时集中导出 Web。无需修改加载器、导出器或战斗主循环中的关卡编号范围。

新机制单独增加共享行为模块：必要时扩展 `capabilities.lua` 的源模板适配，登记源行为 ID，并在 `dove_behaviors.gd` 接入实现和专项检查。若出现新的模板引用字段，同时扩展 Lua 导出器与 Python 的引用字段表。不要把新行为伪装为已支持的源行为，也不要向主循环追加关卡编号判断。

当前转换器覆盖本批次已核实的 **Lua 波次与普通难度 2**。Dove 的 TSV 优先加载、其他世代及其他 Boss 仍须按来源扩展适配；目录登记本身不代表这些内容已经受支持。`hit_fx_water` 保留原模拟器的条件回退，不作为本批前三级塔的强制新依赖；已有前三关资源不因此扩包。装饰仍复用既有动画和交互流程，本轮行为登记覆盖已实现的战斗行为。

## 生成与验证

上次未完成试改已留档在 `output/content_unification_trial_20261028/`，恢复改动前基线后分步迁移，采集样本保留。迁移前金样登记在 `tests/fixtures/campaign_content_baseline.json`、`content_combat_baseline.json` 和 `content_timelines.json`。

```powershell
# 正常新增或修改资源
python tools/prepare_level01.py --level 5
python tools/prepare_level01.py --all
python tools/prepare_level01.py --ranger-arena

# 仅更新接入元数据；源输入或任一玩法字段变化、资源缺失时直接拒绝
python tools/prepare_level01.py --all --reuse-resources
python tools/verify_content_catalog.py

& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_content_unification.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_ranger.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level05.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_challenges.gd

& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/content_tutorial_visual.gd --resolution 1280x720
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/challenges_visual.gd --resolution 1280x720

# 交付时集中一次；浏览器由用户手动验收
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
```

第五关机制检查默认不跑完整回放；按需加 `-- --full-replay`。挑战完整回放仍通过 `-- --with-replays` 显式启用。

## 前五关迁移验证口径（历史基线）

- 六份定义（前五关及游侠场地）除新增 `behaviors`、`dependencies`、`level.controller` 外，玩法全部字段与迁移前一致；源输入哈希单独比较一致。74 份资源文件保持不变，JSON 使用规范化比较，图片使用字节哈希。
- 15 个组合、88 波、2794 条实际波次出生记录完整比较时间、敌人、路线及固定支路。随机支路检查合法范围；完整的预期／实际列表及每波首次差异保存在本地 `reports/content_timelines.json`。
- 首关、第三关、第五关各 1200 帧，共 3600 帧；36 个采样点的单位、塔、弹丸、状态、蜘蛛卵和 RNG 状态均与迁移前哈希相同。这是固定种子的回归证据，不代表穷举全部战斗。
- 另查萨满冷却／施法／死亡边界、游侠、营地、状态、蜘蛛同帧孵化和结算；挑战检查覆盖禁塔、免费塔、升级限制、成绩及存档。
- 原生 1280×720 检查首关教学与两次技能教学确认、挑战入口、第五关钢铁双营地的修复／招募／技能及结算路由；截图经过检查。使用开发跳波构造教学边界、真实胜利事件构造结算，不宣称完成正常经济通关。
- Web 使用 release 导出和隔离资源命名空间的 PCK 检查；实际结果见 `reports/content_unification_delivery.json`。本轮未自动操作浏览器，未运行完整通关回放。
