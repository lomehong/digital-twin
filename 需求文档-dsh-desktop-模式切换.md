# 需求文档：dsh-desktop 托盘菜单「模式切换」——按模式加载不同 dsh 环境

> 文档目的：交由 dsh-desktop 负责方评估可行性与实施方案。文中「已验证/待验证」区分了需求方已确认的事实与留给实施方确认的假设。
>
> 需求提出方联系人语境内约定的术语：**「模式」= 一套可切换的 dsh 运行环境**（含插件集与模式预设），不是 dsh web 会话内的 agent preset（后者是会话级概念，与本需求不同层）。

---

## 1. 背景与目标

当前 dsh-desktop 作为壳包装单个 dsh web 实例（单一 profile），所有插件、预设、全局指令混在同一环境里。用户希望在**不打开设置页手动装卸插件**的前提下，从壳的托盘右键菜单一键切换「默认模式」与「红队模式」：

- **默认模式**：现状环境，干净、零安全向插件，行为与当前版本完全一致；
- **红队模式**：加载 [dsh-redteam-model](https://github.com/SeaOf0/dsh-redteam-model) 合集（9 个安全模式预设 + 17 个运行时插件 + 设置页 Redteam Manager 管理台）的完整环境。

核心价值：两套环境按需加载、互不拖累；红队插件（工具调用拦截、逐轮上下文注入、全局指令文件等宿主级插件）不在默认模式中驻留。

## 2. 名词与事实基础（需求方已验证）

### 2.1 dsh 启动器原生支持按 profile 启动

来源：dsh 包 `lib/bin.js`（需求方已阅读源码并实测 `--help`）：

- `dsh --profile <name>` 启动任意具名 profile；`dsh web` 只是 `--profile web` 的硬编码别名（bin.js L19、L34）；
- 示例（bin.js L35-L41）：`dsh --profile tui --patch ./extra.yml`（自定义 profile 叠加 overlay）、`dsh --profile rescue --from-default-profile web`（**线索：`--from-default-profile web` 可能让具名 profile 以 web 默认组合启动，需实施方验证**）；
- ⚠️ `desktop` profile 名被启动器保留（`rejectElectronProfile`，bin.js L28-L29），模式 profile 不得使用该名；
- web 启动参数：`--host / --no-open / --port`（`--port 0` 由 OS 分配随机端口，地址从 stdout URL 行解析）。

### 2.2 隔离粒度事实

- **预设（agent preset）按 DSH_HOME 共享**：dsh-redteam-model 的 9 个模式预设位于 `<DSH_HOME>/.agent-presets`，同 home 下所有 profile 共享（来源：该项目 README「模式位于当前 DSH_HOME 的全局 .agent-presets，会被该 DSH home 下的 profile 共享」）；
- **插件按 profile 隔离**：安装命令 `dsh plugin --profile <name> add github:SeaOf0/dsh-redteam-model` 只写入该 profile 的依赖声明与 bundle patch（写入前备份、失败恢复）；
- ⚠️ **该合集还会落地全局指令文件**：安装时将随包 `AGENTS.md` 写到 `<DSH_HOME>/AGENTS.md`（仅当文件不存在时），这是 **home 级**文件——若与默认模式共用 home，默认模式的会话也会读到它。这是方案选型的关键变量（见 §4）。

### 2.3 dsh-redteam-model 合集概况

- 版本 v1.1.1，MIT，Node >= 22；peer 依赖 `@deepseek-ai/dsh-settings ^0.1.0-rc.6 || ^0.1.1-rc.0`，最近提交已适配 0.1.2 宿主；
- 内容：9 个模式预设（pentest/code-audit/binary-analysis/attack-defense/av-evasion/incident-response/cloud-security/ctf-solver + redteam 总控）+ 17 个运行时插件（宿主平面治理类为主，工具类挂预设平面）；
- ⚠️ **该合集包含真实攻击样本文件**（webshell 载荷示例、免杀实验室样本、ASPX DLL 等），杀软（如卡巴斯基启发式）会查删其中部分文件。分发/安装流程需考虑：报毒拦截不影响插件源码运行，但若做完整性校验或打包镜像需注意；部署目标机器应有相应软件安装授权。

### 2.4 dsh-desktop 代码现状（需求方已定位，行号为当前版本参考）

| 位置 | 事实 |
|---|---|
| `src-tauri/src/tray.rs` L354 起 | 托盘菜单为声明式 spec：`MenuEntry::Item / Check / Submenu / Sep`，已支持复选项与子菜单 |
| `tray.rs` L362 注释 | 约定：菜单 id 是 `&'static str`，新增项必须**同步修改 spec 与 `on_menu_event` 字符串分发两处** |
| `tray.rs` L845 | `on_menu_event` 按 id 字符串分发 |
| `src-tauri/src/supervisor.rs` L336/L350 | 拉起 `dsh web --no-open --port N`；`--port 0` 随机端口决策逻辑已在 `settings::decide_spawn_port` |
| `supervisor.rs` L366/L420 | 便携版（Launch::Portable）/ 安装版两个 spawn 分支，**改 profile 需两处同改** |
| `supervisor.rs` L393 | 便携版设置 `DSH_HOME` 环境变量（与系统 `~/.dsh` 隔离） |
| `supervisor.rs` L12 注释 | 全新 DSH_HOME 首启需安装 profile 依赖，已为此留超时预算 |
| `supervisor.rs` L653-L663 | 核心版本变化自愈：清空 profile 插件目录并按 `install::install_profile_plugins` 补装 |
| `src-tauri/src/install.rs` L640/L684 | `profile_names()`（home/profiles 下含 package.json 的名单）、`install_profile_plugins(profiles, why)` 已按 profile 粒度工作 |
| `src-tauri/src/settings.rs` | `fixed_port` / `decide_spawn_port` / launcher.json 持久化机制现成 |
| `src-tauri/src/jumplist.rs` | Windows 跳转列表（可作为模式入口的可选扩展位） |
| `src-tauri/src/persona.rs` | 先例：便携模式向导直接向 `<DSH_HOME>` 写 `.agent-presets/...` 与 `profiles/web/cordis.patch.yml`——壳已具备「生成 dsh home 产物」的能力范式 |

## 3. 功能需求（FR）

| # | 需求 | 优先级 |
|---|---|---|
| FR-1 | 托盘右键菜单新增「模式」子菜单，单选项至少含：**默认模式**（现网行为）、**红队模式**（redteam 环境）。菜单结构需可扩展更多模式（数据驱动而非硬编码 if/else 链） | P0 |
| FR-2 | 选中即切换：优雅停止当前 dsh 子进程 → 以目标模式的环境参数重新拉起 → 主窗口/托盘地址与状态随之更新。切换中 UI 需有明确状态反馈（可复用现有启动状态文案机制） | P0 |
| FR-3 | 首次进入红队模式：自动完成环境初始化（创建 profile + 安装 dsh-redteam-model 合集），有进度反馈；失败时明确报错并**保持/回退到原模式**，不得留下半初始化状态（安装命令本身幂等，可直接复用） | P0 |
| FR-4 | 模式选择持久化（launcher.json 或同级机制）；壳重启后按上次选择的环境拉起 | P0 |
| FR-5 | 默认模式零回归：不安装任何新依赖、不改变现有启动参数与行为 | P0 |
| FR-6 | 安装版与便携版两种形态都支持（supervisor 的两个 spawn 分支都要覆盖） | P0 |
| FR-7 | 异常处理：目标模式拉起失败（端口、依赖、bundle 解析错误等）→ 回退上一可用模式并提示；现有孤儿 pid 识别、profile bundle 失联自愈逻辑需在新流程下继续有效 | P0 |
| FR-8 | （可选）Windows 跳转列表同步模式入口；（可选）主窗口设置页提供同等切换入口 | P2 |

## 4. 实现方案：请实施方评估选型

两条候选路径，**核心差异在隔离强度**，请结合 §6 开放问题 Q1 的结论取舍：

### 方案 A：单 DSH_HOME + 多 profile（轻量，推荐先验证）

- 建一个 `redteam` profile（名避开 `desktop`），安装合集到该 profile；托盘切换 = 以 `dsh --profile redteam --no-open --port N` 重启子进程；
- 优点：切换快（依赖已装）、改动集中在 tray/supervisor/settings 三处、安装自愈逻辑天然兼容；
- ⚠️ 已知副作用（§2.2）：同 home 下 **9 个安全预设对所有 profile 可见**（新会话模式选择器会出现安全模式项）；**合集的 AGENTS.md 是 home 级文件，默认模式会话同样会读到**。若 Q1 的答案是「默认模式必须完全无感」，方案 A 不满足，需 B 或对 A 做补救（如初始化红队模式前先放置中性 AGENTS.md 占位阻止合集写入——因安装器只在文件缺失时写入；此补救会改变合集预期行为，需需求方确认）。

### 方案 B：多 DSH_HOME + 实例切换（强隔离）

- 每模式一个 home（如 `Data/home-redteam`），`DSH_HOME` env 按所选模式注入（便携版已有该机制，安装版需扩展）；
- 优点：文件级完全隔离——插件树、npm 缓存、凭据、会话、全局指令全部分家，最符合「红队环境与日常环境零交叉」诉求；
- 代价：新 home 首启要装 profile 依赖（慢，supervisor 已有超时预算先例）；磁盘占用翻倍；切换逻辑改动更大。

### 并行多实例（同开两个 dsh web）

明确列为**非目标**（复杂度高、双 origin 管理、收益低），除非实施方评估后有低成本方案。

## 5. 验收标准（AC）

前置：以红队合集 v1.1.1 + 当前壳内置 dsh 版本为验证基线。

- **AC-1** 托盘右键出现「模式」子菜单，当前模式有选中态标识；
- **AC-2** 切换到红队模式后，逐项验证合集生效：① 设置页出现 Redteam Manager 管理台；② 任一会话可调用 `gates_list` 且返回安全模式门禁 schema；③ pentest 会话可见 `nuclei_scan` 等扫描工具、且 av-evasion/redteam 会话**不可见**（预设平面正确性）；④ 发起任务后出现 `[route-boost] mode=... phase=...` 信封快照；⑤ 新会话模式选择器列出 9 个安全模式；
- **AC-3** 切回默认模式后，AC-2 的五项全部为否，且壳行为与改造前版本无差异；
- **AC-4** 模式选择跨壳重启保持；重启后按上次模式正常拉起；
- **AC-5** 首次进入红队模式的安装流程：有进度显示；断网/安装失败场景下报错清晰、可重试、原模式不受影响；
- **AC-6** 切换过程中：旧子进程被正确终止（无孤儿进程残留，现有 pid 登记机制仍工作）；新实例端口解析与 webview 导航放行正确；
- **AC-7** 安装版与便携版各完整跑通一遍 AC-1~AC-6。

## 6. 开放问题（请实施方评估时与需求方确认）

- **Q1（决定方案选型）**：默认模式需要多强的隔离？① 接受共享 home 的预设可见 + AGENTS.md 泄漏（方案 A 原样）；② 接受预设可见但要求 AGENTS.md 不影响默认会话（方案 A + 中性占位文件）；③ 必须 home 级完全隔离（方案 B）。
- **Q2**：自定义 profile（非 web/tui/headless）如何以 web UI 形态启动？线索 `--from-default-profile web`（bin.js L35），需实测确认完整启动命令形态。
- **Q3**：会话历史/工作区存储是按 profile 隔离还是按 home 共享？（影响切换后「会话还在不在」的用户预期）
- **Q4**：壳内置 dsh 版本与 dsh-redteam-model peer 依赖（`^0.1.0-rc.6 || ^0.1.1-rc.0`，已适配 0.1.2）的兼容性矩阵；壳升级 dsh 核心后红队模式的自愈重装路径是否通畅（`refresh_profile_plugins_if_core_changed` 覆盖面）。
- **Q5**：合集安装来源走 `github:SeaOf0/dsh-redteam-model`（需网络）还是壳内做离线包/镜像？杀软查杀样本文件后合集功能不受影响，但若壳侧有完整性校验需放宽或适配。

## 7. 非目标

- 不修改 dsh 本体与 dsh-redteam-model 合集源码（合集自身的安装/卸载由其自带管理台与 CLI 负责，壳只负责调用与编排）;
- 不做同 host 多实例并行运行;
- 不做会话/数据跨模式迁移;
- 不改变现有单模式（默认）下的任何启动参数与行为。

## 8. 交付物要求

1. **评估结论**：方案选型（A/B/组合）与理由、Q1-Q5 答案、工作量估计；
2. **实施计划**：文件级改动清单（参考 §2.4 定位，含测试计划）；
3. **代码与测试**：含 FR/AC 逐条验证记录；便携版 + 安装版双形态验证；
4. **回滚方案**：模式切换功能异常时，如何一键回到现网行为。
