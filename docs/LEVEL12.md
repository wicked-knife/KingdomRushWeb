# 第十二关：黑塔（The Dark Tower）三模式

基准为 Dove 2.1.0.6，提交 `4072b18bf4e418eec8b813a960c83003744cb710`。开放第十二关战役、英雄挑战与钢铁挑战，一代主线 1–12 关共 **36 个组合**完整闭环。

| 模式 | 初始金币 | 生命 | 波数 | 新建限制 |
| --- | ---: | ---: | ---: | --- |
| 战役 | 1300 | 20 | 15 | 无 |
| 英雄挑战 | 1600 | 1 | 6 | 无 |
| 钢铁挑战 | 2800 | 1 | 1 | 禁炮塔 |

三模式均为 13 个废土塔位、两个开波入口、一处墓地控制器和四座火盆，科技上限 6，允许已实装的马利克参战。战役与挑战按 `editor.game_mode` 区分前景：英雄／钢铁模式在城堡阳台显示 `stage12_forsale` 待售牌；墓地矩形 `(95, 318, 117, 58)` 允许施放火雨与援军。第十三关及后续精英关保留地图预览。

## 维兹南与专属机制

- **高塔阶段（`welcome` / `castle`）**：战役开局在 `pos_castle (518, 677)` 插入 `eb_veznan`，难度 2 生命按 `all/difficulty.lua` 的数组直取 `7999`（不叠乘 `1.65`）。支持全部 30 句简体中文嘲讽气泡（`decal_s12_shoutbox` 呼吸缩放与淡入淡出）；第 6–15 波按源波次表开启 1/2/3 号传送门，第 9–15 波按源波次表施放限时封塔。
- **限时封塔（`mod_veznan_tower`）**：`start`（32 帧）后进入循环 `preHold` 并显示 `decal_veznan_tap` 点击提示与封锁计数。4 秒窗口内点击 3 次提前解除；超时播 `VeznanHoldTrap` 进入 `hold` 强制封锁 6 秒，随后播放 `remove` 解锁清理。
- **传送门（`veznan_portal`）**：3 座传送门分别对应 `out_nodes` 101/146/221，激活后按源概率表依次刷出恶魔、恶魔狼或恶魔法师并附带 `fx_demon_portal_out`。
- **下场与魂吸（`pre_battle` / `battle`）**：全部波次清场后切 `MusicBossFight`、播嘲讽 #30 与 `walkAway`，瞬移至路径起点进入战斗。执行范围魔法近战（`666–999`，8 目标，`decal_veznan_strike`）、封塔、传送门，以及 Dove 2.1.0.6 魂吸技能 `soulDrain`（范围 150，过滤 `elemental` 元素免疫，施加解离即死、生成直线飞向手部的 `veznan_soul` 并回血 `3.5%` 最大生命）。
- **魔化变身（`demon`）**：人形态致死伤害由 `on_damage` 拦截，清状态播 `VeznanToDemon` 与 `demonTransform`，切换为恶魔形态：生命 `initial_hp × 1.5 = 11998.5`、移速 `18`、切 `eb_veznan_demon` 前缀与 `info_portraits_enemies_0072` 头像，启用 8 段物理火焰范围近战（`hit_times` 为 20/24/28/32/36/38/42/44 帧，首段生成 `fx_veznan_demon_fire`）。
- **死亡与主线结算（`death` → `death-end`）**：恶魔致死拦截后清场零金币、封锁场上全部塔、停音频播 `VeznanDeath` 并触发 `hide_gui`；第 110 帧启动 `veznan_souls_aura` 发射带 `ps_veznan_soul` 衰减粒子的曲线飞魂；随后播 `deathLoop`（90 帧）与 `deathEnd` + `decal_eb_veznan_white_circle` 全屏白光膨胀，完成后触发标准两阶段胜利结算（并预留 `custom_game_outcome = "kr1_end"` 钩子，不含演职员表）。

## 验证与集中交付

```powershell
python tools/prepare_level01.py --level 12
python tools/prepare_level12_reference.py
python tools/prepare_upgrades.py --check --reference --reference-level 12
python tools/verify_level01_assets.py --level 12
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/level12-logic.log --script tests/verify_level12.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/level12-upgrades.log --script tests/verify_level12_upgrades.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x720 --log-file output/level12-native.log --script tests/level12_visual.gd
python tools/verify_level12_delivery.py
python -m unittest discover -s tests -p test_web_packs.py -v
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
```

独立源采样核对三模式 22 波共 1110 次出怪、限时封塔、三座传送门、灵魂光环与维兹南全生命周期；科技对照覆盖 16 组源补丁与三模式马利克参战；前十一关与游侠测试场共 246 个数据文件保持逐文件 SHA-256 零变动。Web 集中交付产物为 `build/KingdomRush-KR1-Levels01-12-Web.zip`，浏览器运行、音频解锁与存档持久化由用户手动验收。
