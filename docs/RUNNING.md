# 运行、检查与交付

项目使用 Godot 4.7.2 兼容渲染器。直接打开 `project.godot` 后按 F6／F5，或运行：

```powershell
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path .
```

运行现有内容不依赖 Python、LÖVE 或原游戏安装目录。首次导入需要生成 Godot 缓存。

## 更新 Dove 与生成数据

先在干净的 `D:/projects/KingdomRushDove` 拉取最新代码，更新 `data/campaign_content.json.source`，随后执行：

```powershell
python tools/sync_dove_assets.py
python tools/prepare_upgrades.py
python tools/prepare_level01.py --all
python tools/prepare_level01.py --ranger-arena
python tools/prepare_map.py
python tools/prepare_heroes.py
python tools/prepare_saves.py
python tools/prepare_upgrades.py --reference
```

Python 依赖见 `tools/requirements.txt`。导出脚本默认使用本机源码和 LÖVE 路径，可通过 `--source`、`--love` 指定；每份产物保留源提交和输入文件哈希。媒体与源元数据合并方式见 [素材说明](ASSETS.md)。

## 专项检查

只运行与改动相关的检查，范围见 [验证约定](TEST_REDUNDANCY_REVIEW.md)。共用战斗变更的代表命令：

```powershell
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_current_dove.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_content_unification.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_level06.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_dove_saves.gd
python tools/verify_content_catalog.py
python tools/verify_level01_assets.py --level 6
```

重新采集当前源协程样本：设置 `DOVE_SOURCE_DIR` 为源码绝对路径、`DOVE_CATALOG` 为项目目录清单绝对路径、`DOVE_REFERENCE_OUTPUT` 为 `tests/fixtures/dove_current_source.json` 的绝对路径，然后用 LÖVE 运行 `tools/current_reference`。

原生专项脚本位于 `tests/*visual*.gd`，截图及临时日志写入忽略目录。画面、输入、音频优先用 Godot 原生窗口；不为日常检查反复导出 Web。

蜘蛛产卵／孵化专项：`python tools/prepare_spider_reference.py` 生成源样本；使用 Godot 的 `--headless --path . --script tests/verify_spider.gd` 检查逻辑，去掉 `--headless` 并加 `--resolution 1280x720` 检查实际画面。两种运行分别保留完整逐帧比较，原生运行另外生成 `reports/spider_native_frames.png`。

死亡动画专项：先运行 `python tools/verify_wolf_death_source.py`，再用 Godot 的 `--headless --path . --script tests/verify_death_animation.gd` 检查逻辑；去掉 `--headless` 并加 `--resolution 1280x720` 检查原生渲染。包括座狼、小狼及共用隐藏规则的代表单位，不运行完整战役。

默认科技专项：

```powershell
python tools/prepare_upgrades.py --check
python tools/verify_upgrades_assets.py
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_upgrades.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1280x720 --script tests/upgrades_native.gd
& 'D:/godot/Godot_v4.7.2-stable_win64_console.exe' --path . --resolution 1024x768 --script tests/upgrades_native.gd
```

`prepare_upgrades.py --reference` 会重新生成实际源补丁和行为样本；不需每次开发都执行。规则和保留的源行为见 [默认科技](DEFAULT_UPGRADES.md)。

## 玩家操作与存档

首波单击入口骷髅开始，后续双击同一入口提前开波，空格可直接开波；悬停显示敌人预告及路线。左键选择／建塔／集结／施法，右键取消，Esc 关闭当前界面或暂停，1／2 选择火雨／援军。落点指示器出现时隐藏系统鼠标，退出模式或失焦时恢复。

战役三星开放对应挑战。胜利先保存 `last_victory`，进入地图后更新最好星级与下一关；胜利后直接重开并失败会清除尚未结算胜利，已结算成绩保留。三槽存于 `user://saves/slot_1.json` 至 `slot_3.json`；音量和最后槽位存于 `user://settings.json`。新槽位采用当前源模板，科技 ID 为字符串，不创建成就字段；已有未知字段仍原样保留。损坏或较新格式不作为空槽覆盖。

地图科技按钮打开默认方案。可跨级购买、点击已购节点退级、撤销或重置，操作即时保存；未结算的胜利星星不能消费。其他方案存档保留原数据并提示暂不支持，当前禁止科技操作与开战。

## Web 交付

```powershell
python tools/web_bootstrap.py export --check-pack
python tools/package_level01.py
python tools/web_bootstrap.py serve
```

交付时集中导出一次。发布包在 `build/KingdomRush-KR1-Levels01-06-Web.zip`，目录在 `build/web`；使用 HTTP 服务访问，不能直接打开 HTML 文件。导出默认 release，开发者入口关闭；需要调试包时显式加 `--debug`。隔离 PCK 检查验证菜单、地图、英雄房间和全部 18 个组合的资源，不代替浏览器验收。浏览器由用户手动检查输入、声音解锁、后台标签页和持久化。
