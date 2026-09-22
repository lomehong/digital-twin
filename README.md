# digital-twin · 数字分身套件

基于 [DeepSeek Harness（dsh）](https://github.com/lomehong) 的数字分身完整插件套件。
本仓库是**总仓库（meta-repo）**：用 git submodule 组织组成数字分身的 10 个独立插件仓库，
并附带一键安装与全量构建/测试脚本。

## 套件组成

| 仓库 | 提供的包 | 职责 |
|---|---|---|
| [dsh-twin](https://github.com/lomehong/dsh-twin) | `@dsh-extra/dsh-twin` | 分身核心：人格注入、四张卡（身份/策略/样例/状态）、确认式学习闭环、主动触达、运营面板 |
| [dsh-mind](https://github.com/lomehong/dsh-mind) | `@dsh-extra/dsh-mind` | 分身心智运行时：时间线 + 唤醒调度器（自驱地板 5 分钟/机械空醒短路）+ 函数菜单唤醒 run + **心智主页**（存在体/生活流/留言闭环/照护抽屉，设计稿 §3.3） |
| [dsh-memory](https://github.com/lomehong/dsh-memory) | `@dsh-extra/dsh-memory` | 共享记忆：陈述类型/来源归因/授权治理、按需检索、记忆管理界面 |
| [dsh-ledger](https://github.com/lomehong/dsh-ledger) | `@dsh-extra/dsh-ledger` | 委托账本：L0-L3 分级裁决、审批授权（幂等/fail-closed）、结果回填 |
| [dsh-regression](https://github.com/lomehong/dsh-regression) | `@dsh-extra/dsh-regression` | 回归与影子测试：scripted 场景回归、盲测对统计（分辨不出率） |
| [dsh-actors](https://github.com/lomehong/dsh-actors) | `@dsh-extra/dsh-actors` | 实体注册表：master/colleague/customer/stranger/blocked，新建一律 stranger 不推断身份 |
| [dsh-im-bot](https://github.com/lomehong/dsh-im-bot) | `@dsh-extra/im-channel`、`@dsh-extra/dsh-client-ui-settings-im` | IM 渠道（企微/微信/飞书）+ 渠道设置界面 |
| [dsh-redact](https://github.com/lomehong/dsh-redact) | `@dsh-extra/dsh-redact` | 出站脱敏：分身对外产出先脱敏再放行 |
| [dsh-yuyi](https://github.com/lomehong/dsh-yuyi) | `dsh-yuyi` | 御驿通信：跨 Agent 寻址、收件箱、任务协作 |
| [dsh-task-board](https://github.com/lomehong/dsh-task-board) | `@dsh-extra/dsh-task-board` | 任务看板：Host 权威账本、cron 调度、真实分身会话执行、账本裁决闭环 |

生态工具（不在本套件内，各自独立）：[dsh-plugin-manager](https://github.com/lomehong/dsh-plugin-manager)（插件管理与侧载）、[dsh-architect](https://github.com/lomehong/dsh-architect)（架构师预设）、[dsh-remote](https://github.com/lomehong/dsh-remote)（远程访问）。
电脑操作（截图/鼠标/键盘/窗口/剪贴板）由 dsh 官方插件提供，套件自有实现 dsh-computer 已于 2026-09-18 移除（本地若残留 `dsh-computer/` 检出，属历史遗留目录，不参与套件安装）。
全部插件的配置入口统一在 dsh 左侧「插件」管理页的各插件详情页（`plugins.bundle.config`）：有配置的插件提供表单，无配置的提供只读状态速览；分身心智另有会话顶部「心智」Tab 与窗口右下角常驻存在体两个入口。

## 快速开始

**前提**：先装好 [dsh-desktop](https://github.com/lomehong/dsh-desktop)（Tauri 桌面壳，承载 harness 与本套件的宿主进程），Node.js 与 pnpm 在 PATH。本仓库**不包含** dsh-desktop 源码——它单独维护，与本套件独立升级；安装脚本会自动定位桌面版 DSH_HOME（探测 `%LOCALAPPDATA%\dsh-desktop\home` 与旧版 `%LOCALAPPDATA%\dsh-desktop-app-data\home` 两种布局，可被 DSH_HOME 环境变量覆盖）。

### 方式 A：直接安装发布版（推荐，无需克隆源码、无需构建）

各插件仓库均为公开仓库，CI 在每次发版时把可安装 tarball 挂到 GitHub Release：

```bat
git clone https://github.com/lomehong/digital-twin.git   :: 不需要 --recurse-submodules
cd digital-twin
install-all.bat -Release
```

**全量要求（防残缺套件）**：Release 模式会逐个探测 10 个插件仓库的最新 Release，**任一插件缺发布资产即中止**，不改动任何状态（套件少几块比明确失败更糟）。URL 带 `?release=<tag>`，同版本重跑幂等、新版本重跑即更新——**"生产安装"同时就是"生产更新"**。桌面版也可直接用系统托盘的套件安装菜单（等价于本命令）。

依赖直接写 Release tarball 的固定 URL（`/releases/latest/download/<name>-latest.tgz`）。
也可以只装单个插件：

```bat
dsh plugin --profile web add https://github.com/lomehong/dsh-twin/releases/latest/download/dsh-twin-latest.tgz
```

装完重启 dsh 即生效（宿主按包内 `dsh.bundle` 声明自动登记插件层）。
安装器末尾会跑**升级防复发审计**（组合行 name 与 `@deepseek-ai/*` 运行时 import 在解析链上必须可解析）并清掉预设版本戳（下次启动重物化预设行）。

### 方式 B：开发者源码安装（link: 模式）

```bat
git clone --recurse-submodules https://github.com/lomehong/digital-twin.git
cd digital-twin
install-all.bat        :: 一键把 10 个插件仓库（共 11 个包，im-bot 含 2 个）以 link: 模式装进 dsh web profile
```

`install-all.bat` 会自动定位 Node.js 与 DSH_HOME（桌面版优先）、按 package.json
校验每个插件的构建产物、注册 profile bundle 层、修复 pnpm 9 跨盘 link: 的
junction 问题，并移除数字分身预设版本戳以触发下次启动重物化（挂上
tool-memory / tool-yuyi 工具行）。装完重启 dsh 即生效。

## 全量构建与测试

```bat
scripts\build-all.bat   :: 按目录序构建全部插件（tsc + client bundle）
scripts\test-all.bat    :: 跑全部插件测试套件，任一失败即报
```

## 发版流程（维护者纪律）

每个插件仓库独立发版，**发版 = 打 tag，tag = CI 发布**。`scripts\release.bat` 把纪律固化成机械步骤——只允许从 main 发版、工作区必须干净、本地测试必须全绿，任一不满足直接拒绝；通过后自动 bump 版本、提交、打 tag 并推送，tag 推送即触发该仓库的 release CI（typecheck/test/build → 发布包审计 → tarball 挂 GitHub Release）。

```bat
scripts\release.bat dsh-twin patch    :: 也可 minor / major / 具体版本号
```

机制保障：没有 tag 就没有发版（不会误发）；tag 与 package.json 版本不一致时 CI 审计直接拒绝（不会发错版本）；bump、commit、tag、push 由脚本一次完成（不会"推了代码忘推 tag"）。发版完成后回总仓库更新子模块指针（见下节）。

## 子模块日常操作

各插件在各自目录里照常开发（独立仓库，互不影响）。总仓库只记录每个子模块
指向的 commit，需要同步指针时：

```bat
:: 某插件发布新提交后，在总仓库更新指针
cd dsh-twin && git checkout main && git pull && cd ..
git add dsh-twin
git commit -m "chore: dsh-twin 指针更新至 %NEW_SHA%"

:: 全部子模块批量更新
git submodule update --remote
git add -A && git commit -m "chore: 批量更新子模块指针"
```

克隆本仓库后拉齐子模块：

```bat
git submodule update --init --recursive
```

## 设计文档

`docs/` 目录：

| 文件 | 内容 |
|---|---|
| [suite-charter.md](docs/suite-charter.md) | **套件宪章**（成员矩阵、依赖方向、准入自查、红线）——改动前必读 |
| [mind-runtime-design.md](docs/mind-runtime-design.md) | **分身心智运行时设计稿**（v0.6：时间线/唤醒调度/成本护栏/心智主页 UI-UX/生命周期） |
| [reviews/](docs/reviews/) | 心智运行时五角色评审纪要（arch/cost-ux/security/sre/test + 综合） |
| [reports/](docs/reports/) | 套件设计与实现系统分析报告 |
| [task-board-decisions.md](docs/task-board-decisions.md)、`2026-09-11-待审批重复-根因分析.md`、`dsh-core-browser-auth-cookie-431.md` | 决策与事故根因 |
| `digital-twin-design*.html`、`digital-twin-implementation.html`、`digital-twin-briefing.html` | 早期设计与汇报稿（单文件 HTML，浏览器直接打开） |

## 目录约定

- 总仓库只承载 submodule 指针、安装/构建/发版脚本与文档；各插件的代码、CI、Release 都在各自仓库。
- 工作区出现未注册为 submodule 的插件目录（如历史遗留的 `dsh-computer/`）不参与安装与发版，已在 `.gitignore` 中排除。
