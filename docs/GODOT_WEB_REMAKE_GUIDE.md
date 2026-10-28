# Kingdom Rush Dove → Godot Web 复刻指导文档

版本基准：**Dove 2.1.0.2**。调研与编制日期：2026-10-24；源码与资源基准更新日期：2026-10-25。目标工程：`D:/projects/KingdomRushWeb`。

本文是后续开发的实施依据，覆盖源码定位、技术设计、内容迁移、任务拆分和验收。**工程已有素材链路、启动加载、主菜单和第一代前六关三模式闭环；首关历史结果见 [首关交付报告](LEVEL01_DELIVERY.md)，第二、三关实现及验证边界见 [第二、三关交付](LEVEL02_03_DELIVERY.md)。第四关、三级基础塔和当前验证范围见 [第四关与三级塔交付](LEVEL04_TIER3_DELIVERY.md)。地图旗帜高亮、兵营/援军重新寻敌和出怪口开波图标的后续修正见 [交互修正报告](INTERACTION_FIXES.md)。文中的其他通用服务、关卡能力和数据结构，除明确标为已有者外，均待实现。**

**2026-10-27 增量进度：第五关「银橡森林」普通战役、精灵营地、狼／大小蜘蛛／掠夺者已实现，游侠与两项三级技能正式开放。第四关结算后开放第五关，第五关结算后保存最好星级并解锁第六关预览；前四关限制不变。Godot 专项、合法通关和两种窗口尺寸检查已完成，Web 包更新至前五关，浏览器由用户验收。见 [第五关与精灵营地交付](LEVEL05_ELF_DELIVERY.md)。游侠独立场地继续保留，见 [游侠交付](RANGER_DELIVERY.md)。**

**2026-10-28 第六关接入：前六关战役、英雄挑战、钢铁挑战共 18 个组合开放，普通难度 2、零科技、无英雄参战。新增飞行过滤、敌方远程、独立卫兵、圣骑士与奥术全部技能、毁灭者导弹／召唤／清场。专属流程通过第六关控制器接入，第七关保持预览；前五关数据、资源与代表战斗基线不变。当前实现、验证范围和 Web 包以 [第六关交付](LEVEL06_DELIVERY.md) 为准，下方早期交付段落保留历史。**

## 阅读方式与约定

**2026-10-28 统一接入：前五关全部 15 个关卡／模式组合与游侠测试场已迁移到共享内容目录、能力导出适配、关卡控制器和源行为注册表。玩法与存档保持原状，第六关继续预览。后续已有机制关卡按登记与源数据转换接入，专属流程通过控制器扩展。实现边界、验证证据与接入步骤见 [统一接入说明](CONTENT_INTEGRATION.md)。**

**2026-10-27 存档调整：已采用 Dove 统一 JSON 槽位、数字模式成绩、`seen`、锁定塔和 `last_victory` 两阶段结算；区间规则覆盖全部源世代。早期存档迁移与索引机制已移除，详见 [统一槽位交付](DOVE_SAVES_DELIVERY.md)。**

- **【事实】**：已读取代码、Git 对象、现有资源或校验报告得到的结论。
- **【设计】**：本项目建议采用的实现约定，不表示原版已经如此实现。
- **【验证任务】**：必须在对应里程碑用真实数据或浏览器完成的验证，不视为已通过。
- `WEB` 指本工程；`SNAPSHOT` 指 `WEB/source_assets/kingdom_rush_dove`；`SRC` 指 `D:/projects/KingdomRushDove`；`BASE` 指 Dove `2.1.0.2` 的冻结提交 `e29ece82939fd73fb69bfc4b469d484a72e4dfd2`。
- 本文源码链接指向相邻源码工作目录；已核对 SRC、安装目录和 SNAPSHOT 均对应上述版本与提交。实施时按 BASE 读取代码，并校验资源清单与来源哈希。
- 同一功能的完成顺序是：确认原行为 → 整理依赖与样例 → 实现通用能力 → 对照验证 → 批量迁移内容。素材能显示不等于玩法已还原。

## 目录

