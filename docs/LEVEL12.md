# 第十二关：维兹南终战与主线结尾

基准为 Dove 2.1.0.6，提交 `4072b18bf4e418eec8b813a960c83003744cb710`。普通难度 2、默认科技方案和马利克；三模式初始金币 1300／1600／2800，生命 20／1／1，波数 15／6／1，13 个塔位、两处入口、三处传送门。钢铁挑战禁建炮塔，科技上限六级。

结尾按用户修订省去制作名单数据及界面：Boss `death-end` → 胜利评分面板 → “继续” → 主线漫画 → 尾声漫画 → 地图两阶段结算。胜利面板仍可重开，重复战役胜利可再次播放。挑战和失败直接返回地图。`MusicEndCredits` 只是主线漫画沿用的源配乐标识，没有制作名单内容。

维兹南行为由 `scripts/battle/dove_veznan.gd` 独立维护，关卡控制器 `scripts/battle/controllers/level12.gd` 负责墓地、额外火雨区域、波次清场及结尾路由。主循环通过行为分派工作。城堡阶段按波次配置封塔和传送门；人形致命伤进入变身，恶魔致命伤进入死亡演出。魂吸包含元素免疫、每目标一次、回血、飞行及眩晕／阶段中断。封塔准备、点击窗口、超时和移除分别计时，阻塞引用直到移除动画结束才释放。

恶魔形态使用运行时模板更新命中点、附着点、体型、速度、攻击、头像及点击范围；弹丸和状态特效读取运行时模板。死亡期间禁止战斗输入，清空召唤队列，隐藏 HUD，播放灵魂和白光，最终移除 Boss；生命归零先判负。重开重新初始化全部专属状态。

`finished` 仍只保存待结算成绩，`routed` 单独传递 `kr1_end`。按需分组沿用现有内容寻址、校验和缓存，加载失败可重试或返回地图。存档不新增路由、观看标记或播放位置；中途退出仍按既有待结算胜利恢复。漫画使用源 CSV 的顺序、关键帧、缓动、中文及声音，播放中首次输入跳至页末，再次输入换页。

## 可重现检查

```powershell
python tools/prepare_level01.py --level 12
python tools/prepare_ending.py
python tools/prepare_level12_reference.py
python tools/verify_level01_assets.py --level 12
python tools/verify_ending_assets.py
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/level12-logic.log --script tests/verify_level12.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file output/level12-flow.log --script tests/verify_level12_flow.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x720 --log-file output/level12-native.log --script tests/level12_visual.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1024x768 --log-file output/level12-native-1024.log --script tests/level12_visual.gd -- --layout-only
python tools/verify_level12_delivery.py
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
```

首次导出新图片后，先用 Godot 编辑器导入资源。日常不导出 Web；源码、逻辑和原生专项完成后集中导出一次。浏览器输入、音频解锁和持久化由用户手动验收。

源 Lua 参考工具执行实际波次出生器、Boss、封塔、近战、传送门及灵魂生成协程，并重新求值 Boss 源模板覆盖。三模式核对 22 波、1110 次出生；完整 expected／actual 与首次差异保存在 `reports/level12_timelines.json`、`reports/level12_comparisons.json`。数据条数不视为独立场景数。专项使用构造场景，不宣称实战通关。

必要相邻回归复用当前 JT、墓地、科技、马利克和共用攻击样本。`tests/fixtures/level12_compatibility.json` 对前十一关及游侠测试场内容逐文件校验；不重跑全战役。交付门禁检查报告新鲜度、资源闭包和缺少模板／行为／回调／漫画／音频的拒绝反例。
