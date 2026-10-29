# 关卡统一接入

基准及当前范围见 [复刻指南](GODOT_WEB_REMAKE_GUIDE.md)。前七关 21 个组合与游侠测试场共用导出链路；公开的 `CampaignLevels.supports()`、`load_definition()` 与存档格式保持兼容。

## 职责

| 入口 | 职责 |
| --- | --- |
| `data/campaign_content.json` | 唯一当前源基准、关卡／模式／难度、资源目录、能力、控制器、源行为别名 |
| `tools/dove_source.py` | 共用基准读取与干净源码检查 |
| `tools/campaign_content.py` | 合并能力、验证模板依赖、行为、模式与源基准 |
| `tools/level01_export/capabilities.lua` | 按来源装载普通单位、塔与 Boss 模板和回调 |
| `tools/level01_export/main.lua` | 隔离求值布局、路径、网格、波次和模板，递归依赖并保留源行为 ID |
| `tools/prepare_level01.py` | 转换模式覆盖、数值、通知、禁塔、升级限制、UI、图集、动画与声音 |
| `scripts/services/campaign_levels.gd` | 验证当前基准并加载独立模式；目录查询缓存，运行实例深拷贝 |
| `scripts/services/battle_setup.gd` | 地图／战斗边界：深拷贝通知、存档禁塔和购买科技；不改变关卡加载接口 |
| `scripts/battle/dove_upgrades.gd` | 默认方案的显式 ID 适配、模板补丁、科技上限和运行时行为 |
| `tools/upgrades_contract.py` | 逐科技追踪可达模板、动画、帧与声音；缺项阻止导出 |
| `scripts/battle/dove_behaviors.gd` | 显式源 ID 到 Godot 模块分派；只接受登记的等价名称 |
| `tools/web_bootstrap.py` | 同一目录生成发布文件清单与组合回执 |

目录不手填金币、生命和波次；这些字段来自 Dove。导出沿波次与布局追踪弹丸、士兵、召唤物、状态、光环、生成器、动画与声音；能力声明补充可购买而未出现在初始布局的塔。缺少资源、模板、行为、回调或模式时，必须报告内容 ID、引用者和缺项，阻止开放。

## 控制器

每局独立控制器，不保留跨局模拟器引用。`reset` 初始化通知；`wave_notification` 处理入口通知；`wave_started` 在队列排序后、开波事件前调用；`step` 在出生与自动开波后执行；`enemy_died` 由源行为死亡分支调用一次；`can_finish` 在全帧更新清理后决定可否结算，生命归零优先判负。

默认控制器处理普通通知和流程，首关控制器承接教学，第六关控制器处理毁灭者死亡清场。Boss 完成不可中断动作后触发死亡分支；清理当前及待插入敌人、取消金币、停止生成器。胜利检查出生队列、存活敌人、洞内实体及待插入实体，不额外等待尸体。蜘蛛卵的语义见 [战斗行为](BATTLE_BEHAVIOR.md)。

## 新关卡接入

1. 在目录 `levels` 中登记源关卡 ID、资源目录、三个模式、难度、复用能力和控制器。普通流程使用 `default`，有专属逻辑才增加控制器。
2. 执行 `python tools/prepare_level01.py --level N`；源数据转换与引用检查成功后才开放。
3. 核对三个模式的玩法字段与完整出生列表。共用机制用代表场景回归，新机制单独增加模块及源样本。动画除资源外，还必须核对实际源脚本的开始、循环、结束、后继状态与生命周期，检查实际渲染队列及原生关键帧，不能只验证导出了哪些帧。
4. 交付时集中导出 Web 并检查隔离 PCK；浏览器由用户验收。

新机制在 `dove_behaviors.gd` 注册源 ID，并按需扩展 `capabilities.lua`、Lua 和 Python 引用字段检查。共享行为和 UI 不按关卡编号分派。转换器当前只覆盖已核实的 Lua 波次与普通难度 2，其他世代、TSV 或未支持 Boss 须先扩展能力。

选择贴花、技能等级灯偏移与共用动画都由源 UI 导出，不为新关卡手填。表现时钟与战斗随机数独立。`--reuse-resources` 仅适用于源输入、玩法和媒体完全未变的接入元数据更新；同步新版源码应正常重新生成。

科技规则和扩展步骤见 [默认科技闭环](DEFAULT_UPGRADES.md)。新关卡必须同时包含当前已开放科技对该关可达内容的依赖，不因测试使用零科技而省略。关卡目录中的 `layout_instance_base` 固定历史布局实例的命名起点，新增依赖不能重命名旧卫兵、鱼或背景实例。

源表现字段必须追踪到消费代码：例如 `render.sprites.loop=false` 不能被通用状态名判断改为循环；`unit.hide_after_death=true` 要在死亡动作结束时隐藏，不能等同于 `health.dead_lifetime` 到期移除。源字段已导出、引用检查通过、旧快照稳定，均不足以单独证明这类脚本语义已实现。新增机制按生命周期种类选代表单位检查，不在每关重复同一场景。
