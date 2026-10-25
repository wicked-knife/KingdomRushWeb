# 英雄房间与双英雄选择

实现基准为 Dove 2.1.0.2，冻结提交 `e29ece82939fd73fb69bfc4b469d484a72e4dfd2`。地图左下角“英雄”现已开放，提供全部 79 名英雄的中文资料、四项属性、373 条已求值的技能说明、选择语音及双英雄配置。英雄战斗行为尚未接入，当前首关仍不生成英雄，房间内有相应说明。

## 玩家操作与解锁

- 七列列表可用滚轮、滚动条浏览；锁定英雄也能查看立绘、简介和技能说明。
- 按原版指定关卡的通关成绩解锁；新档不自动选择英雄，首关通关解锁 12 名英雄。其他英雄保持各自通关条件，未开放的关卡不会因此开放。
- 最多选择两名，头像分别标记 1、2；选满后新选择替换第二名，取消第一名后第二名前移，也可全部取消。
- 地图入口按空选择、单英雄、双英雄显示对应头像；双头像使用原版对角裁切。
- Tab 在已选英雄间切换并将其滚动到可见区域；完成、关闭、Esc、右键均可关闭房间。弹窗阻挡底层地图输入，技能正文与滚动条区域也支持右键关闭。
- “技能详情”切换为技能列表和可滚动正文，“英雄资料”返回简介与属性。

## 来源、资源与存档

`tools/hero_export/main.lua` 在独立 LÖVE 进程中评估常量、组件和模板注册以及动态技能文本。模块采用白名单，战斗脚本为不可执行的占位对象；没有加载原游戏入口、更新器、插件或玩家存档。31 份输入文件的 SHA-256 与源纹理哈希记录在英雄目录及清单中。

`tools/prepare_heroes.py` 生成 `data/heroes/`：79 名英雄、373 条技能、181 个界面帧和四张 2048² 派生图集；保留原始尺寸、裁切与缩放信息。地图包只补入英雄入口头像，完整英雄房间的图片与选择语音首次打开时分帧加载。关闭房间保留本地图会话的缓存，离开地图释放场景、图集及声音引用。加载失败可返回或重试。

原素材缺少 `hero_dwarf`（鲁林·长胡子）、`hero_vampiress`、`hero_bolverk` 三名英雄的大立绘；使用各自已有缩略头像兜底，没有生成或替换背景图。

三个槽位的 `campaign.json` 沿用 schema 1，新增可选 `heroes.selected` 字符串数组；缺少字段的旧档默认为空。加载时过滤无效与未解锁 ID、去重并最多保留两名。选择与取消立即保存，关卡结算保留配置，沿用临时写入、有效旧档备份、损坏恢复和写入失败提示；失败时本次运行仍保留选择。设置和英雄配置继续分离。

`CampaignProgress` 提供 `hero()`、`is_hero_unlocked()`、`selected_hero_ids()`、`select_hero()`、`deselect_hero()`；选择顺序和解锁判断统一由服务处理，界面不独立修改存档。

## 验证

```powershell
python tools/prepare_heroes.py
python tools/prepare_map.py
python tests/verify_hero_assets.py
python tests/verify_map_assets.py
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_hero_room.gd
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/hero_room_visual.gd --resolution 1280x720
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/hero_room_visual.gd --resolution 1920x1080
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/hero_room_visual.gd --resolution 1024x768
```

资源检查覆盖全部来源哈希、运行依赖、文案占位符、头像/语音引用及派生图集逐帧像素一致性。Headless 检查覆盖首关解锁、双选替换、取消前移、无效配置清理、旧档、备份、写入失败、三槽隔离及地图/战斗往返。原生窗口脚本通过引擎输入事件检查按钮、滚动后头像命中、Tab、Esc、右键与选择语音播放游标，并审计全部 79 名英雄的资料排版。截图另外检查锁定、解锁、双选、三处立绘兜底及最长技能正文；脚本输入不等同于人工实时游玩。

精简结果为 `reports/heroes_assets.json`、`heroes_logic.json` 和 `heroes_delivery.json`；截图及逐分辨率报告不提交 Git。

## Web 交付

```powershell
python tools/web_bootstrap.py export --debug --check-pack
python tools/package_level01.py
```

交付包为 `build/KingdomRush-KR1-Playtest-Debug-Web.zip`。导出清单包含菜单、地图、英雄房间与首关的明确依赖，保持 Compatibility、单线程。2026-10-26 交付通过隔离 PCK 检查，共 411 个文件；ZIP 约 87.8 MiB，校验与包哈希见 `reports/heroes_delivery.json`。浏览器中的功能、首次声音解锁和持久化由用户手动验收。
