# 分身心智·宿主常驻部署指南

> 设计依据：`docs/mind-runtime-design.md` §12（生命周期与常驻保证）。
> 原则：心智寄生于宿主进程——**宿主在线率 = 分身在线率**。本指南覆盖三种部署形态
> 与告警配置；headlong 同款问题的解法（systemd + Restart + 死亡/静默告警）一并对照。

---

## 一、本机常驻（Windows，最简单）

让 `dsh web` 随系统启动、且不被睡眠打断：

### 1. 计划任务（开机自启 + 崩溃重启）

管理员 PowerShell：

```powershell
$script = @'
@echo off
cd /d C:\Users\hz0704027\AppData\Local\dsh-desktop-app-data\node
dsh web >> "%USERPROFILE%\.dsh\mind-web.log" 2>&1
'@
$script | Set-Content 'C:\Users\hz0704027\dsh-web-task.bat' -Encoding ASCII
schtasks /Create /TN "dsh-web-mind" /TR "C:\Users\hz0704027\dsh-web-task.bat" /SC ONSTART /RU SYSTEM /RL HIGHEST /F
```

### 2. 禁止睡眠（心智要 7×24 就不能睡）

```powershell
powercfg /Change standby-timeout-ac 0
powercfg /Change hibernate-timeout-ac 0
```

（笔记本用电池时酌情保留睡眠——分身会随宿主下线，醒来后错过 due 只补一次。）

---

## 二、专用盒子（推荐，7×24）

家里 NAS / 小主机跑 `dsh web`，桌面/IM 全是终端。headlong 的 systemd 模式对照：

### systemd 单元（Linux 盒子示例）

```ini
# /etc/systemd/system/dsh-web.service
[Unit]
Description=DeepSeek Harness (dsh web)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=dsh
WorkingDirectory=/home/dsh
ExecStart=/home/dsh/.local/bin/dsh web
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### 告警（心智断供必须有人知道）

- **死亡告警**：`systemd` 自带 `OnFailure=` 通知（或 cron 邮件）——进程退出即告警
- **静默告警**：`timeline.jsonl` 超过 `2×(静音时段+退避上限)` 无写入 → 告警
  （一行 cron 检查 mtime 即可；headlong 的 `silence@.timer` 同款思路）
- **spend 告警**：`run/state.json` 的 `spend.usedUsd` 触顶事件写时间线，可转发

---

## 三、云端 VPS

同专用盒子；额外建议：`dsh web` 绑定 127.0.0.1 + 反向代理加认证（LESSONS #11：
插件自有 HTTP 路由不在认证围栏内，公网暴露需自己在反代层加鉴权）。

---

## 四、可用性对照表

| 故障 | 影响 | 恢复 |
|---|---|---|
| 宿主进程崩溃 | 分身下线 | systemd `Restart=always` 10s 拉起；时间线/状态落盘无损 |
| 机器重启 | 分身下线 | 计划任务/systemd 开机自启；首启播种 30s 后第一醒 |
| 睡眠 | 分身暂停 | 醒来错过 due 只补一次；静音时段照常 |
| 网络断 | IM/投递失败 | 时间线留痕；恢复后下拍重试（不吞单） |
