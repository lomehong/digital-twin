# dsh 核心缺陷报告：浏览器会话 cookie 无限累积导致 HTTP 431（dsh-desktop 无法启动）

- 报告日期：2026-09-08
- 受影响组件：`@deepseek-ai/dsh-client-connection`（浏览器会话认证，BrowserAuth）
- 受影响版本：core 0.1.2-alpha.5（dsh-desktop 内置 node 运行时），预计所有使用
  `COOKIE_PREFIX = "dsh-auth-"` 的版本均受影响
- 严重程度：高（桌面端累积使用数天后必然无法启动，重启无法恢复且持续恶化）

## 现象（按恶化顺序）

1. dsh-desktop 启动后界面显示 `HARNESS Failed to load plugins ... bundle script
   /plugins/??...&rev=<hash> failed to load`——实际是 combo bundle 的 `<script>`
   请求被服务端以 **HTTP 431 Request Header Fields Too Large** 拒绝（脚本元素
   error 事件被 client.js 的 defaultLoadBundle 统一报为 "failed to load"）。
2. 继续累积后，连 HTML 文档请求本身也 431，webview 整页显示
   "当前无法使用此页面 / HTTP ERROR 431"。
3. 重启 dsh-desktop **无法恢复**：每次启动的 token 换 cookie 流程会再写入一个
   新 cookie，罐子只增不减，问题持续恶化（用户感知为"越改越糟"）。
4. 同一 harness 实例用独立浏览器（独立 cookie 罐子）访问完全正常；curl 无 cookie
   访问也正常——因此极易误判为"webview 缓存问题"或"插件代码问题"。

## 根因

`dsh-client-connection/lib/index.js`（browser-auth 区段）：

- `COOKIE_PREFIX = "dsh-auth-"`，cookie 名 = 前缀 + 每次进程启动随机生成的
  32 字节密钥（base64url，约 43 字符），用于把会话绑定到本次运行（audience）。
- `sessionCookie()` 以 `Max-Age`/`Expires`（约 22 天，`cookieMaxAgeDays`）写入
  **持久 cookie**，`Path=/`，host 为 `127.0.0.1`。
- **cookie 不区分端口**：harness 每次启动使用随机端口，但所有历史 cookie 的
  domain 都是 `127.0.0.1`，浏览器会把全部 cookie 发给每一次请求。
- 签发新 cookie 时**从不清理旧 cookie**（没有对旧名发 `Max-Age=0` 的删除指令，
  名字每次不同也无法覆盖）。
- 每个 cookie 约 230 字节（name 43 + value 173 + 分隔）。约 70 次启动后 cookie
  请求头达到 ~15.8KB，叠加 UA/Referer/sec-fetch 等常规头后超过 Node 默认
  `--max-http-header-size`（16384 字节），node:http 直接回 431。

取证数据（2026-09-08，用户机器）：WebView2 cookie 罐中 `127.0.0.1` 域共
69 个 `dsh-auth-*` cookie，cookie 头合计 15781 字节；清空后全部请求恢复 200。

## 复现步骤

1. 正常使用 dsh-desktop，每天多次重启（每次启动新增 1 个持久 cookie）。
2. 约 60–70 次启动后：combo bundle 请求 431 → "Failed to load plugins"。
3. 再若干次启动后：文档请求 431 → 整页不可用。
4. 用 CDP（`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222`）
   连接 webview，`Network.getAllCookies` 可见数百个 `dsh-auth-*`；
   `Network.clearBrowserCookies` 后立即恢复正常。

## 建议修复（上游）

任选其一或组合：

1. **签发即清理**：Set-Cookie 新会话 cookie 的同时，对已知旧 cookie 名发
   `Max-Age=0` 删除指令。服务端可在凭证存储中记录"上一次签发的 cookie 名"
   （或让客户端在换 cookie 的 POST 中带上当前 cookie 名清单）。
2. **稳定 cookie 名**：cookie 名固定为 `dsh-auth`（audience 绑定改由签名 payload
   内的 authority + secret 校验承担），新签发自然覆盖旧值，罐子恒为 1 个。
3. **缩短生命周期**：`cookieMaxAgeDays` 默认值降到 1 天以内，控制累积上界。
4. **服务端兜底**：harness 创建 http server 时显式设置
   `maxHeaderSize`（如 64KB），把"cookie 过多"从硬失败降级为可容忍状态，
   并在 431 前主动忽略非本运行的 `dsh-auth-*` cookie（解析时只认本次密钥名）。

## 用户侧临时缓解（已实施）

1. 用户级环境变量 `NODE_OPTIONS=--max-http-header-size=65536`
   （4 倍余量，约可再容忍 280 次启动；dsh-desktop 拉起的 node 继承该变量）。
2. 清理脚本 `scripts/clean-dsh-webview-cookies.bat`：dsh-desktop 退出后删除
   `%LOCALAPPDATA%\com.dshextra.dsh-desktop\EBWebView\Default\Network\Cookies`。
3. 运行中清理：带 `--remote-debugging-port=9222` 启动 desktop，CDP 调
   `Network.clearBrowserCookies`。
