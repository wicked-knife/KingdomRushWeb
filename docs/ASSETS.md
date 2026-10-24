# Dove 素材使用说明

资源基准是本机已安装的 Dove 版本：`D:\王国保卫战Dove版\KingdomRushDove`。
`D:\projects\KingdomRushDove` 仅用于报告新版源码差异，不覆盖安装版本的资源定义。
原安装目录始终只读；所有操作都是复制和生成新文件。

当前资源快照为 **2.1.0.2**（2026-10-24 同步），安装版本与源码提交均为 `e4278f83d913f96a8d35a17f912e0c21945bfdac`。

## 后续复刻指导

源码阅读索引、Godot 架构、数据迁移规则、Web 分包、阶段任务和验收清单见 [Godot Web 复刻指导文档](GODOT_WEB_REMAKE_GUIDE.md)。指南保留已确认的 `2.1.0.1` 玩法对照基线，并单列当前 `2.1.0.2` 资源同步情况与兼容核对规则。

## 目录

| 目录 | 内容 |
| --- | --- |
| `source_assets/kingdom_rush_dove/` | 原始 `_assets`、游戏与界面配套数据、版本信息；由 `.gdignore` 排除导入和导出 |
| `assets/kingdom_rush/` | Godot 使用的 PNG、OGG、TTF/OTF/TTC、JSON 和资源目录索引 |
| `scripts/dove_asset_catalog.gd` | `DoveAssetCatalog`，按需读取元数据和纹理 |
| `scenes/asset_preview.tscn` | 独立素材预览场景，用 F6 运行，无须修改项目主场景 |
| `reports/` | 搬运清单、完整性校验、源码差异与 Godot 检查结果；不导入游戏 |

原始文件包括 582 张 DDS、3,899 段 OGG、8 份字体、490 份 KRAB 图集，以及 1,021 份 EXO3 组合动画。
转换保留图集，不把十几万帧拆成独立 PNG。

## 导入与验证

在项目根目录的 PowerShell 中执行：

```powershell
python -m pip install -r tools/requirements.txt
python tools/import_dove_assets.py
```

本机已经安装 Pillow 13.0.0，无须重复安装。指定其他安装目录：

```powershell
python tools/import_dove_assets.py --source 'D:\王国保卫战Dove版\KingdomRushDove'
```

工具逐项写入检查点；中断后执行同一个命令即可继续。只有来源哈希、转换器版本、目标大小和目标哈希都匹配的文件才会跳过。
582 张 DDS 转换时逐张解码为 RGBA，再重新读取 PNG 比较像素，覆盖 DXT1、DXT5 和 BC7。
原始文件、OGG 和字体通过 SHA-256 核对。不会启动或执行原游戏 Lua。

本机游戏更新后，先拉取参考源码，再同步安装目录中的资源：

```powershell
git -C D:\projects\KingdomRushDove pull --ff-only
python tools/import_dove_assets.py
```

源码拉取不会更新本机安装包；导入时始终以已经更新完成的游戏安装目录为准。
本次更新新增奥术幻铸师（`go_towers_forger`）、哨兵瞭望塔（`go_towers_sentry`）图集、39 段音频和 9 份组合动画；中英文文案各为 9,573 条。
本次增量清单及版本信息见 `reports/assets_sync_summary.json`。

```powershell
python tools/import_dove_assets.py --verify-only --check-source
python -m unittest discover -s tests -p 'test_*.py' -v
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --editor --import --max-fps 30
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_godot_assets.gd
```

首次 Godot 导入会生成较大的 `.godot` 缓存。图片默认使用 Godot 的 2D 无损导入设置，不缩小原图；字体支持中文 TTC。
转换期间可能暂时存在 `assets/kingdom_rush/.gdignore`，用于防止编辑器扫描尚未完成的素材；成功完成转换后才移除。

## 访问图片与动画

```gdscript
var assets := DoveAssetCatalog.new()
var frame := assets.get_frame("go_towers_group4", "soldier_lvl4_barbarian_0003")
$Sprite2D.texture = frame["texture"]

var animation := assets.get_animation("soldier_barbarian_running")
# animation["fps"] == 30；animation["frames"] 是有序帧名，可逐帧交给 get_frame。

var composition := assets.get_exoskeleton("archer4Def")
var sound := assets.get_sound("AmazonTaunt")
$AudioStreamPlayer.stream = load(sound["paths"][0])
$AudioStreamPlayer.play()

var chinese := assets.get_static("locale_zh-Hans")
var font_rules := assets.get_static("fonts")
assets.clear_cache()
```

`get_frame()` 返回 `texture`（AtlasTexture）、`region`（实际纹理像素区域）、`source_region`、`logical_size`、`original_size`、`trim` 和 `ref_scale`。
`Sprite2D.texture` 示例用于观察裁切；还原游戏坐标时应使用逻辑尺寸、裁切偏移和缩放，不能把物理纹理大小直接当作游戏尺寸。

部分高清 DDS 的实际尺寸与原版图集声明尺寸不同。实际裁切区域按以下方式换算，逻辑尺寸不改变：

```text
region.x / region.width 乘以 actual_texture_width / declared_texture_width
region.y / region.height 乘以 actual_texture_height / declared_texture_height
```

不同组可以拥有同名帧，因此必须同时指定分组和帧名。图集中的别名保留；元数据和纹理按调用加载，`clear_cache()` 释放目录持有的引用，调用者仍持有的纹理保持有效。

## 数据约定与边界

- JSON 的 `schema_version` 为 1，普通动画默认 30 FPS，倒序和重复帧保留。
- EXO3 的 `frames` 保存去重的组合帧，`animations` 中的共享帧引用已转为从 0 开始；部件/挂点记录中的索引仍从 1 开始，并在字段名标明。
- 每条组合记录依次为：`type, index_1_based, alpha, x, y, scale_x, scale_y, rotation, skew_x, skew_y`；type 1 为图像部件，type 8 为挂点。
- 中英文文本中的 `%$...%$` 和 `%s` 等占位符保留，不计算伤害、等级或其他游戏数值。
- 原版已有的图集舍入边界、缺失引用等问题记录在 `assets_verification.json`，不生成占位图掩盖缺失。最终统计以报告为准。
- 本次新增 11 条源数据动画引用提示：新塔的部分单帧动画引用带 `_0001` 的帧名，图集中对应静态图名不带编号。原始图像、帧名和动画定义均已保留，未自动改名；明细见增量报告。
- 当前安装包已包含参考源码索引中的全部素材，原先缺少的 2 张 DDS 和 39 段 OGG 已随游戏更新同步；后续版本的差异以报告为准。
- 关卡中需要执行逻辑的 Lua、英雄房间动态文本脚本和 LÖVE 着色器保存在原始档案，后续移植对应功能时再改写。本阶段不提供玩法和组合动画渲染器。

后续 Web 导出时，保持兼容渲染器；导出预设需包含通过 FileAccess 动态读取的 `assets/kingdom_rush/**/*.json`（也可在非资源包含过滤器中使用 `*.json`）。
本次资源是全量本地开发素材，未生成整个游戏的 Web 发布包；分包、加载策略和压缩优化属于后续工作。
