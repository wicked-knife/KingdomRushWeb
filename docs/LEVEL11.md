# 第十一关：凄凉山谷三模式

基准为 Dove 2.1.0.6，提交 `4072b18bf4e418eec8b813a960c83003744cb710`。

| 模式 | 初始金币 | 生命 | 波数 | 新建限制 |
| --- | --- | --- | --- | --- |
| 战役 | 1300 | 20 | 19 | 无 |
| 英雄挑战 | 2100 | 1 | 6 | 无 |
| 钢铁挑战 | 2600 | 1 | 1 | 禁箭塔、炮塔 |

三模式均为 18 个塔位、两个开波入口，科技上限 6，允许已实装的马利克参战。战役三星后开放挑战；胜负、重开和返回地图沿用两阶段存档流程，第十二关仍为预览。

死灵法师按实际源协程召唤：8 秒严格冷却，12 帧施法准备、每次出生前等待 4 帧，最多五只；骷髅零赏金，随机速度和大小，受到伤害乘 0.7，主人死亡释放该系数。保持实际源列表上限 30 及其清理循环语义；召唤过程中沉默不会中断，死亡／眩晕按源等待边界处理。敌方魔法弹使用独立的追踪、加速和命中流程。

熔岩元素沿用源生命、护甲、魔抗、电伤系数、十目标范围近战和毒／火禁用。布局生成器在第一波开始后等待 400 秒，之后每 120 秒出生一次，位置 `(498,383)`、源路径 4，从非循环出生动画进入强制路径移动；未来计时器不阻止胜利。新增单位按源保留死亡末帧和完整不透明度，实体在尸体寿命结束后清理。

独立源采样读取固定提交的原始波次、布局与实际 Lua 函数，比较三模式 26 波共 1472 次出怪、11 个召唤场景、5 个魔法弹场景、12 个近战和 6 个远程场景。比较报告保留完整预期、实际值和首次差异。新增敌人覆盖字段单独求值，科技另有 16 组源补丁比对。Godot 原生检查使用受控短场景和构造结算，不代表 AI 打通挑战。

```powershell
python tools/prepare_level01.py --level 11
python tools/prepare_level11_reference.py
python tools/prepare_upgrades.py --check --reference --reference-level 11
python tools/verify_level01_assets.py --level 11
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/level11-logic.log --script tests/verify_level11.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/level11-upgrades.log --script tests/verify_level11_upgrades.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x720 --log-file output/level11-native.log --script tests/level11_visual.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/level11-shared.log --script tests/verify_level11_shared.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/level11-ranged-shared.log --script tests/verify_level11_ranged_shared.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/hero-regression.log --script tests/verify_hero_malik.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/tesla-regression.log --script tests/verify_tesla_animation.gd
python tools/verify_level11_delivery.py
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
```

交付门禁核对当前报告及输入哈希、资源像素和依赖缺失反例，并对前十关和游侠测试场保留逐文件 SHA256 检查。Web 包包含前十一关 33 个模式组合，PCK 在独立 Godot 工程中检查；浏览器输入、音频解锁和持久化由用户手动验收。
