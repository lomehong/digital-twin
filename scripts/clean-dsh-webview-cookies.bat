@echo off
setlocal EnableExtensions
rem 清理 dsh-desktop WebView2 的 cookie 罐子（dsh-auth-* 会话 cookie 每次启动新增一个、
rem 22 天过期、从不清理；累积到 ~16KB 后请求头超过 Node 默认 maxHeaderSize，
rem 服务端回 HTTP 431，表现为 "Failed to load plugins / bundle script failed to load"
rem 或整页 "HTTP ERROR 431"）。必须在 dsh-desktop 完全退出后运行。
rem 详见 docs/dsh-core-browser-auth-cookie-431.md

set "COOKIE_DIR=%LOCALAPPDATA%\com.dshextra.dsh-desktop\EBWebView\Default\Network"

tasklist /FI "IMAGENAME eq dsh-desktop.exe" 2>nul | find /I "dsh-desktop.exe" >nul
if not errorlevel 1 (
    echo [错误] dsh-desktop 正在运行，请先完全退出后再运行本脚本。
    exit /b 1
)

if not exist "%COOKIE_DIR%\Cookies" (
    echo [跳过] 未找到 cookie 文件：%COOKIE_DIR%\Cookies
    exit /b 0
)

del /F /Q "%COOKIE_DIR%\Cookies" >nul 2>&1
del /F /Q "%COOKIE_DIR%\Cookies-journal" >nul 2>&1
echo [完成] 已清空 dsh-desktop webview 的 cookie 罐子，下次启动将重新签发单个会话 cookie。
exit /b 0
