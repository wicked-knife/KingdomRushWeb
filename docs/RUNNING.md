# 启动与验证

## Godot 中运行

使用 **Godot 4.7.2 stable** 打开项目根目录的 `project.godot`，按 **F5**。
默认入口为 `scenes/app_root.tscn`，无需手动选择主场景。启动后依次显示加载进度与主菜单。

首页使用 Dove 2.1.0.2 原版 `screen_slots/homeMenu_bg` 背景，通过 `data/original_menu_background.tres` 从已有图集中裁切，复用原版的 17 帧 Logo、中文按钮和音乐。开始与制作人员入口显示暂未开放提示；选项支持即时调节音乐、音效并保存；Esc 关闭弹窗，桌面窗口关闭按钮与退出入口均显示退出确认。
设计尺寸为 1920×1080，默认窗口为 1280×720。其他比例等比缩放并留黑边，保证完整显示菜单与弹窗。

音量保存在 Godot 的 `user://settings.json`。设置损坏时恢复默认值，写入失败时保留本次运行中的调整并提示。自动检查使用单独的临时设置文件，不改动玩家设置。
无显示的 headless 运行不会播放音频；音频检查应使用 Godot 原生渲染窗口。

## 日常验证

依照根目录 `AGENTS.md`，日常验证在 Godot 内完成，浏览器验收由用户手动执行。
以下命令在项目根目录的 PowerShell 中运行：

```powershell
# 设置默认值、持久化、损坏恢复、写入失败、加载缺失资源与重试、图集裁切
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_menu_bootstrap.gd

# 防止零时长 OGG 再次卡住编辑器的音频预览
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/verify_audio_compat.gd

# 原生渲染：主菜单、弹窗、Esc、音量总线和音乐播放；截图保存到 reports/
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1280x720
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1920x1080
& 'D:\godot\Godot_v4.7.2-stable_win64_console.exe' --path . --script tests/menu_visual_smoke.gd --resolution 1024x768
```

现有独立素材预览仍可选择 `scenes/asset_preview.tscn` 后按 F6 运行。

## Web 导出与手动验收

发布目标保持 Compatibility、单线程 Web，不要求 COOP/COEP，不启用 Service Worker。
仅在需要交付或用户准备手动验收时导出：

```powershell
python tools/web_bootstrap.py export
python tools/web_bootstrap.py serve
```

在浏览器打开 `http://127.0.0.1:8060/`，通过 Ctrl+C 停止服务；也可用 `serve --port 8061` 指定其他端口。
不能通过双击 HTML 的 `file://` 方式运行。其他机器可通过 `export --godot <Godot可执行文件路径>` 指定引擎。
需要安装与引擎匹配的 Web 导出模板。

导出目录为 `build/web/`，可整体作为静态站点发布。本地服务器已经设置 WASM、PCK、JS 的 MIME 类型，并关闭本地缓存以方便手动验收。
浏览器首次点击或按键后启用声音。存储受到限制时会提示设置可能无法保留，不影响主菜单使用。

导出由 `data/menu_manifest.json` 控制：只包含启动/首页脚本与场景、原版背景的 AtlasTexture 资源、五张图集、一种中文字体、两段音频和必要 JSON。背景复用现有图集，不增加独立纹理。
`export_presets.cfg` 由工具生成；修改首页依赖时先更新 manifest，再运行 `python tools/web_bootstrap.py preset`。
导出工具会用隔离的 Godot 工程检查 PCK，防止漏文件被开发目录掩盖；实际文件清单写入 `build/web/pack_files.json`。
此检查不会启动浏览器，也不替代用户的 Web 功能验收。
