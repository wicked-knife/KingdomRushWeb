# 战斗行为与动画迁移约定

基准为 Dove `2.1.0.2 / e29ece82939fd73fb69bfc4b469d484a72e4dfd2`。
本轮修复兵营门、集结、箭、炮弹及爆炸、绵羊点击、单位属性。日常继续使用 Godot 验证，浏览器由用户验收。

## 已核对的源行为

| 行为 | Dove 来源 | 当前映射 |
| --- | --- | --- |
| 兵营出兵与门 | `all/scripts.lua` 的 `tower_barrack.update`；`kr1/foundamental_towers.lua` | 缺员后开门，5 帧开门动画结束才出兵，保持 `door_hold_time = 0.5s`，再播 4 帧关门。关门后保持末帧；只有下一次补兵才重开。集结不触发开门。 |
| 集结移动 | `all/script_utils.lua` 的 `y_soldier_new_rally`；`all/utils.lua` 的 `walk_off__accel__unsnapped`、`rally_formation_position` | 校验落点地形与椭圆范围后，解除原阻挡和待结算近战，直接朝各自阵型点移动。集结移动期间不索敌，到达后恢复战斗。取消此前额外添加的四向网格寻路。 |
| 箭塔 | `all/scripts.lua` 的 `tower_archer.update`、`arrow.insert/update` | 两名射手轮流播放各自的 8 帧动作，发射点跟随轮值射手；箭使用命中偏移、当前移动速度预判与 `g = -900`，一级飞行 22 帧、二级 21 帧，沿速度方向旋转，并在距起终点 6 单位内隐藏。 |
| 箭塔升级与出售 | `kr1/foundamental_towers.lua`、`all/tower_utils.lua`、`kr1/data/tower_menus_data.lua` | 一级升二级为 110 金币事务，切换当前模板、保留 holder/位置/地形并累计投入至 180；新塔重新等待 18 帧攻击冷却，旧待发攻击取消，已发箭保留一级数值。开波前全额退款，开波后按累计投入 × refund_factor 四舍五入；提示与事务共用计算。首关命令层读取原二级塔锁定，升级只在独立测试场验证。 |
| 三类二级塔 | 同上；`all/templates.lua` | 兵营/炮塔/法师塔升级费 110/220/160，累计投入 180/345/260；开波后退款 108/207/156。共用原升级命令，成功关闭菜单，二级无三级入口；首关仍禁止四类升级。 |
| 兵营换兵 | `all/tower_utils.lua`、`all/systems/health.lua`、`y_soldier_new_rally` | 存活民兵原位替换成满血步兵：100 生命、15% 物甲、4–6 伤害；继承朝向及攻击时间戳，换接阻挡引用，再执行解除阻挡的重新集结。旧未结算近战和尸体移除，缺员经新门动画补齐。集结范围从 145 升至 150。 |
| 法术弹道 | `tower_mage.update`、`bolt.insert/update` | 两级法术共用加速追踪：初速 30、最高 300、加速因子 0.05，逐 tick 使用源向上取整公式；目标位移任一轴超过 128 后永久停止追踪。目标失效时仍到保存落点播放命中特效，但不造成目标伤害；前摇结束已超出 1.1 倍射程时向起手落点发射无目标法术。 |
| 冷却与朝向 | `tower_mage.update`、`tower_engineer.update`、`soldier_melee_attacks` | 法师严格超过 1.5 秒，民兵/步兵严格超过 1 秒/41⁄30 秒，分别在 46/31/42 tick 可再次起手；炮塔达到 90 tick 即可。箭塔仍为既有 18 tick 基准。法师、炮塔沿用源固定水平朝向，箭塔保留水平翻转。 |
| 炮塔 | `all/scripts.lua` 的 `tower_engineer.update`、`bomb.insert/update` | 七个活动图层各自播完整 35 帧射击/复位动作；31 帧抛物线、`g = -900`、随机初始角与 600°/s 自转，起终点 8 单位内隐藏。目标先死时仍射向保存的地面落点。 |
| 炮弹命中 | `all/templates.lua` 的 `fx_explosion_small`、`decal_bomb_crater`；`bomb.update` | 18 帧单次 `explosion_big`，保留原锚点及 0.9 缩放；弹坑停留 1 秒、于 2.5 秒消失。爆炸伤害按源距离衰减及护甲曲线计算。 |
| 绵羊 | `kr1/template_groups/decal_sheep.lua`；`all/scripts.lua` 的 `delayed_play.update` | 前 7 次点击叫声与 0 → 0.12 → 0.16 秒的缩放关键帧；第 8 次移除绵羊并只触发一次爆炸。保留 10% 替代爆炸/音效、随机朝向和间歇吃草动作。状态随暂停、倍速、重开统一控制。 |
| 单位信息 | `all-desktop/game_gui.lua` 的 `InfoBar`；`soldier_barrack.get_info`、敌人模板 | 依据源点击框选择存活单位，下方显示原底板、头像框、头像、译名/随机姓名、实时生命、伤害与间隔、物理/魔法护甲、补员时间或漏怪扣命。援军保留外观对应头像。单位死亡、右键、Esc、重开会清除选择；面板拦截点击。 |

弹道采用源初速度公式和重力的解析采样，保证固定模拟步长下准确到达指定终点；没有逐行复写源协程的 Euler 积分误差。战役模拟继续固定 30 Hz。

## 代码职责

- `level01_sim.gd` 管理门状态、射手轮值、每层动作起始 tick、直线集结、装饰物点击与效果生命期。显示层不再通过模板名猜测何时循环。
- `dove_animation.gd` 统一解析普通动画、单次末帧、持续时间和分段关键帧。显示层必须应用源 `loop`、`scale`、`anchor`、`sort_y_offset` 和旋转。
- `dove_projectile.gd` 根据源 `g`、飞行时间、`rotation_speed`、`align_with_trajectory`、`hide_radius` 采样弹道。世界到画面的旋转符号只在显示入口转换。
- `dove_unit_info.gd` 提供源点击框选取和只读属性快照；`battle_ui.gd` 使用既有 `DoveUILayout` 组合信息底栏。头像、文字、属性条和命中区域共用缩放。
- `prepare_level01.py` 除行为状态外，必须收集每张精灵的实际默认动画名。例如 `explosion_big`、`explode_small` 不属于 `idle/shoot/death` 枚举，也必须纳入依赖。生成 PNG 使用临时文件替换，避免编辑器导入时读到部分输出。

后续加入单位、塔或关卡时，先扩展导出数据和模拟状态，复用以上组件；特殊动作需要显式状态和回归样例，不能重新引入按模板名猜动画长度、循环或弹道的逻辑。以上组件仍以首关实际使用能力为范围，不代表已覆盖其他关卡全部技能。

## 验证

```powershell
python tools/verify_level01_assets.py
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_battle_details.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level01.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/battle_details_visual.gd --resolution 1280x720
```

原生检查也运行 `1920x1080`、`1024x768`。它通过源点击框操作民兵、兽人、援军和羊，记录门与集结位置、实际塔攻击产生的连续弹道/爆炸帧，并审计单位底栏文字与命中区域。属于可重复的原生渲染回放，未声称进行逐音效人工听辨。

版本库保留精简汇总 `reports/battle_details_report.json`。复跑时生成 `reports/battle_details_logic.json`、`reports/battle_details_visual_<分辨率>.json`、`reports/details_*`；这些临时产物不提交 Git，可随时清理。完整战役继续使用 `tests/battle_visual_smoke.gd` 回归。Web 交付时须包含三个新公共脚本，并通过隔离 PCK 检查。
