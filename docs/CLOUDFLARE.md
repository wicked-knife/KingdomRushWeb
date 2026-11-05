# Cloudflare 试玩发布

使用已有、通过隔离 PCK 检查的 `build/web` 导出，不需要为上传重复导出游戏。

```powershell
python tools/prepare_cloudflare.py
node tools/verify_cloudflare.mjs
npx wrangler pages deploy build/cloudflare --project-name kingdom-rush-web --branch main
node tools/verify_cloudflare.mjs https://kingdom-rush-web.pages.dev
```

首次发布需要创建 Pages 项目 `kingdom-rush-web`（生产分支 `main`）。登录可使用最小范围：

```powershell
npx wrangler login --scopes account:read user:read pages:write
```

Web 导出会先生成原始整包（仅保存在 `build/web-source`），再按内容哈希去重，生成菜单启动包和地图、英雄大厅、关卡、战斗英雄资源包。原资源路径与资源内容保持不变；共享资源按使用者分组，进入早期关卡不会下载只供后期关卡使用的图集。`build/web/pack_report.json` 记录实际大小、首次／增量下载量和资源逐路径校验结果。

Cloudflare 静态文件上限为 25 MiB。延后下载的 `packs/<SHA-256>.pck` 均不超过 24 MiB，由 Pages 静态服务提供并长期缓存。上传准备脚本只将较大的启动 PCK 和 WASM 切成 24 MiB 资源，由 `_worker.js` 按原文件地址逐块流式返回；只有 `/index.pck` 和 `/index.wasm` 请求进入函数。入口与原文件地址每次重新验证。准备脚本核对启动包、索引和全部延后包的哈希，重新生成上传目录，避免旧资源残留。

菜单仅下载启动包和引擎；打开地图、英雄大厅、进入关卡时下载相应资源。战斗初始化完成三秒后后台预下载下一关；前台加载优先。下载成功并通过大小／SHA-256 校验后才写入可复用缓存，预下载不会挂载或解码纹理。浏览器禁用持久化时，本次会话仍可运行，但重新打开可能需要再次下载。

本地验证命令：

```powershell
python -m unittest discover -s tests -p test_web_packs.py -v
python tools/check_content_downloads.py
python tools/web_bootstrap.py export --check-pack
python tools/check_web_packs_native.py
python tools/package_level01.py
python tools/prepare_cloudflare.py
node tools/verify_cloudflare.mjs
python tools/verify_web_packs_delivery.py
```

原生窗口检查在隔离工程中使用真实 Web PCK 和本地 HTTP 下载，截图及报告位于 `output/web_packs_native`。完整资源并集由 Godot headless 检查。部署后可用 HTTP 检查入口、WASM 类型、全部 PCK 的 SHA-256 和缓存头；浏览器中的游戏功能、持久化和兼容性由用户手动验收。
