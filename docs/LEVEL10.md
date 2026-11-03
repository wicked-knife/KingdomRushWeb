# 第十关「废弃之地」与特斯拉

基准为 Dove 2.1.0.6／`4072b18bf4e418eec8b813a960c83003744cb710`。第一至十关开放战役、英雄挑战、钢铁挑战，共 30 个组合，第十一关保留预览。

| 模式 | 金币 | 生命 | 波数 | 科技上限 |
| --- | ---: | ---: | ---: | ---: |
| 战役 | 800 | 20 | 19 | 6 |
| 英雄挑战 | 1800 | 1 | 6 | 5 |
| 钢铁挑战 | 2200 | 1 | 1 | 5 |

三模式有 14 处塔位、两个入口。钢铁挑战禁止新建炮塔。布局、完整波次、路线、出生时间和模式限制直接核对冻结源数据；26 波共 1160 次出生，不以 AI 通关作为验收条件。

## 行为与生命周期

特斯拉接入三级炮塔分支、连锁和超载技能，永久解锁后可以在此前允许高级塔的关卡回玩。第 4–9 关补齐资源，存档与模式禁塔仍生效。普通攻击严格遵循源冷却、起手、发射、结束回到待机；连锁跟随命中点、排除重复目标，基础两次跳跃，技能增加跳跃次数。电伤使用一半物理护甲，科技同时消费价格、射程、冷却和连锁伤害字段。

射线、分段伤害、超载光环和粒子分别结束与清理。独立执行源塔协程的五种场景、四档连锁，以及实际 `mod_dps.insert/update` 的逐次伤害时刻；浮点时钟采用源绝对秒数比较，避免把分段伤害简化成固定两帧一次。

恶魔死亡爆炸与死亡动画并行，遵循禁止生成的伤害类型。恶魔法师施放四击护盾；电击的同一伤害来源只消耗一击，护盾忽略／贯穿标记单独处理。沉默抑制施法；沉默恶魔死亡使用源分解特效，同时保留并行爆炸。

墓地定时收集符合源标记、尸龄和生命阈值的尸体，依次生成小／大骷髅。复活动画结束后移动到源路线节点，保留金币；同一尸体只消费一次。大骷髅光环延迟出现并淡入，停止后增益按源持续时间释放。结算等待墓地宽限和最后一个敌人的死亡动画；重开清空队列与时钟。

魔法师弹丸保留源金色星形主图，补齐 `ps_bolt_sorcerer` 拖尾。粒子按源实际 runner 的平均寿命、发射频率、位置插值、缩放及透明度执行，命中停止发射，已发射粒子自然结束。

## 验证与交付

```powershell
python tools/prepare_level01.py --level 10
python tools/prepare_level10_reference.py
python tools/prepare_upgrades.py --reference --reference-level 10
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level10.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level10_upgrades.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level10_shared.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_sorcerer_trail.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_misc_presentation.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_battle_details.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_hero_malik.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x720 --script tests/level10_visual.gd
4..10 | ForEach-Object { python tools/verify_level01_assets.py --level $_ }
python tools/verify_level10_delivery.py
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
```

当前专项为 168 项第十关逻辑检查、16 组源科技配置和原生 1280×720 流程检查；共享行为使用代表场景，无全战役回放或多分辨率重复执行。`level10_delivery.json` 检查当前报告的文件哈希、像素证据、依赖缺失负向探针，并验证导出资源清单。

`tests/fixtures/level10_additions.json` 精确声明相对 `1775c0e` 的新增模板、菜单、升级边及图集重排；旧关卡配置保持不变。目录中的 `layout_instance_aliases` 固定已发布的场景实例身份，避免新增模板改变旧实例编号。历史快照、旧增量声明及报告不改写为本轮通过；当前发布使用第十关专项与共享回归，不要求过期历史报告重新跑完整流程。

发布包为 `build/KingdomRush-KR1-Levels01-10-Web.zip`，包含此前 UI、冻结交互、死亡结算修复。本轮集中导出一次并检查隔离 PCK、ZIP 与资源哈希；浏览器输入、音频解锁和持久化由用户手动验收。

## 连锁闪电动画专项修正

新增四个实际源协程场景：移动目标、斜向连锁、起点瞬移、终点瞬移。逐帧比较位置、角度、横纵缩放、隐藏状态、动画帧与清理时刻。修正跳跃等待期间过早追踪、瞬移时过早取消已排定跳跃，以及新射线在入队初始化前闪现默认水平贴图的问题。新射线按源等待下一帧初始化；命中特效仍随射线实际开始插入。

专项入口为 headless `tests/verify_tesla_animation.gd` 与原生 `tests/tesla_animation_visual.gd`，后者以源逐帧结果核对实际渲染队列。后续导出需要这两份当前报告；本次局部检查不重复导出 Web。
