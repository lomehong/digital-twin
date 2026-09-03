# digital-twin · 数字分身套件

基于 [DeepSeek Harness（dsh）](https://github.com/lomehong) 的数字分身完整插件套件。
本仓库是**总仓库（meta-repo）**：用 git submodule 组织组成数字分身的 9 个独立插件仓库，
并附带一键安装与全量构建/测试脚本。

## 套件组成

| 仓库 | 提供的包 | 职责 |
|---|---|---|
| [dsh-twin](https://github.com/lomehong/dsh-twin) | `@dsh-extra/dsh-twin` | 分身核心：人格注入、四张卡（身份/策略/样例/状态）、确认式学习闭环、主动触达、运营面板 |
| [dsh-memory](https://github.com/lomehong/dsh-memory) | `@dsh-extra/dsh-memory` | 共享记忆：陈述类型/来源归因/授权治理、按需检索、记忆管理界面 |
| [dsh-ledger](https://github.com/lomehong/dsh-ledger) | `@dsh-extra/dsh-ledger` | 委托账本：L0-L3 分级裁决、审批授权（幂等/fail-closed）、结果回填 |
| [dsh-regression](https://github.com/lomehong/dsh-regression) | `@dsh-extra/dsh-regression` | 回归与影子测试：scripted 场景回归、盲测对统计（分辨不出率） |
| [dsh-actors](https://github.com/lomehong/dsh-actors) | `@dsh-extra/dsh-actors` | 实体注册表：master/colleague/customer/stranger/blocked，新建一律 stranger 不推断身份 |
| [dsh-im-bot](https://github.com/lomehong/dsh-im-bot) | `@dsh-extra/im-channel`、`@dsh-extra/dsh-client-ui-settings-im` | IM 渠道（企微/微信/飞书）+ 渠道设置界面 |
| [dsh-computer](https://github.com/lomehong/dsh-computer) | `@dsh-extra/dsh-computer` | 电脑操作：截图/鼠标/键盘/窗口/剪贴板 |
| [dsh-redact](https://github.com/lomehong/dsh-redact) | `@dsh-extra/dsh-redact` | 出站脱敏：分身对外产出先脱敏再放行 |
| [dsh-yuyi](https://github.com/lomehong/dsh-yuyi) | `dsh-yuyi` | 御驿通信：跨 Agent 寻址、收件箱、任务协作 |

生态工具（不在本套件内，各自独立）：[dsh-plugin-manager](https://github.com/lomehong/dsh-plugin-manager)（插件管理与侧载）、[dsh-remote](https://github.com/lomehong/dsh-remote)（远程访问）。

## 快速开始

前提：已安装 dsh（桌面版或 `npm i -g` 的 dsh CLI）与 Node.js。

```bat
git clone --recurse-submodules https://github.com/lomehong/digital-twin.git
cd digital-twin
install-all.bat        :: 一键把 9 个插件以 link: 模式装进 dsh web profile
```

`install-all.bat` 会自动定位 Node.js 与 DSH_HOME（桌面版优先）、按 package.json
校验每个插件的构建产物、注册 profile bundle 层、修复 pnpm 9 跨盘 link: 的
junction 问题，并移除数字分身预设版本戳以触发下次启动重物化（挂上
tool-memory / tool-yuyi / tool-computer 工具行）。装完重启 dsh 即生效。

## 全量构建与测试

```bat
scripts\build-all.bat   :: 按目录序构建全部插件（tsc + client bundle）
scripts\test-all.bat    :: 跑全部插件测试套件，任一失败即报
```

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

`docs/` 目录收录数字分身的设计文档（v0.2 设计、v2 三主线、实施方案、领导简报），
均为单文件 HTML，浏览器直接打开。
