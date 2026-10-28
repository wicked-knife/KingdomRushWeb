# Dove 素材与源数据

基准为 [复刻指南](GODOT_WEB_REMAKE_GUIDE.md) 所列当前最新源码，机器配置在 `data/campaign_content.json.source`。源码 `D:/projects/KingdomRushDove` 提供 Lua、布局、动画、声音索引和翻译；本机安装 `D:/王国保卫战Dove版/KingdomRushDove` 提供未跟踪的 DDS、OGG、字体等媒体。安装目录始终只读。

## 同步与验证

```powershell
python tools/sync_dove_assets.py
python tools/import_dove_assets.py --verify-only --check-source
```

同步器验证源码 HEAD 与目录一致且工作区干净，将 Git 当前元数据放入忽略的 `output/dove_assets_<commit>`，补充安装目录的媒体，再运行统一转换器。已安装媒体通过只读硬链接暂存；覆盖源元数据前先解除已有链接，不会写入安装文件。删除不再受源清单管理的生成文件仅限受管 raw／assets 目录，不删除用户数据。

原始快照保存在 `source_assets/kingdom_rush_dove`，运行资源在 `assets/kingdom_rush`，清单与完整性信息在 `reports/assets_manifest.json`、`assets_verification.json`。关卡／地图／英雄房间另生成裁剪后的图集与 manifest，发布仅收集其依赖。不要把整个本地素材库打入 Web 包。

空 Vorbis 音频在运行资源中转换为同采样率、同声道的 10 ms 静音，原始快照保持原样，清单记录 `empty_ogg_to_silence_v1` 与双方哈希；可用 `python tools/import_dove_assets.py --repair-empty-audio` 专门修复。Godot 编辑器不应加载原始零时长 OGG。

## 访问与坐标

`DoveAssetCatalog` 提供 `get_frame(group,name)`、`get_animation(name)`、`get_exoskeleton(name)`、`get_sound(name)` 与 `get_static(name)`。帧返回纹理、实际 region、source_region、logical_size、original_size、trim 和 ref_scale。同名帧可能分属不同组，必须携带分组。

裁切区域按高清 DDS 实际尺寸与源声明尺寸之比转换；逻辑尺寸不变。显示要恢复原画布与 trim，不能将裁切纹理大小直接用作游戏尺寸。普通动画为 30 FPS，重复帧和倒序保留；EXO 共享帧索引从 0 开始，部件／挂点仍以标注的 1-based 索引保存。

原数据缺失引用、图集边缘舍入和字体映射问题保留于校验报告。开放内容遇到必需媒体或行为缺失必须失败，不生成占位资源掩盖。英雄房间动态技能文本由当前源表达式格式化器求值；未支持的战斗机制不因拥有素材而视作已经实现。

导出后用 `tools/verify_level01_assets.py --level N` 校验源输入哈希、全部动画／音频引用与重打包像素。运行时不依赖安装目录和转换工具。