1. [目标、基准与当前状态](#s01)
2. [原项目运行架构](#s02)
3. [源码阅读与迁移索引](#s03)
4. [Godot 总体架构与接口](#s04)
5. [数据提取、转换和内容管理](#s05)
6. [素材、普通动画和 EXO3](#s06)
7. [时间、命令与实体生命周期](#s07)
8. [路径、地形、集结与索敌](#s08)
9. [战斗与数值规则](#s09)
10. [塔、士兵、英雄与 Boss](#s10)
11. [完整玩家流程与界面](#s11)
12. [Dove 扩展玩法](#s12)
13. [文本、音频和存档](#s13)
14. [Web 加载、导出和发布](#s14)
15. [里程碑与首批任务](#s15)
16. [验收体系与完成定义](#s16)
17. [附录 A：2.1.0.2 基准与内容核对](#appendix-a)
18. [附录 B：2.1.0.2 素材告警](#appendix-b)
19. [附录 C：命令与官方资料](#appendix-c)

<a id="s01"></a>
## 1. 目标、基准与当前状态

### 1.1 复刻范围

【设计】最终覆盖 Dove `2.1.0.2` 向玩家提供的完整内容：实际开放的多代地图与关卡、战役/英雄/钢铁挑战、难度、基础及扩展塔、士兵、英雄、Boss、技能、科技、图鉴、成就、玩家设置、无尽和回溯。源码中的地图入口涉及代际 1、2、3、5、6；不能根据 `kr1` 目录名推断只有第一代，也不能自行承诺存在第四代完整地图。

首版验收桌面 Chrome、Edge、Firefox 的鼠标键盘流程。手机触控、移动 Safari、桌面 Safari 的正式适配放在后续兼容阶段。新建浏览器存档，并提供 JSON 备份与恢复。原 Lua 存档导入可另行实现。

以下内容不作为本轮复刻目标：原开发用关卡/波次/图集编辑器、原桌面更新器、任意 Lua 插件二进制或源码兼容、云存档与账号服务。关卡专属的可点击机关属于玩家玩法，仍需迁移；不能因为它使用编辑器生成数据就排除。

### 1.2 唯一版本基准：2.1.0.2

| 来源 | 已验证标识 | 使用规则 |
| --- | --- | --- |
| SRC 源码 | `id=2.1.0.2`；HEAD 为 `e29ece82939fd73fb69bfc4b469d484a72e4dfd2`，工作区干净 | 完整玩法代码、数值和行为的冻结依据 |
| 本机安装目录 | `D:/王国保卫战Dove版/KingdomRushDove`；`id=2.1.0.2`，提交记录与 BASE 一致 | 同版本运行对照与原始素材来源 |
| SNAPSHOT | `id=2.1.0.2`，提交记录与 BASE 一致 | 保存原始素材及配套数据；完整运行时代码仍从 SRC 读取 |
| Godot 运行素材 | 当前 manifest 与校验汇总对应 `2.1.0.2` | 所有资源包从这份配套资源生成，逐项保留来源哈希 |

【事实】源码、安装目录和工程素材快照的版本标识与提交一致。`tower_forger`（奥术幻铸师）、`tower_sentry`（哨兵瞭望塔）属于本版本的完整复刻范围，其模板、行为、技能、菜单、文案、图集、EXO 和声音均须纳入内容迁移清单。

【设计】M0 在隔离目录建立 BASE 只读导出副本，玩法数据、资源依赖和原版对照样本统一使用 `2.1.0.2`。生成基准清单，记录提交、工作区状态、版本文件、资源 manifest 哈希及每个导出输入的哈希；发现不匹配则阻止该批导出。后续更新内容时同步更新该清单、玩法数据、行为和验收样本。

### 1.2.1 2026-10-25 同版本更新

【事实】源码从 `e4278f83d913f96a8d35a17f912e0c21945bfdac` 快进 7 个提交至 `e29ece82939fd73fb69bfc4b469d484a72e4dfd2`，版本号仍为 `2.1.0.2`。本机安装目录的更新记录与新 HEAD 一致；本轮变更的 198 个源码/元数据文件已逐项核对与安装目录相同（不含由更新器记录安装提交的 `current_version_commit_hash.txt`）。因此后续迁移锁定新提交，仅凭版本号不能判断资源与行为是否配套。

更新包括 `go_enemies_T2-1`、`go_enemies_spiders-1` 两张 DDS 及对应图集元数据，未新增音频、字体、图集或 EXO；哨兵射程补偿倍率恢复为 1，流血倍率计算、攻击大眼报错及猎犬 flags 得到修正；树人单位移速及狼人化限制、部分塔技能升级回调和通用辅助函数也有调整。配套快照中更新了 78 份关卡脚本，许多变化是辅助函数与实体队列调用整理，不能按文件数量推断新增关卡。

本轮资源增量、来源哈希和验证范围见 [assets_sync_summary.json](../reports/assets_sync_summary.json)。本节记录源码与素材更新，相关战斗行为仍须在对应迁移阶段验收。

### 1.3 本工程已有能力

| 已有产物 | 能做什么 | 当前边界 |
| --- | --- | --- |
| [素材说明](ASSETS.md)、[转换器](../tools/import_dove_assets.py) | 原始资源复制、DDS 转 PNG、KRAB/动画/EXO3 元数据转换、哈希与像素校验 | 不转换完整玩法逻辑 |
| [DoveAssetCatalog](../scripts/dove_asset_catalog.gd) | 按需访问帧、图组、动画、EXO、声音和静态数据 | 不负责组合动画绘制、完整依赖分包和游戏对象生命周期 |
| [素材预览](../scenes/asset_preview.tscn) | 背景、裁切帧、普通动画、字体与音效展示 | 独立预览场景，不是游戏主场景 |
| [启动与主菜单](RUNNING.md)、[首页场景](../scenes/app_root.tscn) | 加载、原版菜单、音量持久化、弹窗与退出确认；裁剪 Web 导出入口 | 开始后选择存档槽进入地图，前六关三模式可玩；浏览器功能由用户手动验收 |
| [地图与英雄选择](HERO_SELECTION_DELIVERY.md) | 一代地图、三槽进度、79 名英雄资料与 373 条技能说明、原版解锁、双英雄选择及存档 | 前六关三模式可玩；英雄战斗行为尚未接入 |
| [第二、三关战役](LEVEL02_03_DELIVERY.md) | 按关卡裁剪与加载、双路出怪、二级塔、小狼闪避、萨满治疗、食人魔扣命、实际关卡结算 | 普通难度、无英雄参战和科技；第四关和前五关挑战已另行接通，挑战验收状态见下方 |
| [第四关与三级塔](LEVEL04_TIER3_DELIVERY.md) | 双子河畔、双入口、盗贼/强盗、四类二升三、骑士换兵、目标模板升级菜单、区间规则解锁 | 普通难度、无英雄参战、零科技；后续第五关已接通 |
| [游侠塔与独立场地](RANGER_DELIVERY.md) | 三级箭塔升游侠、双射手、毒箭／森林之怒各三级、状态叠加与多塔保护、可选敌人／数量／路线、清场及重置 | 独立场地不保存进度；第五关正式开放，前四关限制不变 |
| [第五关与精灵营地](LEVEL05_ELF_DELIVERY.md) | 银橡森林、15 波 242 名波次敌人、独立蜘蛛孵化、预置箭塔、游侠解锁、四人营地、流血／致残、合法通关回放、前五关 Web 包 | 普通难度、无英雄参战、零科技；第六关现已接通，见后续交付 |
| [前五关英雄／钢铁挑战](CHALLENGES_DELIVERY.md) | 十个模式的数据、三星准入、禁塔、模式结算、地图标记及原生界面已接入 | 普通难度、零科技；按 Dove 配置和功能一致性验收，不要求打通；已有 3 份回放作补充回归 |
| [内容统一接入](CONTENT_INTEGRATION.md) | 导出、运行时与 Web 清单共读目录；能力模板适配与源行为注册表；前六关 18 个组合及默认／首关／第六关控制器 | 保留既有地面战斗基线；尚未扩展 TSV、英雄战斗、科技；新机制须增加共享模块 |
| [第六关与共享战斗能力](LEVEL06_DELIVERY.md) | 三模式、飞行、暗影弓箭手、皇家卫兵、圣骑士／奥术全部技能、毁灭者、生成器、Boss 血条与结算、前六关 Web 包 | 普通难度 2、零科技、无英雄参战；第七关预览；浏览器由用户手动验收 |
| [转换测试](../tests/test_asset_conversion.py)、[Godot 校验](../tests/verify_godot_assets.gd) | 二进制转换样例和部分引擎资源加载检查 | 不证明战斗、EXO 显示、Web 导出已通过 |
| [汇总报告](../reports/verification_summary.json) | 记录已有导入及兼容渲染预览结果 | 已有素材检查结果，不代表完整游戏或浏览器验收通过 |

【事实】`project.godot` 当前采用 Compatibility 和 `canvas_items`，`run/main_scene` 为 `scenes/app_root.tscn`。已有启动加载、原版主菜单、音量设置及退出确认；开始后经三个独立存档槽进入一代地图，已接通第一代前六关普通战役、十二个挑战入口及 79 名英雄的资料、解锁与双选存档，制作人员入口仍为暂未开放提示。已有按菜单、地图、英雄房间和前六关 manifest 裁剪的单线程 Web 导出预设及工具，操作说明见 [RUNNING.md](RUNNING.md)。前六关按普通难度、无英雄参战与零科技完成闭环；第二、三关开放四类二级塔，第四关开放四类三级塔，第五关开放游侠与精灵营地，第六关开放圣骑士、奥术塔、飞行、远程敌人和首个 Boss，首关保留教学与塔级限制，十二个挑战的数据、限制、成绩及界面已接入，按 Dove 配置和功能一致性验收，不再以完整通关回放作为交付前置条件；其他完整玩法和动态分包仍待实现。Godot 4.7.2 stable 与对应单线程 Web 模板已安装。3D 物理 Jolt 的配置存在，但本项目的 2D 战斗不依赖它。

### 1.4 资源与内容规模

以下统计均对应 **2.1.0.2** 的当前 manifest、校验报告及素材目录，单位 GiB 为 2³⁰ 字节。

| 项目 | 数值 | 口径与约束 |
| --- | ---: | --- |
| 原始资源及配套数据 | 7,016 个文件 / 4,166,296,932 字节 | 约 3.88 GiB，包含原始格式 |
| Godot 运行资源 | 3,341,219,788 字节 | 约 3.11 GiB，不含 `.godot` 导入缓存 |
| 原 DDS / 运行 PNG | 582 / 590 | PNG 另含光标等非 DDS 来源图片；Godot 导入的 591 张纹理还包括工程图标 |
| 图集 / 标准帧 / 别名 | 490 / 158,627 / 136,501 | 帧 ID 必须带图集组，不能假设全局唯一 |
| 普通动画 / 动画帧引用 | 12,178 / 250,791 | 保留重复、倒序和零帧号 |
| EXO3 文件 / 组合动作 | 1,021 / 3,052 | 已转换数据不等于已有播放器 |
| OGG / 字体 | 3,899 / 8 | 声音定义带变体、分组和播放约束 |
| 中文 / 英文文案 | 9,573 / 9,573 | 含未求值的动态占位符 |
| 资产 JSON 文件 | 1,519 | 不含后续待生成的玩法 JSON |
| 布局 / 路径 / 网格文件 | 129 / 129 / 131 | 不能据此宣称 129 个完整可玩关卡 |
| Lua 波次：战役 / 英雄 / 钢铁 | 97 / 96 / 95 | 还需考虑 TSV、特殊关卡和专属生成逻辑 |
| TSV 波次文件 | 97 | 同一搜索来源下原加载器优先尝试 TSV |
| 当前源码索引缺失素材 | 0 | 索引完整不等于所有动画和 EXO 引用均无告警，见附录 B |

【事实】590 张 PNG 的 `宽×高×4` 累计为 **14,872,770,400 字节，约 13.85 GiB**。这只是基础 RGBA 数据估算，不包含 mipmap、驱动开销、双份解码和导入压缩差异，不是实测 GPU 占用。最大图片 `go_enemies_T3-1.png` 为 7732×7728，单张基础 RGBA 约 228 MiB；23 张图片至少一边超过 4096。

当前 [assets_manifest.json](../reports/assets_manifest.json) 的 SHA-256 为 `51c8c3dfb9a84433a6963d017bf79773a463145db146fbee518e8954fde2d887`。[verification_summary.json](../reports/verification_summary.json) 记录的安装版本为 `2.1.0.2`、提交为 BASE；文件哈希核对无错误，素材格式测试、Godot 导入与资源校验、Compatibility 素材预览已有通过记录。它们证明素材处理链路，不证明游戏玩法、Web 分包或浏览器性能已通过。

【结论】开发库可以全量保存；浏览器发布包必须裁剪依赖、分批下载并控制驻留资源。禁止先把全素材打进一个 PCK，再把运行崩溃当作后期优化。

<a id="s02"></a>
## 2. 原项目运行架构

### 2.1 启动和关卡初始化

【事实】原版入口建立全局平台/搜索路径、设置与语言，再由 loader 和 director 管理界面切换；桌面更新、公告及插件挂载属于外围功能。游戏关卡通过 `game`、`simulation` 和共享 `store` 运行。

~~~mermaid
flowchart TD
    A[main / loader] --> B[director 场景切换]
    B --> C[地图 / 选择 / 加载]
    C --> D[game 与 store]
    D --> E[simulation 系统调度]
    E --> F[关卡 / 波次 / 行为 / 战斗]
    F --> G[render / sound / HUD]
    F --> H[结算 / 成就 / 存档]
    H --> B
~~~

读取 `all/systems/level.lua:init_coroutined` 时，必须保留以下初始化依赖：

1. 从存档建立科技等级、科技列表、难度、法术选择。
2. 加载地形网格、敌人路径；按设置处理反向路径。
3. 加载基础组件及实体模板，再加载关卡 `required_templates` 和 `level:init` 的专属模板。
4. 注册选中的第三法术模板；原版执行热编译。
5. 应用难度及法术附加生命倍率，执行模板预计算。
6. 加载当前关卡模式的波次，加载动画与 EXO，清理上一局链接缓存。
7. 应用第三法术数值，再应用科技补丁，随后应用玩家配置；必要时进行敌人随机化。
8. 插入布局实体、禁用路径范围，执行关卡 `load`，建立初始金币、英雄经验倍率和锁塔条件。

【设计】Godot 不复刻原 Lua 热编译器；用“不可变基础模板 → 本局实例化与数值补丁”的管线替代。每一步输出应可检查，避免重开后在上次补丁上再次乘倍率。

### 2.2 store 与模板

【事实】`entity_db` 注册组件、注册并继承模板、创建实体；`store` 保存活跃实体、分类索引、时间、伤害队列、插入移除队列和关卡状态。模板本身包含数值、资源名、脚本函数和嵌套数据。许多功能在 `insert/remove` 或脚本协程中完成，并不都对应独立系统。

主要分类包括 enemies、soldiers、towers、modifiers、auras、particle_systems。`damage` 是队列消息，不应建模为附着在目标上的普通组件。分类索引及挂钩需要在正确的插入移除阶段维护，不能边遍历边任意删除集合。

### 2.3 实际系统顺序

【事实】BASE 的 `all/game.lua:game.simulation_systems` 顺序如下。`all/systems.lua` 负责可用模块注册，不是此运行顺序；项目说明中的系统清单需与此代码核对。

~~~text
level → wave_spawn → wave_spawn_tsv → mod_lifecycle → main_script
→ events → tween → endless → health → count_groups → tower
→ tower_skill → particle_system → render → timed → sound_events
→ enemy → last_hook → assets_checker
~~~

Lua 与 TSV 波次系统按实际格式选择启用；`lights` 在该清单中被注释。系统同时存在 `on_update` 与 `on_render_update` 通道，不能把显示帧更新机械并入战斗帧。

【设计】Godot 保留上述阶段的因果关系与队列可见性。初版可以合并实现文件，但不任意交换 modifier、行为、health、tower、timed 等阶段。若将索敌索引更新移到统一入口，必须验证其与原版的时序差异。

<a id="s03"></a>
## 3. 源码阅读与迁移索引

以下链接均用于定位 `2.1.0.2` 的 SRC 文件。导出时锁定 BASE，并按导出清单校验来源哈希；原项目的说明文档可辅助阅读，系统顺序和实际行为以本版本代码为准。

| 子系统 | 原实现入口 | Godot 对应工作 / 依赖 / 首要验收 |
| --- | --- | --- |
| 入口与场景 | [main.lua](../../KingdomRushDove/main.lua)、[director.lua](../../KingdomRushDove/all/director.lua) | AppRoot 与 ScreenRouter；依赖存档/资源；地图与关卡往返无残留 |
| 时间与主循环 | [game.lua](../../KingdomRushDove/all/game.lua)、[adaptive_fps.lua](../../KingdomRushDove/dove_modules/perf/adaptive_fps.lua) | SimulationClock、独立 UI 时钟；暂停倍速与后台恢复 |
| 调度与生命周期 | [simulation.lua](../../KingdomRushDove/all/simulation.lua)、[systems.lua](../../KingdomRushDove/all/systems.lua)、[last_hook.lua](../../KingdomRushDove/all/systems/last_hook.lua) | SimulationWorld、队列及索引；插入取消/死亡移除时序 |
| 模板与组件 | [entity_db.lua](../../KingdomRushDove/all/entity_db.lua)、[components.lua](../../KingdomRushDove/all/components.lua)、[templates.lua](../../KingdomRushDove/all/templates.lua) | 数据导出与 EntityFactory；继承、克隆隔离和默认值 |
| 关卡生命周期 | [level.lua](../../KingdomRushDove/all/systems/level.lua)、[level_utils.lua](../../KingdomRushDove/all/level_utils.lua) | LevelRunner、布局加载、结算；依赖波次/单位 |
| 关卡数据与脚本 | [level01_data.lua](../source_assets/kingdom_rush_dove/kr1/data/levels/level01_data.lua)、[level01.lua](../../KingdomRushDove/kr1/data/levels/level01.lua) | LevelDefinition 与专属状态机；不能只导出布局 |
| Lua 波次 | [wave_db.lua](../../KingdomRushDove/all/wave_db.lua)、[wave_spawn.lua](../../KingdomRushDove/all/systems/wave_spawn.lua)、[wave_utils.lua](../../KingdomRushDove/all/wave_utils.lua) | Lua 波次适配、提前开波奖励；出生顺序与时点 |
| TSV 波次 | [wave_spawn_tsv.lua](../../KingdomRushDove/all/systems/wave_spawn_tsv.lua) | 指令调度、信号/事件/手动波次；代表 TSV 关卡 |
| 路径、地形 | [path_db.lua](../../KingdomRushDove/all/path_db.lua)、[grid_db.lua](../../KingdomRushDove/all/grid_db.lua)、[grid_a_star.lua](../../KingdomRushDove/all/grid_a_star.lua) | PathService、TerrainGrid；连接、反向、集结和地形限制 |
| 索敌与空间索引 | [seek.lua](../../KingdomRushDove/all/seek.lua)、[spatial_index.lua](../../KingdomRushDove/all/spatial_index.lua) | TargetQuery、空间哈希；椭圆范围和 flags/bans |
| 通用脚本工具 | [utils.lua](../../KingdomRushDove/all/utils.lua)、[script_utils.lua](../../KingdomRushDove/all/script_utils.lua)、[scripts.lua](../../KingdomRushDove/all/scripts.lua) | 伤害、移动、攻击与状态能力库；是大部分行为的依赖 |
| 动画与渲染 | [animation_db.lua](../../KingdomRushDove/all/animation_db.lua)、[render.lua](../../KingdomRushDove/all/systems/render.lua)、[render_utils.lua](../../KingdomRushDove/all/render_utils.lua) | Sprite/EXO 播放器、RenderFrame；逻辑尺寸、排序及挂点 |
| EXO 与图集 | [exoskeleton.lua](../../KingdomRushDove/all/exoskeleton.lua)、[image_db.lua](../../KingdomRushDove/lib/klove/image_db.lua)、[atlas_binary.lua](../../KingdomRushDove/lib/klove/atlas_binary.lua) | 元数据契约；依赖现有转换器；用有翻转/斜切的动作验收 |
| 伤害结算 | [health.lua](../../KingdomRushDove/all/systems/health.lua)、[constants.lua](../../KingdomRushDove/all/constants.lua) | DamageResolver、伤害类型位标志；反伤、免疫、击杀唯一性 |
| 状态、光环、补间 | [mod_lifecycle.lua](../../KingdomRushDove/all/systems/mod_lifecycle.lua)、[tween.lua](../../KingdomRushDove/all/systems/tween.lua)、[game_scripts.lua](../../KingdomRushDove/kr1/game_scripts.lua) | 状态生命周期及通用能力；检查暂停、刷新、源单位消失 |
| 游戏模板、敌人 | [game_templates.lua](../../KingdomRushDove/kr1/game_templates.lua)、[enemies.lua](../../KingdomRushDove/kr1/enemies.lua) | 单位定义与行为绑定；基础敌人到特性敌人的分批迁移 |
| 四类塔定义 | [archer_towers.lua](../../KingdomRushDove/kr1/archer_towers.lua)、[mage_towers.lua](../../KingdomRushDove/kr1/mage_towers.lua)、[engineer_towers.lua](../../KingdomRushDove/kr1/engineer_towers.lua)、[barrack_towers.lua](../../KingdomRushDove/kr1/barrack_towers.lua) | 塔定义、分支、技能、士兵；依赖通用战斗与资产 |
| 塔行为与操作 | [tower_scripts.lua](../../KingdomRushDove/kr1/tower_scripts.lua)、[tower_utils.lua](../../KingdomRushDove/all/tower_utils.lua)、[rally_utils.lua](../../KingdomRushDove/all/rally_utils.lua) | 塔状态机、建造/升级/卖塔/集结命令；原子扣款与取消 |
| 英雄 | [heroes.lua](../../KingdomRushDove/kr1/heroes.lua)、[hero_scripts.lua](../../KingdomRushDove/kr1/hero_scripts.lua) | 升级、技能、移动、复活及多英雄选择；不能写死单英雄 |
| Boss | [boss.lua](../../KingdomRushDove/kr1/boss.lua)、[boss_scripts.lua](../../KingdomRushDove/kr1/boss_scripts.lua) | 阶段控制器、召唤、环境交互；结合专属关卡脚本 |
| 难度与科技 | [difficulty.lua](../../KingdomRushDove/all/difficulty.lua)、[upgrades.lua](../../KingdomRushDove/kr1/upgrades.lua)、[game_settings.lua](../../KingdomRushDove/kr1/game_settings.lua) | 本局数值补丁管线；验证多次重开不重复叠乘 |
| 战斗 HUD | [game_gui.lua](../../KingdomRushDove/all-desktop/game_gui.lua)、[game_gui_data.lua](../../KingdomRushDove/kr1-desktop/data/game_gui_data.lua) | Control 场景与输入状态；依赖命令和只读状态 |
| 地图与英雄选择 | [screen_map.lua](../../KingdomRushDove/all-desktop/screen_map.lua)、[map_data.lua](../../KingdomRushDove/kr1-desktop/data/map_data.lua) | 多代地图入口、解锁、配装；依赖持久化和动态文案 |
| 第三法术 | [spell_system.lua](../../KingdomRushDove/kr1/spell_system.lua)、[spells](../../KingdomRushDove/kr1/spells/) | 法术注册、资源依赖、施放、等级和附加生命倍率 |
| 无尽与塔技能 | [endless_utils.lua](../../KingdomRushDove/kr1/endless_utils.lua)、[tech_registry.lua](../../KingdomRushDove/kr1/endless/tech_registry.lua)、[tower_skill_protocol.lua](../../KingdomRushDove/kr1/tower_skill_protocol.lua) | 模板/运行时科技分流、波次成长、技能和保存恢复 |
| 回溯 | [time_rewind.lua](../../KingdomRushDove/dove_modules/time_rewind.lua)、[time_rewind_kinds.lua](../../KingdomRushDove/dove_modules/time_rewind_kinds.lua) | 玩家操作日志、重建重演、时间线、无效命令和副作用抑制 |
| 存档、成就、配置 | [storage.lua](../../KingdomRushDove/all/storage.lua)、[achievements_handlers.lua](../../KingdomRushDove/kr1/achievements_handlers.lua)、[configer.lua](../../KingdomRushDove/dove_modules/configer.lua) | SaveService、事件统计、配置校验；浏览器备份恢复 |
| 音频、国际化 | [sound_db.lua](../../KingdomRushDove/all/sound_db.lua)、[i18n.lua](../../KingdomRushDove/all/i18n.lua) | AudioService、TextService；声音约束与实时参数 |
| 自动参考场 | [autoplay.lua](../../KingdomRushDove/dove_modules/debug/autoplay.lua) | 参考原版测试入口和日志字段；执行时隔离存档及版本 |

阅读建议：第一遍读 `constants → entity_db/components → simulation → game → systems/level`；第二遍从第一关沿 `wave_db → enemy → tower → damage → render` 追踪一个完整攻击；第三遍按具体内容追踪专属脚本。数万行的塔、英雄脚本按行为族拆读，不做一次性逐行翻译。

<a id="s04"></a>
## 4. Godot 总体架构与接口

### 4.1 工程组织与职责

【设计】复用现有 `assets/kingdom_rush` 和 `DoveAssetCatalog`，新玩法代码按职责扩展。以下是建议目录，不表示已经创建：

~~~text
scenes/app/         启动、地图、载入、结算
scenes/game/        战场表现和 HUD
scripts/core/      时钟、命令、事件、实体与模拟世界
scripts/systems/   波次、行为、伤害、状态、塔、关卡等阶段
scripts/content/   数据加载、行为注册、数值补丁、关卡控制器
scripts/render/    普通动画、EXO、挂点、渲染排序
scripts/services/  资源包、文本、音频、存档
data/gameplay/     生成后的关卡、模板、数值和依赖数据
tools/gameplay/    离线导出与验证工具；不进入 Web 包
tests/gameplay/    纯逻辑测试、集成场景与参考数据
~~~

~~~mermaid
flowchart LR
    A[冻结源码 / 原始快照] --> B[离线导出与依赖验证]
    B --> C[玩法数据 / 资源包清单]
    C --> D[ContentRegistry / PackLoader]
    E[HUD / 输入] --> F[PlayerCommand 队列]
    F --> G[SimulationWorld]
    D --> G
    G --> H[状态快照 / 领域事件 / RenderFrame]
    H --> I[WorldView / 动画 / 音频 / HUD]
    H --> J[存档与成就]
~~~

推荐场景树：

~~~text
AppRoot
├── ScreenRouter
│   └── 当前屏幕（Map / Loading / Battle / Result）
├── Services（生命周期由 AppRoot 管理）
└── BattleScreen（进入战斗时存在）
    ├── BattleController → SimulationWorld（RefCounted，纯逻辑）
    ├── WorldView（Node2D，消费 RenderFrame）
    ├── Camera2D（只管显示与输入投影）
    └── HUD（CanvasLayer / Control）
~~~

共享服务限定为 ContentRegistry、AssetService/PackLoader、AudioService、TextService、SaveService。模拟实例属于一局，不放在永久单例里。UI 只发命令和读取状态；资源目录不直接改生命、金币或解锁。

【设计】优先用 GDScript 的 RefCounted/紧凑记录承载逻辑实体，避免每个组件、计时器、EXO 部件都建节点。少量单位可用 Node2D 表现；大量部件使用自定义绘制或集中绘制命令。弹丸、飘字及短特效采用池化，但先测量再扩展池。

### 4.2 最小数据与运行接口

以下字段为新接口草案，`schema_version=1` 指玩法数据版本，与现有资产 schema 分开管理。示例不是全部字段；实际迁移需覆盖使用到的源字段，并输出未映射字段报告。

| 类型 | 最小内容 | 约束 |
| --- | --- | --- |
| LevelDefinition | `id`、来源版本、可用模式、布局、路径/网格引用、模式覆盖、资源依赖、关卡行为 ID | 不从关卡文件名推断解锁和玩法模式 |
| EntityTemplate | 原模板 ID、组件值、behavior bindings、资源引用 | 基础模板不可变；实例含可变运行态 |
| WaveProgram / WaveCommand | 格式来源、初始资源、通道/波次组、命令序列和等待条件 | 保留并发、手动波次与信号语义 |
| BehaviorRegistry | `behavior_id → factory`、所需能力、状态版本 | 未实现的可达行为使内容验收失败 |
| PlayerCommand | 逻辑 tick、同 tick 序号、命令类型、稳定对象标识、参数 | 入队前转成世界坐标；执行时再次校验合法性 |
| PackManifest | 发布版本、包 ID、依赖、URL、字节数、SHA-256、资源路径清单 | 包来自同一次兼容导出，禁止任意覆盖已加载脚本 |
| SaveEnvelope | schema、内容版本、存档槽、玩家进度与设置 | 不保存场景节点、函数和浏览器文件句柄 |

~~~json
{
  "schema_version": 1,
  "id": "level01",
  "source": {"version": "2.1.0.2", "commit": "e29ece82939fd73fb69bfc4b469d484a72e4dfd2"},
  "mode_ids": [1, 2, 3],
  "layout_ref": "levels/level01.layout.json",
  "paths_ref": "levels/level01.paths.json",
  "grid_ref": "levels/level01.grid.json",
  "level_behavior_id": "level01",
  "wave_programs": {"1": "waves/level01.campaign.json"}
}
~~~

该示例只展示战役波次引用；其他已支持模式必须补齐对应程序后才可在界面开放。原 ID、模式数字、塔位 ID、技能 ID 均保留；JSON 对象键始终为字符串。数组访问在统一适配层转成从 0 开始，禁止业务代码散布 `-1`。

~~~gdscript
# 拟实现接口；仅定义调用关系。
# ContentRegistry.get_template(id) -> 不可变模板
# EntityFactory.create(template_id, context) -> 本局实体
# BehaviorRegistry.create(behavior_id) -> 行为实例
# SimulationWorld.enqueue(command) -> 校验后进入 tick 队列
# SimulationWorld.step(dt) -> 执行一次逻辑步进
# SimulationWorld.drain_events() -> 本步领域事件
# WorldView.present(render_frames, interpolation) -> 更新表现
~~~

【设计】公共事件用明确名字和结构化参数，例如 `enemy_spawned`、`damage_applied`、`tower_built`、`wave_started`、`battle_finished`。区分模拟内事件、UI 提示和持久化事件，避免重演时把同一击杀重复记入成就。

<a id="s05"></a>
## 5. 数据提取、转换和内容管理

### 5.1 两条导出路径

【事实】现有 `StaticLua` 只覆盖受限数据子集，测试明确拒绝 `require`、任意函数和系统调用。关卡含 `v(...)`，模板含继承、算术、函数引用、条件分支和运行时补丁，不能用正则或现有解析器直接导出完整游戏。

【设计】工具分为两个适配器，共同输出新玩法 schema：

1. **纯数据适配器**：为已知数据提供显式的向量构造、常量及帧转秒支持，读取布局、路径、网格和简单波次；遇到超出子集的语法立即报源文件与位置，不静默丢字段。
2. **隔离 Lua 导出器**：基于 BASE 的独立副本，在离线 LuaJIT/LÖVE 兼容环境注册基础组件和模板；展开继承、克隆和可求值数值；将已登记函数引用转成行为 ID。只读导出输入，所有临时文件和输出位于工具工作目录，禁止运行原 `main.lua`、更新器或用户插件。原配置读取写入由隔离测试配置接管。

【验证任务 M0】先导出 `enemy_goblin`、四类基础塔、第一关布局和一个专属模板组，证明 `require` 搜索路径、组件克隆、预编译依赖和函数映射可控。不要未经验证就承诺“所有模板一键导出”。导出器可以跳过只用于 Lua 性能优化的编译阶段，但必须对照验证最终组件默认值和脚本绑定；不能把跳过后的差异藏在 JSON 中。

函数映射采用显式注册表，例如原 `scripts.enemy_mixed.update` 对应 `enemy_mixed.update`。未登记函数、循环引用、非有限数字、未知 userdata、不可解释 FFI 数据均报错。运行态缓存和协程不作为模板导出。导出报告逐项列出保留、转换、忽略及需手工实现的字段与原因。

### 5.2 数值管线

【设计】保存未应用本局难度和科技的基础值，运行时按第 2 章顺序实例化补丁；另导出若干已求值参考快照供对照测试。禁止在基础 JSON 先乘难度，Godot 入局时再乘一次。所有等级数组、条件分支及取整位置要有来源。

【事实】BASE 的弓箭、法师、工程、兵营四类塔列表分别含 25、29、25、30 个模板 ID，合计 109 项（包含基础级别及特殊条目，不能直接称为 109 座独立高级塔）。难度除了生命还影响速度、掉金、造塔价格、护甲与敌人技能间隔。科技、法术、配置和无尽会继续改变模板或实例。

### 5.3 波次统一模型

【事实】`wave_db:load` 在每个搜索来源中先试 TSV 再试 Lua；原版还支持编辑器目录覆盖。Web 正式内容使用冻结的官方数据来源，不加载原编辑器覆盖目录，但保留其已选中的文件格式语义。Lua 的 `*_extra.lua` 合并也要记录。

【设计】两种格式转换成统一程序，不把整个游戏简化为一个 `spawn_at_seconds[]`：

| 命令能力 | 必须保留的语义 |
| --- | --- |
| wave / flags | 波次组、路线旗帜、准备/发送、教程通知及提前开波 |
| spawn | 数量、敌人/辅助敌人、路径/子路径、交替规则、间隔及出生附加数据 |
| wait | 时间等待、等待玩家开波、强制开波中断及难度调整 |
| event / signal | 关卡实体事件与信号名称/参数；两者不能合并为仅 UI 通知 |
| wait_signal | 信号订阅、超时、强制中断、解除订阅和清怪等待 |
| manual_wave / repeat / call | 独立命名通道、重复和停止；与主波次并行 |
| 初始属性与默认值 | lives、gold/cash、gems、enemy_prefix、默认增量与间隔 |

时间字段按解析器实际处理转成统一秒数并保留来源值/单位。Lua 常见帧数要除以 30；TSV 已解析命令中的等待值不能再次盲目除以 30。负等待和 `wait_signal` 的特殊约束按代码单独处理。

~~~json
{
  "kind": "spawn",
  "channel": "main",
  "wave_group": 1,
  "enemy_id": "enemy_goblin",
  "path_id": 1,
  "count": 3,
  "interval_seconds": 1.7,
  "first_spawn_after_interval": true,
  "source": {"format": "lua", "interval_frames": 51}
}
~~~

该命令是第一波出生规则的字段示例，不是完整波次程序。【事实】原 Lua spawner 在每个敌人入队前先等待 interval，首个敌人并非必然在开波瞬间出生。普通帧号不能替代逻辑 tick。

### 5.4 关卡与内容依赖闭合

【设计】生成内容清单，以“地图可达入口 × 支持模式 × 关卡行为”作为交付单位。由地图入口、游戏设置和布局共同推导；特殊测试场、未开放条目和残留文件单独标记。迁移看板至少记录：

~~~text
内容 ID / 来源提交 / 模式 / 专属行为 / 敌人 / 塔和英雄能力
所需资源包 / 未实现能力 / 验收场景 / 状态 / 参考日志
~~~

依赖扫描沿模板继承、子弹、召唤、死亡生成、modifier、aura、动画、EXO 部件、声音、法术和关卡控制器递归展开。字符串动态拼接无法静态证明时，由行为声明资源依赖，并用运行时缺失采样补充。已选英雄和法术也会引入关卡布局清单之外的资源。

【验收】允许记录未开放内容的遗留告警；任何本批可达内容缺关键模板、脚本、帧或音频必须阻止该批发布。不能靠静音、空白图或自动删除敌人掩盖缺失。

<a id="s06"></a>
## 6. 素材、普通动画和 EXO3

### 6.1 复用现有访问层

【事实】`DoveAssetCatalog` 已提供 `list_groups`、`load_group`、`get_frame`、`get_texture`、`get_animation`、`get_exoskeleton`、`get_sound`、`get_static`、`clear_cache`。沿用现有 `schema_version=1`；Web 派生图集使用独立输出目录和清单，不能悄悄改写原始快照。

【设计】扩展 AssetService 负责资源包就绪状态、缓存统计、依赖与生命周期；底层帧查询仍使用 `(group, frame_name)`。原版全局查找出来的帧名须在离线阶段按加载组顺序解析为具体组；不能对同名帧随便取第一项。

### 6.2 坐标、裁切与锚点

【事实】原世界 Y 向上，显示时使用 `REF_H - world_y`，`REF_W=1024`、`REF_H=768`、范围椭圆比例 `ASPECT=0.7`。宽屏显示会扩展可见逻辑宽度，背景 PNG 的 1920×1080 像素不是游戏逻辑坐标。

【设计】设可见逻辑宽度为 `visible_w`，屏幕缩放为 `scale`，相机/视口偏移单独计算：

~~~text
view_x = world_x + (visible_w - 1024) / 2
view_y = 768 - world_y
screen_position = camera_view_transform(view_position) × scale
world_position = 上述变换的逆变换（只在输入边界执行）
~~~

16:9、4:3、窗口缩放和相机缩放都须验证；4:3 下如需平移查看地图边缘，应沿原相机边界实现。地图选关界面使用自己的布局数据，不能强套战场坐标。

【事实】图集 `region` 为实际 PNG 像素，`logical_size`、`original_size`、`trim` 保留原图集逻辑单位。实际图比声明图大时，UV 已由转换器按宽高比换算。再次统一放大逻辑尺寸会导致错位。

普通帧绘制参考原 `render_utils`：

~~~text
origin_x = anchor.x × original_size.x - trim.x
origin_y = (1 - anchor.y) × original_size.y - trim.y
局部绘制矩形起点 = -origin × ref_scale
局部绘制矩形大小 = logical_size × ref_scale
再应用实体缩放、翻转、旋转与位移；原实体旋转在屏幕边界取反。
~~~

这里读取的是帧逻辑矩形；AtlasTexture 的物理 region 只决定采样。含斜切时使用完整仿射变换。角色的脚点、影子、生命条和点击区分别还原，不能把纹理包围盒直接当单位位置。

### 6.3 普通动画

【设计】建立 AnimationPlayerAdapter，接受动画 ID、开始模拟时间、循环/一次播放、速度、偏移和反向参数。素材动画通常 30 FPS；帧序列中重复与逆序帧按序播放，不重新去重或按数字排序。

动画中的攻击/施法命中时点由战斗行为调度，不由“屏幕恰好绘制到某帧”触发。跳帧、不可见、后台暂停和回溯快进不应漏伤害。完成事件也要按模拟时间保证只触发一次。

### 6.4 EXO3 组合播放器

【事实】现有 JSON 的 `animations` 引用共享组合帧，帧引用已转成 0 基；部件/挂点索引仍是 1 基。记录布局为：

~~~text
type, index_1_based, alpha, x, y, scale_x, scale_y, rotation, skew_x, skew_y
type=1：图像部件；type=8：挂点
~~~

【设计】播放器必须支持动作切换、共享帧、部件顺序、透明度、双轴缩放/翻转、旋转、斜切、部件 offset、隐藏部件及挂点查询。EXO 局部坐标不能统一再套一次世界 Y 翻转；部件与挂点采用源变换链，分别与参考渲染核对。

输出 `attachment_transform(name)` 供子弹出生点、武器、技能和附着特效使用。挂点的世界坐标需在逻辑攻击前可取得；不能仅在 `WorldView.draw` 更新缓存，否则无渲染的测试、快进和离屏单位会使用旧坐标。必要时模拟层调用无绘制的姿态采样器。

【验证任务 M0】先用现有 `archer4Def` 验证 idle/攻击/翻转/挂点，再选带非零斜切或多层变换的动作。不得把全部 EXO 动作预渲染为帧 PNG 作为主方案，避免包体、内存和挂点信息损失。

### 6.5 遮挡与 Web 派生图集

【事实】原稳定排序为 `z` 升序 → `sort_y` 降序 → `_draw_order` 升序，末者含部件顺序与实体 ID。原始 Z 值包括 3000、3300、3400、4000 等。

【设计】维护相同的逻辑排序键，再映射到 Godot 绘制命令序列。Godot 的 `z_index` 有范围限制，不能把所有原始大 Z 值及每帧排序名次直接塞进去。原生 YSort 也不能单独表达全部遮挡和独立子部件排序。初版使用可复现的稳定排序；替换原 FFI 排序及空间结构时保持结果语义。

Web 派生图集优先以最大 4096 为切分目标，对超大图按帧重新打包并加边缘 padding；保持组/帧逻辑 ID、裁切、锚点与 ref_scale。不要先整体缩小所有图片。对于单帧本身超过上限、舍入越界或特殊组合，列入专项验证；4096 是项目的派生资源目标，不是所有 WebGL 2 设备的统一硬上限。压缩格式和实际纹理上限以浏览器能力验证为准。

<a id="s07"></a>
## 7. 时间、命令与实体生命周期

### 7.1 三种时间

【设计】采用固定 30 Hz 模拟，一步 `SIM_DT=1/30`；渲染目标 60 FPS；界面动效按未乘倍速的现实增量更新。所有战斗等待、冷却、DOT、buff 时长、波次和行为状态保存模拟时间/tick，禁止用节点 Timer 或 `create_timer` 的现实等待替代。

【事实】原 `game:update` 使用累加器和 `store.tick_length`；adaptive_fps 根据渲染负载调整步长，最高参考值 144、最低 30 FPS。`fts(x)=x/30` 是素材/原规则时间换算，不证明原模拟一直固定 30 Hz。

【验证任务】固定步长是新实现选择。对照原版固定测试配置验证临界比较、出生时点、出手与冷却；时间事件允许在一个模拟 tick 内的采样误差，但扣款、数量、伤害公式及规则不能以该容差放宽。

累加器每渲染帧执行有上限的逻辑步数，例如首版上限 8；未消费的正常增量保留，避免默默丢掉波次时间。标签页隐藏或异常长间隔时自动暂停并清除积压，返回后由玩家继续；不补算后台数分钟。倍速通过多执行逻辑步实现，不能直接增大单步 dt。UI 提示、按钮动画和鼠标响应保持正常速度。

### 7.2 命令总线

~~~json
{
  "tick": 120,
  "sequence": 3,
  "kind": "tower_upgrade",
  "target": {"holder_id": "1"},
  "args": {"upgrade_to": "tower_archer_2"}
}
~~~

【设计】第一天就通过命令总线实现建塔、升级、卖塔、集结、英雄移动、施法、提前开波和塔模式切换。点击后目标可能已死亡或金币不足，因此在逻辑执行时检查目标、解锁、价格、位置和冷却。稳定标识优先使用塔位 ID 或角色实例映射，而不是跨重建复用内存引用。

原始输入只进入一次命令。重演执行不得再次录入；重建期间玩家输入被屏蔽。随机建塔的日志记录已经选出的目标模板，不能在重演时再次随机选择建造目标。调试回放可另行记录随机流，玩家回溯语义见第 12 章。

### 7.3 实体与队列

【事实】`simulation:do_tick` 先增加 tick_ts，再处理本步开始时的 pending_inserts、pending_removals，然后依次更新系统。插入采用本批长度快照和正向处理；处理期间新加入的实体不会无限递归入场。插入方向以本版本的正向处理代码为准。

【事实】2026-10-25 同步的 BASE 将多处局部辅助函数归并到 `U.fts`、`U.tpos`、`U.ready_to_attack`、`U.enemy_ready_to_magic_attack` 和 `U.queue_damage`，实体插入/移除直接调用 `simulation:queue_insert_entity` / `queue_remove_entity`。部分塔技能改用 `on_power_upgrade` 回调；关卡恢复技能时只对 `level > 0` 的技能调用升级入口。迁移时按当前调用链核对升级、恢复和入场顺序。

【设计】在每个 tick 明确批次边界；成功入场后更新对应分类、索敌及渲染索引，取消插入不留下半个实体。死亡状态、移除、死亡生成、奖励和表现销毁分开处理。生成于本批处理期间的下一批对象按原可见性推进。

伤害在统一阶段结算；反伤等新伤害使用双队列，避免同一结算阶段递归到栈溢出或双重击杀。暂停时逻辑 tick 不增长；显示层可继续播放菜单动效。离开关卡取消该局全部任务、信号订阅和资源租约，重新进入时实例状态为空。

<a id="s08"></a>
## 8. 路径、地形、集结与索敌

### 8.1 敌人路径

【事实】敌人以 `pi/spi/ni` 表示主路径、子路径和节点，带移动方向及路径连接；路径采样距离常量为 7，原路径不是供任意重建的视觉曲线。存在反向路径、不可用区段、可见起止点、目标点与分支连接。

【设计】首版直接使用原节点序列推进并保留路径标识，用路径剩余距离/节点和连接关系计算到终点的顺序。不能仅按 X 坐标判定“最前方敌人”。保留离屏出生及离屏路径节点，不要因超出 1024×768 就裁掉。

到达 defend point 或离场规则只结算一次生命损失，并从可攻击/存活统计中移除。倒退、传送、强制位移、隧道与关卡切路通过 PathService 接口处理，不能由表现节点直接改路径游标。

### 8.2 地形与集结

【事实】原网格 cell_size 为 16，有 ox/oy、地形类型与属性位标志；塔位来自布局实体的 holder，而不是在所有网格上任意摆塔。网格还用于士兵/英雄寻路、有效落点和地形限制。

【设计】保留 TerrainGrid 的世界坐标转换和位掩码语义，用原网格 A* 能力迁移士兵/英雄路径，不一开始替换为 Godot 自动烘焙导航。集结点校验涉及塔的 rally_range、原椭圆距离、NF_RALLY、地形与是否允许任意集结。

士兵需要走到分配位置、占用阻挡目标、进入近战、脱战回复、死亡补员；集结变更须释放旧阻挡并重新寻路。阻挡关系双向维护，支持飞行/不可阻挡单位、单位容量及关卡特例。

### 8.3 索敌

【设计】建立空间哈希，初值沿用原常量 50 逻辑单位；先做粗筛，再按原 vis.flags、vis.bans、存活、隐藏、路径有效性、最小/最大范围及目标种类过滤。一般地面范围使用椭圆判定，是否有距离预测与飞行例外由具体攻击决定，不全局硬套。

对椭圆中心 `c` 和目标 `p`，普通范围可用 `dx² + (dy/0.7)² <= r²`。塔 range_offset、单位命中偏移、弹道预测及专门的圆形攻击，须走各自接口。相同候选的优先级用稳定规则，避免 Dictionary 遍历顺序改变每次结果。

【验收】第一关 1 条主路的子路径全部可用；至少增加连接/反向路线测试，以及飞行过滤、超界出生、范围边缘、单位死亡后重新索敌、集结点无效地形测试。空间索引优化不能改变合法目标集合。

<a id="s09"></a>
## 9. 战斗与数值规则

### 9.1 攻击是一个有时序的过程

【设计】通用攻击状态依次为：冷却就绪 → 选择合法目标 → 起手/朝向 → 等待命中或发射时点 → 生成弹丸或直接伤害 → 后摇 → 下一次冷却。保留原攻击是从起手、命中还是结束计时的差别，以及目标丢失后的取消/继续规则。

弹道按能力分成弧线箭、炮弹、追踪弹、直线弹、射线/即时命中、链式命中和地面持续区域。它们共享来源、目标、命中 offset、伤害/状态 payload 与移除机制；不强求都使用一个节点类。爆炸范围、最大目标数、衰减、空地过滤和死亡目标上的命中策略按模板定义。

### 9.2 伤害消息与阶段

【事实】原伤害消息包括 `source_id`、`target_id`、`damage_type`、`value`、减甲字段、hooks、pop、经验归属及结算结果。`health` 先检查死亡、免疫、ignore_damage 和 on_damage，再处理削甲、吞噬、预测伤害、生命扣除、命中效果与击杀跟踪。不是所有敌人的死亡清理由同一个通用分支完成。

【设计】DamageResolver 将“过滤 → 计算 → 扣血 → 结算事件”集中，单位死亡行为再处理金币、召唤、尸体和移除。每个致死结果只能生成一次奖励。跨实体 hooks 改写数值和护盾规则显式注册，避免把 Lua 函数字符串直接执行。

伤害类型为位标志，可能组合。原 Lua bit 使用 32 位整数语义，最高位有 `2147483648`，`DAMAGE_ALL=4294967295`；GDScript int 为 64 位。移植时统一按 `0xffffffff` 规范化，并使用位与结果非零判断，测试最高位和组合优先级。

### 9.3 必须还原的公式

【事实】以下来自 BASE 的 `U.calc_protection` 与 `U.predict_damage`。设 `a=armor-reduce_armor`，`m=magic_armor-reduce_magic_armor`，最终 protection 在变换后 clamp 到 [0,1]。

| 类型 | protection | 额外处理 |
| --- | --- | --- |
| poison | poison_armor | 在该分支序列中先于 true 判定 |
| true / disintegrate | 0 | 仍需经过对应免疫及行为规则 |
| physical / against_armor | a | against 类型另加护甲平方项 |
| magical / against_magic_armor | m | magical 类型乘专门的受魔法伤害倍率 |
| explosion / rude | a × (0.2a + 0.4) | 不能直接等同 physical |
| magical_explosion | m × (0.2m + 0.4) | 同时应用魔法伤害倍率 |
| electrical | 0.5a | 若存在 electrical 受伤倍率则应用 |
| shot | 0.7a | 不是纯物理减伤 |
| stab | a × (2-a) | 原始伤害值先乘 2 |
| mixed | (a+m)/2 | 独立于纯物理或魔法 |
| none（值恰为 0） | 1 | 不与普通伤害混淆 |

通常伤害为 `adjusted_value × health.damage_factor × (1-protection)`；against 两类另加 `adjusted_value × protection² × 2 × health.damage_factor`。hooks 在读取最终 damage.value 前执行。`NO_KILL` 对致死伤害限制为当前 hp−1。

`INSTAKILL` 预测值使用 `hp_max × (1-instakill_resistance)`，只在 damage_factor>1 时再乘该倍率；不能统一写成当前生命清零。`EAT` 在 health 中另有专门分支，实际施加量取非负当前生命，不能仅照预测函数实现。削物甲、削魔甲不属于普通扣血。死亡生成、闪避、护盾、吸血及免疫效果需同时审查专属行为，不能只靠此表完成全部战斗。

【验收样例】在所有额外倍率=1、无 hooks、原始值=100、a=0.5、m=0.2 时，物理=50，魔法=80，爆炸=75，电击=75，shot=65，stab=50，mixed=65，against_armor=100。另测免疫、护盾、负减甲/越界保护、反伤双队列、非致死和两次同 tick 致死消息。

### 9.4 modifier、aura、治疗与难度

【设计】modifier 定义生效、刷新/叠加、周期结算、结束恢复和源对象消失规则；慢速、冻结、眩晕、毒、燃烧、流血、增益、减甲和变形按行为族复用。aura 负责周期性查找目标、入圈/离圈及派生 modifier。不同效果不能全部简化为“修改一个属性，结束恢复默认值”，否则多个 buff 重叠时会互相覆盖。

治疗、脱战再生、吸血、英雄经验和击杀归属使用独立领域事件或明确接口。模板倍率与实例倍率分开：塔自身、士兵/子单位和技能可能使用不同伤害与冷却因子。

【事实】四档难度编号为 1/2/3/4；BASE 敌人 hp 倍率为 1.3/1.65/1.65/2，移速倍率为 1.20/1.20/1.25/1.25；它们不是经典原版的默认平衡。难度还包含数组取值、飞行单位生命特例、不可能难度秒杀抗性等规则。第三法术启用后还会增加敌人生命。不得用网上经典 KR 数值覆盖 Dove 定义。

【验收】基础模板在切换难度、退出重开、切换科技列表及选择法术后重新构建；三次连续重开和首次入局的相同配置数值一致。

<a id="s10"></a>
## 10. 塔、士兵、英雄与 Boss

### 10.1 基础塔与升级操作

【设计】先实现四个基础模板：`tower_archer_1`、`tower_barrack_1`、`tower_mage_1`、`tower_engineer_1`，再扩展 2/3 级、分支塔与技能。建造过程保留 holder、花费、占位、建造完成时点及菜单状态。四类射程、目标过滤和弹道分别验证。

升级是逻辑事务：检查目标分支/限制 → 校验金币 → 扣款 → 原塔移除/新塔插入 → 迁移 holder、集结点和允许保留的升级数据 → 更新 UI。未成功升级不能只扣钱或只改纹理。卖塔按原售价与累计投入规则计算并清理士兵、光环和专属对象，恢复正确地形的 holder。

技能购买、兵营购买士兵、塔模式切换、手动指定目标与随机塔，均使用命令总线。技能等级上限和关卡锁定来自数据，不在菜单硬编码。

### 10.2 行为能力矩阵

| 内容族 | 基础能力 | 特殊迁移点 | 推荐验收样本 |
| --- | --- | --- | --- |
| 弓箭塔 | 选敌、朝向、箭弹、攻击动画 | 多目标、标记、毒、暴击、狙击与召唤 | 基础塔 + 至少两个机制不同的高级塔 |
| 法师塔 | 魔法目标过滤、弹丸/射线 | 传送、变形、光环、召唤、链与特殊抗性 | 基础塔 + 传送/召唤各一例 |
| 炮塔 | 地面过滤、预测落点、范围结算 | 火焰、持续区域、机甲、地震、电链 | 基础炮 + 地震/电链各一例 |
| 兵营 | 士兵生成、路径、集结、阻挡、补员 | 单位技能、多个兵种、远程补击与召唤 | 集结变更、死后补员、塔升级与卖塔 |
| 敌人 | 路径、阻挡、近战、死亡掉落 | 飞行、远程、治疗、召唤、护盾、复活、隧道 | 每个实际使用的特性有独立场景 |
| 英雄 | 移动、经验、等级、技能、死亡复活 | 飞行/变形、召唤、主动技能、多英雄控制 | `hero_gerald` 起步，再按技能能力扩展 |
| Boss | 阶段状态、血条、免疫、技能循环 | 路线/场景联动、召唤、离场与胜利条件 | 第一批目标 Boss 及至少一个多阶段 Boss |

【设计】每个行为实现保留来源函数 ID、通用能力依赖和验证场景。一个高级塔迁移前，先在能力矩阵中确认弹道、状态、EXO 和挂点是否已完成；不能把外观相似作为共用逻辑的依据。

英雄列表及选中配置按数组处理，不把源版可能的多英雄选择压缩成单个 `selected_hero_id`。英雄本局经验、持久进度、技能等级、复活时间和生成位置分别建模。第一关不为演示方便强制免费插入一个本来未选择的英雄。

Boss 的胜利条件由关卡控制器判断，不能只看 Boss hp≤0。需要等待转阶段、召唤单位、演出或关卡脚本完成的情况纳入专属状态机。

<a id="s11"></a>
## 11. 完整玩家流程与界面

### 11.1 交互流程

~~~mermaid
stateDiagram-v2
    [*] --> Boot
    Boot --> Map: 服务与存档就绪
    Map --> Loading: 选关 / 模式 / 难度
    Loading --> Preparing: 数据与资源通过检查
    Loading --> Map: 取消或加载失败
    Preparing --> Playing: 首次开波
    Playing --> Paused: 暂停 / 标签页隐藏
    Paused --> Playing: 继续
    Playing --> Result: 胜利或失败条件满足
    Result --> Loading: 重试
    Result --> Map: 保存结果后返回
~~~

【设计】地图按源数据实现代际切换、关卡星级/挑战标记和解锁；英雄选择、塔选择/解锁、科技分配、法术选择、图鉴与成就逐步接入。外部菜单视觉可以先搭清晰骨架，但保留源布局、文案、图标和交互信息的还原路线。

### 11.2 HUD 和输入状态

战斗 HUD 至少包含生命、金币、波数、下一波、暂停、倍速、技能冷却、单位信息及建造/升级/卖塔/集结操作。建造菜单、圆形范围、技能落点和 tooltip 由只读状态生成，逻辑层决定按钮是否可用。

【设计】输入状态明确分为普通选择、塔菜单、集结点选择、法术落点、英雄移动和模态窗口。UI 消费点击后不再传给战场；拖动相机与单击通过阈值区分。Esc/右键取消按源行为实现；键位初值从 `patches/keyset_default.lua` 映射，并提供浏览器可用的重绑定。文案输入框获得焦点时不执行游戏快捷键。

页面缩放、DPR、canvas CSS 大小和游戏视口的转换只在统一投影层处理，不能在每个按钮里各乘一遍比例。tooltip、塔菜单和暂停窗在 4:3、16:9、窄窗口及边缘塔位均不得超出可见区域。

### 11.3 第一关的可复核基线

【事实】第一关 `level01` 战役 Lua 数据：

| 波次组 | 哥布林 `enemy_goblin` | 兽人 `enemy_fat_orc` | 提示/注意 |
| --- | ---: | ---: | --- |
| 1 | 3 | 0 | 首次开波由玩家触发 |
| 2 | 6 | 0 | 两个连续出生段 |
| 3 | 9 | 0 | `POWER_REINFORCEMENT` 通知 |
| 4 | 4 | 1 | 开始混合兵种 |
| 5 | 0 | 3 | `TIP_ARMOR` 次级提示 |
| 6 | 10 | 4 | `TIP_RALLY` 次级提示 |
| 7 | 16 | 0 | `POWER_FIREBALL` 通知 |
| 合计 | **48** | **8** | 共 56 个配置出生单位 |

初始 lives=20、cash=270；8 个 holder 的 ID 为 `1` 到 `8`，位置与 default_rally_pos 直接来自布局。背景还有独立舞台前景、磨坊、树木和羊，不能只显示一张背景便视为地图还原。

战役覆盖包含初始锁定的两个玩家能力，以及锁定的四类二级塔；第三、七波通知与教程解锁衔接要追踪 HUD 逻辑，不能从第一帧无条件开放。关卡允许英雄但采用手动插入流程，是否存在英雄由选择配置决定。英雄/钢铁挑战有各自的英雄锁定、升级上限和塔限制，不能沿用战役规则。

【验收】M1 对照上述波表及原始 interval/delay/interval_next，不只验证总数；原始路径含子路径，随机选择在测试中可固定或逐条覆盖。最后一波发完仍有存活敌人时不能提前胜利。升级与高级塔在独立测试关卡验证，不修改第一关规则来迁就展示。

<a id="s12"></a>
## 12. Dove 扩展玩法

### 12.1 第三法术

【事实】`spell_system` 注册 9 个模块：`royal_edict`、`aspect_of_sol`、`musketeers`、`wintersongs_wrath`、`rain_of_fire`、`teleportation_sigil`、`thunder_zapper`、`reinforcements_kr6`、`soaring_shop`。只在选中时注册本局模板并加入资源需求；默认没有选择。

选中有效法术使敌人额外生命倍率为 1.1。法术模板先注册，难度补丁随后应用，法术数值 apply 在普通科技补丁之前执行。等级计算以源码实际表达式为准：

~~~text
max_lvl = min(关卡上限或科技/全局上限, 6)
level = clamp(1, max_lvl, ceil(rain_level + reinforcements_level) / 2)
~~~

不要擅自改成 `ceil((rain+reinforcements)/2)`；当前表达式可能产生半级，需要逐模块确认其后续处理。UI 显示、技能冷却、落点合法性和第三技能重演记录必须一起迁移，不能只补一个按钮。

### 12.2 无尽、科技与塔技能

【设计】无尽模式使用独立会话数据，包括波次增长、敌人强化、友方科技、分支等级、塔运行态、评分和恢复位置。沿用 tech ID 和注册表；区分 `apply_template` 与 `apply_runtime`，避免把已有实例的效果只写到模板，或每帧重复施加一次性加成。

数据由 `kr1/data/endless.lua`、`tower_skills_endless.lua`、tech_handlers 和 endless_scripts/系统共同定义。每条科技清单标记数值描述、适用单位、模板/运行态处理器、保存字段和验收样例。塔技能的目标范围可能使用 range_offset，与普通塔射程并非自动相同。

【验收】加载旧无尽会话时重建模板补丁后恢复实例，不能把保存时已乘过的倍率再乘一次；对升级、卖塔、新增单位和已有单位均验证科技生效。波次、金币和科技选择在保存刷新后按已定义状态恢复。M5 前先在 M2 保留本局运行态与模板数据分离的接口。

### 12.3 玩家配置

【事实】`configer` 管理 config、criket、keyset、ui_settings。配置有开关、敌人数量/生命/伤害/速度/金币倍率、塔伤害/范围/冷却、英雄初始等级与经验倍率、反向路径、随机敌人/英雄/塔、额外士兵等。`criket` 是原命名，不在迁移时猜测其含义和字段。

【设计】按原 registry/defaults 建立 JSON 设置与受控 UI；保存并验证数值类型、范围和配置版本。正式玩家支持项由原 UI 与行为共同梳理，不能只迁移音量。用于修改战斗规则的配置在入局时冻结到会话；运行中允许改变的项目逐项声明。

M0/M1 的对照场禁用随机化和额外倍率，M5 单独验收每项配置对模板、波次、英雄和奖励的作用，避免把配置效果误判为数值移植错误。

### 12.4 玩家回溯与调试回放分开

【事实】原版记录玩家决策，通过重建关卡并重演到目标时刻实现回溯；金币、击杀、单位位置和随机流是世界计算结果，不写入普通操作日志。源码明确说明重演随机流可能不同，甚至回到“当前时刻”也可重开一次结果。它不是完整状态快照回滚。

【设计】回溯流程：

1. 选目标时间，关闭暂停等弹层，冻结新输入。
2. 保存必要的持久统计状态，重建同一内容版本、关卡模式、配装与本局配置。
3. 按时间和同 tick 顺序执行已记录命令，验证它们在新世界中的合法性；对已死亡目标、金币不足等情况按原 valid/apply 语义处理，不凭空补钱保证执行。
4. 快速推进模拟，跳过绘制与音效，按帧让出控制以更新进度并避免浏览器无响应。
5. 到达目标时间后截断未来操作与波次刻度，恢复正常 UI/音频及输入，继续新分支。

覆盖的操作族应以 `time_rewind_kinds.lua` 为清单，包括建造/升级/卖塔、技能购买、集结、英雄召唤与移动、下一波、塔模式及世界点击。随机塔记录已解析结果。第三法术与无尽中新增的命令须审计是否完整接入；发现源版未记录的操作，要在差异说明中明确修补，不能默认原记录系统已覆盖全部扩展。

重演期间禁止重复持久化成就、重复奖励外部进度及播放大量音效；收尾只提交当前分支应提交的状态。原版的成就快照和恢复是参考行为。

**调试回放**另设模式，记录固定种子/随机决策及输入，用于同一 Godot 构建的可重复测试。不同引擎即使 seed 相同也不能假设随机序列相同；跨引擎对照使用指定随机结果、固定伤害或采样日志。玩家回溯不强行改成每次得到相同战斗结果。

<a id="s13"></a>
## 13. 文本、音频和存档

### 13.1 动态文案

【事实】现有中英文 JSON 保留 `%$...%$`、`%s` 等占位符。原版表达式可以读取模板、`this`、`level`、`tdmg/tcd`、算术和含 local/return 的语句块；文案数值可能受当前塔的科技或光环影响。

【设计】TextService 保留 locale key，将可达文案逐条转换为带命名参数的模板和受控参数提供器，例如 `tower.xxx.cooldown` 从当前实体/技能数值接口取得。不是把含 Lua 的字符串交给 GDScript Expression 或 JavaScript eval。图鉴用基础配置上下文，战斗菜单用当前实例上下文；同时显示范围、等级、单位和取整格式。

导出时生成“文案 key → 参数提供器 → 依赖字段”清单。未转换的动态表达式使对应内容验收失败；开发模式可显示明确的缺失 key，发布前不可遗留 `%$` 或将整个说明悄悄变空。字体映射按已存在字体做明确替代，中文排版验证粗体、换行、数字和边缘 tooltip；不要全量预热所有字体的所有字形。

### 13.2 音频

【设计】建立 Master、Music、SFX、Voice、UI 音量分组；转换原 sound ID 的文件变体、gain、循环、延迟、并发上限、播放概率/间隔和 group 停止行为。塔/英雄语音与战斗音效分开限制，背景音乐不随切 UI 重复叠加。

【事实】Godot Web 默认 Sample 模式使用 Web Audio，适合低延迟；当前官方文档指出该模式不支持完整 AudioEffects、混响/多普勒等功能。Stream 可获得完整引擎音频能力，但单线程 Web 下延迟更高。

【设计】首版普通短音效优先 Sample，长音乐按内存与循环测试选择 Stream；不依赖必需总线效果才能正确播放。首个“开始”点击同时解锁音频；浏览器拒绝时显示可恢复的音频状态，不重复请求或影响战斗。暂停/继续、静音、切关和回溯分别测试。

### 13.3 存档与导入导出

【已实现】按 BASE 的统一槽位语义保存 JSON，每槽一份 `user://saves/slot_N.json`。数据从冻结 `slot_template.lua` 及 `storage.lua` 默认项导出，保留各世代关卡、英雄、科技、seen、锁定塔、背包与成就字段；`schema_version` 仅标记磁盘格式，来源版本及哈希放在资源清单。缺失关卡表示锁定，空记录表示解锁，数字模式键保存最高难度。胜利写 `last_victory`，进入地图消费后更新最好星级、塔与关卡解锁；失败清除待结算胜利。统一算法读取各世代区间和主线终点，独立于当前可玩资源。设置独立保存，包含 `last_slot_idx`。早期 Web 存档的迁移机制已清理，运行时仅支持统一格式。见 [统一槽位交付](DOVE_SAVES_DELIVERY.md)。

保存触发点至少包括明确配置提交、配装修改、关卡结算及无尽定义的检查点；不依赖关闭网页时才保存。采用上一份可读备份和新文件校验后替换的流程；JSON 导入先在内存验证版本、结构、ID 与数值，再提交，失败保留原存档。

【事实】Web 的 `user://` 持久化依赖浏览器 IndexedDB/存储策略。`OS.is_userfs_persistent()` 可辅助检查，但不能单独保证真实刷新后可恢复，隐私模式和 iframe 策略也可能受限。

【验证任务】M0 就验证一份小存档写入、页面刷新和重开恢复，确认本版本文件系统同步时序；M3 验证完整进度。保存成功状态要与已验证的持久化能力一致；失败时保持可玩并提供 JSON 下载。生产环境优先同源顶层页面；浏览器 JavaScript 桥接仅负责下载/文件选择、可见性及必要存储集成。

不执行 Lua 存档，不提供历史格式转换或运行时迁移分支。

<a id="s14"></a>
## 14. Web 加载、导出和发布

### 14.1 引擎与导出约定

【设计】锁定 Godot **4.7.2 stable**、类型化 GDScript、Compatibility、单线程 Web，使用相同版本导出模板。C#、原 LuaJIT FFI DLL/SO、LÖVE shader 和桌面 updater 不能直接带到浏览器；原 C 排序和哈希结构用 GDScript/Godot 数据结构替代，测量后才考虑专门编译的扩展。

【事实】Godot 4.7 官方文档的 Web 目标为 WebAssembly + WebGL 2，Forward+/Mobile 渲染器不适用；Godot 4 的 C# 项目当前不能导出到 Web。`rendering_device/driver.windows=d3d12` 不会使 Web 获得 D3D12。

初版关闭 Thread Support 与 Extensions Support。普通单线程方案不要求为 SharedArrayBuffer 设置跨源隔离。未来启用线程/扩展时，需另行评估模板、性能与托管条件，包含 HTTPS/安全上下文及 COOP/COEP；不要把这些配置作为首版不必要的前置条件。

### 14.2 资源包划分与接口

【设计】从依赖图生成资源包，而不是按文件扩展名一锅打包：

| 包族 | 典型内容 | 加载时机 |
| --- | --- | --- |
| bootstrap | 主场景、服务代码、最小启动 UI、版本与目录 | 首次打开 |
| menu/map | 当前代际地图、菜单、所用字体/文案 | 进入对应界面 |
| shared gameplay | 基础 UI、通用战斗素材与必要基础塔 | 第一次战斗前 |
| level | 关卡布局、路径、波次、背景、敌人和专属机制 | 选关后 |
| tower/hero/spell | 当前配装及召唤链的资源 | 按所选内容补充 |

共享资源按唯一归属分配，避免多包重复；不把所有高级塔/英雄因为“可选”就全部放进 bootstrap。选中的内容必须在开始战斗前依赖闭合；战斗中不因首次施法才阻塞下载。

~~~json
{
  "schema_version": 1,
  "content_version": "dove-2.1.0.2-web.1",
  "godot_version": "4.7.2",
  "packs": [{
    "id": "level01",
    "url": "packs/level01.<sha256>.pck",
    "bytes": 0,
    "sha256": "<由构建工具填写的64位十六进制值>",
    "depends_on": ["shared_gameplay"],
    "resource_index": "indices/level01.json"
  }]
}
~~~

`bytes=0` 与占位哈希仅说明字段，不可作为发布清单。先下载并校验大小/哈希，再把包标记可用。包中的 Godot 导入产物和 remap 路径也必须来自同一次 Web 导出；复制原 PNG 到 zip 不等于可按原 ResourceLoader 路径加载的 PCK。

### 14.3 加载流程和内存边界

【设计】PackLoader 的状态机为 `未请求 → 下载中 → 校验中 → 挂载中 → 预热中 → 可用`，每阶段均可失败并返回诊断。通过 HTTPRequest 或 HTML shell 的异步加载接口获取内容，禁止主线程同步等待网络。失败提供重试/返回地图，部分文件不当作已完成包使用。单线程不把 threaded resource loading 当作性能保证，预热按帧分批处理。

**PCK 挂载不等于流式读取，也不等于可卸载。** `ProjectSettings.load_resource_pack()` 把包加入资源命名空间；Godot 没有可依赖的通用卸载包对称接口。Web 下载到虚拟文件系统、请求响应、包内容、导入纹理和 GPU 纹理可能同时占内存；写入 `user://` 并不保证原文件离开 Wasm 内存。`DoveAssetCatalog.clear_cache()` 只释放该对象持有的引用。

【验证任务 M0，阻塞全量扩展】下载两个真实 Web PCK，切换场景至少 10 次，分别记录下载缓冲、虚拟文件系统、Wasm 堆、Godot 资源和 GPU 可获得指标；确认挂载后能否删除源包文件及释放何种内存，不预设结论。验证不同包里的 import/remap 是否正确，是否存在路径覆盖和加载缓存污染。

【设计】正式方案采用**有界驻留会话**：单会话只挂载当前关卡及配装依赖，不后台预取整代所有关卡。按 M0 实测制定包大小和累计驻留阈值；达到阈值时先保存进度，回到 shell 后重启 Godot/Wasm 实例，再按新关卡依赖启动。此方案不要求引擎支持卸载 PCK；可保留 HTTP 缓存以减少重新下载。正常小包切关可复用实例，但不得无限累积到全量内容。

纹理引用、AudioStream、EXO 缓存、场景节点和事件订阅各自有租约/释放清单。4096 派生图集与压缩格式须在 Chrome/Edge/Firefox 验证画质及内存；无损 PNG 文件体积小不代表解码后内存小。短音频样本预热量及长音乐解码也纳入预算。

### 14.4 导出与托管

【设计】建立明确命名的 `Web Bootstrap`、`Web Content …` 导出预设；导出选择由构建工具生成依赖文件列表。动态 `FileAccess` JSON 不会自动被所有场景依赖发现，必须包含在对应包的非资源过滤器/清单中。现有 ASSETS 中 `*.json` 是全量开发导出提示，正式分包不能因此把全部 1,519 份资产 JSON 又塞回每一个包。

排除 `source_assets`、reports、tools、tests、docs、原 DLL/SO 和不需要的字体/文案。保留原 `.gdignore` 约定并检查实际导出清单；不把 `.godot` 原始缓存目录整体发布。游戏入口场景、InputMap、视口和音量总线在 M0/M1 显式配置。

Web 产物通过本地 HTTP 服务或正式 HTTPS 提供，不能双击 `file://` 验收。服务保证 `.wasm` 的 `application/wasm`、PCK 的二进制类型、正确 JS/JSON 类型及 gzip/Brotli 对应 Content-Encoding。打包哈希校验基于解压后的实际包字节，不能把 HTTP 压缩大小误作内容大小。

生产部署使用版本目录及内容哈希 URL。先上传全部内容包，再切换短缓存的启动页/版本清单；哈希资源长缓存。一次会话锁定一份 manifest，不能中途混入新版本包。槽位使用独立于内容版本的统一结构，不为关卡更新增加迁移分支。失败可切回旧清单，不覆盖同名旧 PCK 造成客户端混合版本。

首版不启用复杂离线 Service Worker 缓存；确需 PWA 时再验证引擎文件、资源包、清单更新和回滚。跨源 CDN 使用明确 CORS；优先同源托管，具体平台不在本文固定。

### 14.5 性能目标与记录

【设计目标，尚未实测】1080p 普通关卡目标 60 FPS，压力场景至少 30 FPS；逻辑固定 30 Hz。分别记录渲染帧 P50/P95/P99、模拟步耗时、长任务、活动实体/部件/音源数、下载字节与首次可交互时间。

M0 产出参考设备记录（CPU、GPU、内存、系统、浏览器完整版本、DPR），并据真实包测量冻结 bootstrap、单关依赖、Wasm 和纹理预算。不得把 3.09 GiB 开发目录当作允许的首包，也不把未测过的“512 MiB 一定够”写成引擎保证。检查内存要区分浏览器进程、Wasm、CPU 资源和估算 GPU；无法测量的项标明方法与局限。

压力场景由固定输入/随机流生成，包含密集敌人、多个高级塔、英雄召唤、EXO 和持续区域；持续至少 10 分钟，并做 10 次切关。优化顺序为依赖裁剪/大图 → 缓存与分配 → 索敌和脚本 → 绘制与特效；不得为性能删除实际伤害或改变波次。

<a id="s15"></a>
## 15. 里程碑与首批任务

以下保留整体实施路线，已完成部分以 1.3 节及各交付报告为准，剩余能力仍需逐步实现。优先级 P0 表示阻塞基础正确性或下一阶段，P1 表示当前阶段的必要完整能力，P2 表示首版之外的扩展；不以未经验证的固定工期衡量完成。

### 15.1 阶段交付门槛

| 阶段 | 输入与前置依赖 | 交付物 | 完成条件 |
| --- | --- | --- | --- |
| M0 基线与技术验证 | 本文、冻结 Git 对象、现有素材 | baseline manifest、最小数据导出、坐标/普通帧/EXO 场、Web 引导与双包验证、持久化探针、测试设备与预算 | 真实浏览器中资源/挂点正确、动态 JSON 可读、分包失败可恢复、内存边界与存档刷新已记录 |
| M1 第一关闭环 | M0 的数据、资源与时间约定 | 第一关战役、四类基础塔、阻挡、两类敌人、波次、教程/技能、音效、胜负及重开 | 20 生命、270 金币、8 塔位、7 波、48 哥布林+8 兽人；出生时点与规则通过对照；可完成胜/败各一次 |
| M2 通用战斗能力 | M1 正确且可测试 | 升级/卖塔、攻击与状态能力库、飞行、英雄、Boss、独立测试场、能力矩阵 | 每种本批能力有数值/时序样例；至少一种高级塔、英雄和 Boss 在代表关卡可玩 |
| M3 玩家流程 | M1/M2 命令与事件接口 | 多代地图骨架、解锁、选配、科技、图鉴、成就、设置、版本化存档与 JSON 备份 | 从地图选关到成长结果与刷新恢复连通，无需调试脚本改数据才能操作 |
| M4 批量内容 | 内容入口清单、M2 能力矩阵、M3 UI | 各代内容批次、专属机制、挑战/难度、资源依赖和回归记录 | 本批所有可达模板/行为/资源/文案闭合；生产入口只开放已验收内容 |
| M5 Dove 扩展 | M2 状态架构、M3 存档、M4 已迁移能力 | 无尽/科技/塔技能、9 法术、玩家配置和回溯时间线 | 数值、保存恢复、命令覆盖及重演副作用通过验收；源版不足有明确差异记录 |
| M6 完整发布 | 所有目标内容及 M0 起持续维护的 Web 构建 | 可重复构建、浏览器矩阵、性能报告、版本清单、缓存/回滚说明 | 所有发布门槛通过；可部署到静态 HTTP/HTTPS 服务并安全切换内容版本 |

Web 导出在 M0 开始，持续纳入各阶段；不等全游戏完成才第一次打开浏览器。无尽/第三法术的 UI 可暂隐藏，但数据与命令扩展点在早期保留。

### 15.2 可直接领取的首批任务

| ID / 优先级 | 任务与产物 | 依赖 | 验收 |
| --- | --- | --- | --- |
| M0-01 / P0 | 导出 2.1.0.2 BASE 隔离副本，生成源码与配套资源的版本/哈希清单，登记实际设备 | 无 | 源码、安装目录和快照标识与 BASE 一致；相同输入导出可复现 |
| M0-02 / P0 | 建数据 schema、受限数据适配器与模板导出探针，导出第一关和四基础塔 | M0-01 | JSON 可解析；模板继承/脚本绑定不丢失；未支持语法明确失败 |
| M0-03 / P0 | 建坐标投影和普通动画验证场，使用现有 catalog | 无 | 4:3/16:9，背景/塔位/脚点/输入逆变换对齐；高清 UV 不重复放大 |
| M0-04 / P0 | EXO3 姿态采样器和最小播放器，返回挂点变换 | M0-03 | 动作、翻转、alpha/斜切、挂点与源版对照；无绘制时同样可采样 |
| M0-05 / P0 | Web bootstrap、双资源包、动态 JSON、失败重试与实例重启验证 | M0-03 | Chrome/Edge/Firefox 均打开；10 次切换记录内存；预算/驻留边界明确 |
| M0-06 / P0 | `user://` 小存档和 JSON 下载/导入探针、音频解锁 | M0-05 | 刷新恢复；拒绝存储时可备份；首击音效与暂停正常 |
| M1-01 / P0 | SimulationClock、World、EntityFactory、命令/事件、队列 | M0-02 | 固定 tick、暂停/倍速、插入批次和重开清理通过测试 |
| M1-02 / P0 | 路径/网格服务、两种敌人走路与终点结算 | M1-01、M0-03 | 所有第一关子路径正确；单次扣命；离屏出生不误删 |
| M1-03 / P0 | 索敌、普通攻击、伤害消息及基础弹道 | M1-02 | 命中时点、物理/魔法/爆炸、目标消失和致死奖励正确 |
| M1-04 / P0 | 四基础塔、士兵集结/阻挡/补员及基础表现 | M1-03 | 花费来自导出数据；士兵阻挡/死亡/补员，塔位不重复占用 |
| M1-05 / P0 | Lua 波次程序、第一关控制器、HUD、教程与两技能 | M1-04 | 逐波数量与时间匹配；技能按通知解锁；提前开波奖励正确 |
| M1-06 / P0 | 胜负、结算、重开、浏览器闭环及参考记录 | M1-05、M0-05/06 | 空防失败与正常胜利都能返回/重试；连开 3 局数值不漂移 |

M0-03 可与 M0-01/02 按任务依赖独立推进；这是任务图，不要求一定多代理或多人并行。模板导出、EXO、分包的失败先解决，不能通过大量手填 JSON 绕过后再宣称工具链完成。

### 15.3 后续任务分组

| 批次 / 优先级 | 必须完成的子任务 | 关键依赖与产物 |
| --- | --- | --- |
| M2-A / P0 | TSV 指令解析/调度、事件与信号、手动并发波次、强制中断 | 波次样例对照；至少一个实际 TSV 关卡 |
| M2-B / P0 | 全伤害位标志、状态叠加、光环、治疗、死亡生成与反伤 | 数值金样；后续单位共同依赖 |
| M2-C / P1 | 二三级与高级塔、技能购买、卖塔、塔模式及子单位 | 稳定 holder 和命令；独立升级测试场 |
| M2-D / P1 | 英雄经验/技能/复活、多英雄选择数据、飞行和特殊移动 | 能力矩阵；英雄与特性敌人场 |
| M2-E / P1 | 关卡脚本状态机、Boss 阶段/机关/胜利条件 | 代表 Boss 关卡与完整结算 |
| M3-A / P1 | 地图/模式/难度入口、塔/英雄/法术选配、科技 UI | 内容可达清单、动态文案参数 |
| M3-B / P1 | 统一存档槽、设置、成绩、图鉴、成就与备份恢复 | Save schema；刷新/错误恢复集成场 |
| M4-A / P1 | 第一代基础与挑战内容批量迁移，补齐遗漏通用能力 | 每关模式清单、完整依赖和回归 |
| M4-B / P1 | 代际 2/3/5/6 按入口和能力复用程度分批推进 | 每批先标缺失行为，再批量导数据 |
| M5-A / P1 | 无尽数据、科技双处理器、塔技能、会话保存恢复 | 倍率无重复叠加，老/新实例均生效 |
| M5-B / P1 | 9 法术逐模块实现、配置及配装、附加生命平衡 | 选中才加载；每法术一个施放与数值场 |
| M5-C / P1 | 回溯命令覆盖、重建/快进/时间线、副作用抑制 | 从 M1 起的命令日志；随机语义和截断验收 |
| M6-A / P0 | 精确导出、依赖包、缓存、发布清单和回滚演练 | 可重复构建；无旧新资源混用 |
| M6-B / P0 | 性能与浏览器全矩阵、全部目标内容回归 | 第 16 章记录与发布门槛 |
| 后续 / P2 | 移动触控/Safari、PWA 或云功能 | 单独范围与兼容验收，不阻塞桌面首版 |

内容看板使用 `未梳理 → 依赖已知 → 能力已实现 → 可运行 → 已对照 → 可发布`，只看源码文件“翻译完成率”没有意义。阶段完成报告列出本次新增能力、开放内容、实际测试证据与剩余缺口。

<a id="s16"></a>
## 16. 验收体系与完成定义

### 16.1 测试层级与参考方法

| 层级 | 实施方法 | 通过依据 |
| --- | --- | --- |
| 数据静态校验 | schema、ID、模式/入口、资源与行为引用、来源哈希、函数/字段映射 | 本批可达引用无未解释缺失；未映射项有清单 |
| 纯逻辑测试 | 无渲染推进 SimulationWorld；固定输入/伤害/随机决策 | tick 事件、数量、公式、金币/生命和状态满足规则 |
| 能力场景 | 单攻击、单 modifier、阻挡、路径连接、EXO 挂点等小场 | 可定位错误，不依赖打完整关卡才发现 |
| 关卡集成 | 真实数据、可重复命令、胜败与所有开放模式 | 出生/技能/机关/结算与 BASE 对照 |
| 画面对照 | 指定动作和模拟时刻截图，检查脚点/锚点/遮挡/层次 | 结构位置正确；抗锯齿与字体栅格差异单独记录 |
| 浏览器验收 | 实际 Web 导出，三浏览器、刷新/网络/存储/后台流程 | 控制台无未处理错误，实际操作可完成 |
| 长时与切关 | 固定压力场、反复切关及实例重启、重复无尽/回溯 | 无逻辑挂起和无限增长；达到目标或有明确阻塞问题 |

原版参考使用 Dove `2.1.0.2` 的隔离运行副本，核对提交与 BASE 一致，使用独立存档并关闭更新和插件。现有 autoplay 可作为接口参考，使用前确认默认配置和日志副作用；本文未启动原游戏或修改其存档。

跨引擎对比先固定伤害和路径/子路径，再比较确定事件。带随机结果的场景记录决策或比较受控分布；不得仅使用相同 seed 就要求两个引擎生成相同世界。时间戳允许一个 1/30 秒模拟步以内的采样偏差；分支触发次数、价格、奖励、伤害和单位数必须按源规则一致。

### 16.2 最小验收用例清单

以下均为待实现/执行的用例，编号供任务和报告引用。

| 用例 ID | 场景 | 核心断言 |
| --- | --- | --- |
| DATA-01 | 第一关导出 | 8 塔位、初始 20/270、7 组、48/8 敌人；模式覆盖不丢 |
| DATA-02 | 同名帧/别名、索引 | 组+帧唯一定位；Lua nil 孔位、1 基/0 基转换不移位 |
| DATA-03 | 基准哈希不符、未知行为或缺资源 | 明确拒绝/报告，不从未登记来源静默补值 |
| SIM-01 | 暂停 10 秒后继续 | tick/冷却/波次不前进，UI 可响应；继续无积压出生 |
| SIM-02 | 同输入 1×/倍速 | 按模拟时间的事件与数值一致；UI 不加速 |
| SIM-03 | 入场时再召唤、移除时再插入 | 生命周期批次可解释，无遍历跳过和无限递归 |
| SIM-04 | 连续重开三次 | 模板倍率、注册表、事件监听和实体数量无累积 |
| WAVE-01 | 第一波首怪与逐段出怪 | interval 前置等待、interval_next、并发路线与总数正确 |
| WAVE-02 | TSV event/wait_signal/manual repeat | 执行顺序/订阅解除/中断及清怪等待正确 |
| WAVE-03 | 提前开波与末波清场 | 奖励取整与额外效果正确；最后一个活敌人未清不得胜利 |
| NAV-01 | 路径连接、反向和离屏出生 | 游标、目标顺序、终点扣命只发生一次 |
| NAV-02 | 无效集结地形与士兵死亡 | 无效点不扣款/不迁移；阻挡双方关系能释放 |
| COMBAT-01 | 第 9 章伤害金样 | 各类型公式、组合优先级、最高位和特殊倍率正确 |
| COMBAT-02 | 同 tick 致死、反伤、目标消失 | 奖励一次；反伤进入后续队列；无悬空引用 |
| COMBAT-03 | buff 叠加、刷新、结束与源死亡 | 数值正确恢复；不覆盖其他有效效果 |
| UNIT-01 | 塔升级/卖塔/补员/技能购买 | 原子扣款、holder/集结/子单位和价格一致 |
| UNIT-02 | 英雄升级、死亡复活、多选 | 经验/等级、复活点、技能和选择数据正确 |
| UNIT-03 | 多阶段 Boss 与机关 | 阶段条件、免疫、召唤、演出与结算不提前 |
| RENDER-01 | 大小图混合、锚点、翻转与排序 | 物理 UV 与逻辑尺寸分开，Y 方向和层次正确 |
| RENDER-02 | EXO 共享帧、斜切、隐藏和挂点 | 索引正确；无绘制推进的命中点与绘制时一致 |
| UI-01 | 边缘塔位菜单、拖动、Esc、文字输入 | 无误点击/穿透，缩放与输入逆变换一致 |
| SAVE-01 | 刷新恢复、损坏 JSON、未知版本 | 成功恢复或给出可恢复错误，不覆盖有效备份 |
| SAVE-02 | 禁止存储/隐私策略 | 保持可玩，明确持久化状态，JSON 备份可往返 |
| DOVE-01 | 无尽科技升级并保存恢复 | 模板/实例倍率不重复叠加，新生单位一致 |
| DOVE-02 | 法术选择/取消、半级与科技 | 资源/模板按选择注册，生命倍率与技能数值正确 |
| REWIND-01 | 回到某波并继续新分支 | 操作按序重演、无效命令受控、未来日志截断 |
| REWIND-02 | 重演期间成就/声音/第三技能 | 无重复持久化或音效风暴，新增命令覆盖完整 |
| WEB-01 | 首次加载、404、断网、包哈希不符 | 有进度和重试，未完整下载包不能进入战斗 |
| WEB-02 | 新旧 manifest 与缓存并存 | 会话不混版本；回滚后可加载兼容存档 |
| WEB-03 | 标签页隐藏、恢复、音频未解锁 | 自动暂停、无追赶爆发、首击可恢复声音 |
| PERF-01 | 三浏览器普通/压力关卡 | 记录完整设备与指标，普通 60/压力 30 FPS 目标可核查 |
| PERF-02 | 10 次切关与驻留上限触发 | 保存/引擎重启/缓存复用正常；不无限累积资源包 |

### 16.3 每个内容批次的完成定义

- [ ] 原 ID、来源提交及数据哈希已登记，所有本批模式有实际入口。
- [ ] 模板、行为、动画/挂点、声音、文本和资源包依赖闭合。
- [ ] 操作通过命令总线；入场、移除、保存和重演副作用正确。
- [ ] 数值及时序在相同配置下与 BASE 对照，差异有明确结论。
- [ ] 普通、失败、重开路径通过；相关特性有能力级用例。
- [ ] 实际 Web 构建三浏览器通过；无未处理异常或新增缺失资源。
- [ ] 该批性能和峰值内存记录符合已冻结预算；例外作为阻塞问题处理。
- [ ] 内容看板、测试记录和玩家可见入口同步更新。

### 16.4 风险与处置

| 风险 | 早期信号 | 对策 / 阻塞点 |
| --- | --- | --- |
| 安装目录自动更新、基准漂移 | version/hash 与快照不同 | 使用 BASE Git 和快照哈希；M0-01 阻塞 |
| 模板包含执行逻辑，导出不可控 | 继承或函数绑定丢失 | 最小探针与字段映射报告；M0-02 阻塞 |
| 大图/元数据/音频解码超内存 | 首次施法或切图长任务、浏览器崩溃 | 裁剪、派生图集、分批预热和有界实例；M0-05 阻塞 |
| EXO 挂点与显示坐标混用 | 武器错位、离屏子弹起点滞后 | 无绘制姿态采样和矩阵对照；M0-04 阻塞 |
| 固定步长改变临界时序 | 少一击、多一次 DOT、首怪提早 | 帧转换与状态机金样，避免浮点累计漂移 |
| 只实现 Lua 波次 | 部分后代关卡空白/挂起 | TSV 在 M2-A 明确交付，不留到最后 |
| 全量“翻译代码”缺复用 | 同一攻击复制多份且修复不一致 | 能力矩阵、行为 ID 和代表样本先行 |
| 存档被浏览器策略阻止 | 页面刷新丢进度 | M0 探针、真实往返和 JSON 备份 |
| 回溯重复副作用或随机语义变化 | 成就变多、声音爆发、随机塔不同 | 区分玩家回溯/调试回放、命令覆盖审计 |
| 发布混用 PCK/import 缓存 | 只有部分客户端缺资源 | 内容哈希 URL、会话锁版本、原子清单与回滚 |

### 16.5 当前调研与验证范围

【2026-10-27 游侠增量】独立游侠场地通过 215 项逻辑检查、1280×720 原生交互与动画采样、1024×768 新界面检查和来源／像素校验；相邻三级塔、箭塔升级及战斗细节回归通过。结果及边界见 [RANGER_DELIVERY.md](RANGER_DELIVERY.md)。下方 2026-10-25 记录保留当时的素材同步范围，不代表当前战斗进度。

【已完成调研】核对 Dove `2.1.0.2` 的 SRC、安装目录及 SNAPSHOT 版本标识与 BASE 提交；读取核心系统、模板和数据入口；核对当前报告统计、首关布局与波次、塔列表、PNG 头尺寸、Godot 版本和模板安装情况；通过 Context7/官方文档核对 Web 约束。

【2026-10-25 素材验证】已执行增量转换，并独立核对 13,032 个产物文件和 7,016 个来源文件的哈希，无错误。转换链路保持全体 DDS/PNG 的像素校验记录，其中本轮两张更新 DDS 已重新逐像素核对。10 项格式与音频转换测试、Godot 导入、资源加载、空音频解码及主菜单 headless 检查通过；Compatibility 原生窗口加载了本轮两个图集的全部 1,638 个标准帧并抽样截图，1280×720 主菜单交互与音乐播放检查通过。素材数量及源定义告警数量保持不变。

【本轮范围】更新了相邻 SRC 参考仓库、原始资源快照、Godot 运行资源及本文基准和统计；本机安装目录始终只读，未启动原游戏或修改其存档。原生截图和一次性资源检查产物曾生成于 `output/dove_sync_20261025_after/`，现已清理且不提交 Git；结论汇总见 [assets_sync_summary.json](../reports/assets_sync_summary.json) 与 [verification_summary.json](../reports/verification_summary.json)。已有 Web 导出保留，本轮未重新导出或自动操作浏览器；战斗、完整 Web 分包和浏览器性能验收仍待实施。

<a id="appendix-a"></a>
## 附录 A：2.1.0.2 基准与内容核对

### A.1 基准登记入口

本指南只使用 Dove `2.1.0.2`，冻结提交为 `e29ece82939fd73fb69bfc4b469d484a72e4dfd2`。实施任务及验收报告均引用该标识。

| 核对项 | 文件 / 入口 | 预期 |
| --- | --- | --- |
| 源码版本与提交 | [SRC version.lua](../../KingdomRushDove/version.lua)、`git rev-parse HEAD` | `id=2.1.0.2`，HEAD 与 BASE 一致 |
| 素材快照版本与提交 | [SNAPSHOT version.lua](../source_assets/kingdom_rush_dove/version.lua)、[提交记录](../source_assets/kingdom_rush_dove/current_version_commit_hash.txt) | `id=2.1.0.2`，提交记录与 BASE 一致 |
| 当前资源来源与文件哈希 | [assets_manifest.json](../reports/assets_manifest.json) | 来源版本与上表一致；manifest 哈希见 1.4 |
| 当前素材校验结论 | [verification_summary.json](../reports/verification_summary.json)、[assets_verification.json](../reports/assets_verification.json) | 版本、文件数及检查范围与第 1 章一致；告警按附录 B 处理 |

### A.2 完整范围中的塔依赖示例

以下两塔均按 M4 批量内容迁移执行，涉及的 Dove 塔技能机制接入 M5；不得因素材已转换而跳过行为迁移或验收。

| 内容 ID | 定义与行为入口 | 配套资源与核对重点 |
| --- | --- | --- |
| `tower_forger` | [mage_towers.lua](../../KingdomRushDove/kr1/mage_towers.lua)、[tower_scripts.lua](../../KingdomRushDove/kr1/tower_scripts.lua) 中的 `scripts.tower_forger` 及其引用行为 | `go_towers_forger` 图集；攻击/技能衍生实体、升级价格、命中与移除清理；菜单、文案与声音 |
| `tower_sentry` | [archer_towers.lua](../../KingdomRushDove/kr1/archer_towers.lua)、[tower_scripts.lua](../../KingdomRushDove/kr1/tower_scripts.lua) 中的 `scripts.tower_sentry` 及其引用行为 | `go_towers_sentry` 图集与 `sentry*Def` 组合定义；模式切换、技能数值、索敌预留伤害与清理；菜单、文案与声音 |

两塔同时核对 [game_settings.lua](../../KingdomRushDove/kr1/game_settings.lua) 的列表注册、[tower_menus_data.lua](../../KingdomRushDove/kr1/data/tower_menus_data.lua) 的操作及 [map_data.lua](../../KingdomRushDove/kr1-desktop/data/map_data.lua) 的玩家入口。所有技能等级、价格和行为以 BASE 为准，不能按文案或图像推算。

### A.3 本批内容验收入口

- [ ] 为本版本所有实际地图入口生成关卡/模式清单，关联原内容 ID、模板、行为、文案和资源依赖。
- [ ] 四类塔按 25 / 29 / 25 / 30 个列表条目登记，并区分基础级别、进阶塔和特殊条目。
- [ ] `tower_forger` 与 `tower_sentry` 的选择、建造、升级、技能、卖塔及清理流程列入对应回归场景；受关卡限制的操作在独立测试关卡执行。
- [ ] 仅将依赖闭合并通过第 16 章用例的内容开放给玩家。

<a id="appendix-b"></a>
## 附录 B：2.1.0.2 素材告警

### B.1 当前源定义告警

来源：[assets_verification.json](../reports/assets_verification.json)、[ASSET_REPORT.md](../reports/ASSET_REPORT.md)。当前状态是 `passed_with_source_warnings`，素材检查已通过，仍须逐项处理实际使用到的源定义告警。

| 项目 | 数量 / 口径 | 处理方式 |
| --- | --- | --- |
| 图集边界提示 | 35 组图集、379 条记录 | 常见为声明边界舍入 1 像素；保留来源，针对实际可达帧核对采样与 padding |
| EXO 缺部件 | 86 份组合定义 | 按可达动作核对所需图集与别名；不能删除部件消除告警 |
| 普通动画缺帧 | 1,015 个动画定义 | 包括可能未使用的定义；对本批用到的动画逐帧验证 |
| 字体映射缺文件 | 8 个映射名称 | 不等于现有 8 份字体全部损坏；建立显式字体替代并验中文显示 |

当前安装索引的 **4,497 个外部素材全部存在**，当前源码索引的缺失素材列表也为空。上述告警来自源定义/引用关系，不是复制漏文件。修复规则必须记录来源与视觉结果，不能一律夹取 region 或添加空白图片。Web 部署使用大小写敏感路径，并保持源资源 ID。

### B.2 两塔的单帧动画引用核对

上述普通动画告警中，奥术幻铸师有 9 条、哨兵瞭望塔有 2 条属于“动画引用带 `_0001` 的帧名，而对应静态帧不带编号”的情况。例如 `arcane_forger_lvl4_tower_base_0001`、`sentry_tower4_0001`、`sentry_tower4mask_0001`。

当前图像、帧名和动画定义均保留。迁移时先核对对应静态图及原版实际显示，再在有来源记录的适配层建立映射；不能全局删除编号或自动替换所有缺帧。该核对纳入两塔的 RENDER-01/02 验收。

<a id="appendix-c"></a>
## 附录 C：命令、现有验证与官方资料

### C.1 读取 2.1.0.2 冻结源码（只读）

在 PowerShell 中执行；以下命令只读取源码及其版本：

~~~powershell
git -C 'D:/projects/KingdomRushDove' rev-parse HEAD
git -C 'D:/projects/KingdomRushDove' show 'e29ece82939fd73fb69bfc4b469d484a72e4dfd2:version.lua'
git -C 'D:/projects/KingdomRushDove' show 'e29ece82939fd73fb69bfc4b469d484a72e4dfd2:all/game.lua'
git -C 'D:/projects/KingdomRushDove' status --short
Get-Content 'source_assets/kingdom_rush_dove/version.lua'
Get-Content 'source_assets/kingdom_rush_dove/current_version_commit_hash.txt'
Get-FileHash 'reports/assets_manifest.json' -Algorithm SHA256
~~~

后面三条在 WEB 根目录执行。M0 使用 `git archive` 对 BASE 导出至新的工具工作目录，再按清单验证；玩法数据与资源均锁定 `2.1.0.2`。将版本、提交、来源与 manifest 哈希写入基准清单，后续导出和验收复用该清单。

### C.2 已有素材检查命令

以下在 WEB 根目录运行，对应现有工具。最近一次实际执行范围见 16.5 及校验报告：

~~~powershell
python tools/import_dove_assets.py --verify-only
python -m unittest discover -s tests -p 'test_*.py' -v
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import --quit
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_godot_assets.gd
~~~

注意 Godot 检查脚本会写 `reports/godot_assets_verification.json`。`--verify-only` 校验已有目标文件；追加 `--check-source` 可核对 manifest 中记录的来源文件。仍需同时检查安装目录、源码和快照的 `2.1.0.2` 版本标识与 BASE 提交；文件哈希通过不代表游戏玩法完整。

### C.3 后续构建接口

当前已有 `Web Bootstrap` 预设和受内容目录约束的构建工具，交付时使用：

~~~powershell
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
python tools/web_bootstrap.py serve
~~~

本地服务由用户需要浏览器验收时运行，日常功能检查使用 Godot。已有工具生成资源清单、内容目录哈希和导出／隔离 PCK 回执；动态关卡分包、预压缩发布与线程／扩展仍为后续能力，不能把当前单包导出视为分包已经完成。需线程／扩展时另配置所需安全响应头。

### C.4 官方参考资料

核对日期：2026-10-24；优先使用 4.7 分支，避免照抄其他大版本接口。

- [Godot 4.7 Web 导出](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)：渲染器、C#、线程、音频、持久化、后台与托管约束。
- [Web 导出文档源文件](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/export/exporting_for_web.rst)：固定 4.7 分支，便于核查原文。
- [导出与加载 PCK](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_pcks.html)：运行时资源包及其路径行为。
- [命令行导出](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)：`--export-release`、`--export-pack` 与 headless 工作流。
- [Web HTML shell 接口](https://docs.godotengine.org/en/4.7/tutorials/platform/web/html5_shell_classref.html)：启动、预加载与 WebGL 可用性检查。
- [JavaScriptBridge](https://docs.godotengine.org/en/4.7/classes/class_javascriptbridge.html)：文件下载和最小浏览器桥接。
- [ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html)：`load_resource_pack` 的资源命名空间与替换行为。
- [OS](https://docs.godotengine.org/en/4.7/classes/class_os.html)：`is_userfs_persistent` 等平台能力查询。

后续每次升级 Godot、导出模板或资源 schema，都要重跑 M0 的 Web/EXO/存储验证，并同步本指南的基准与兼容结论。
