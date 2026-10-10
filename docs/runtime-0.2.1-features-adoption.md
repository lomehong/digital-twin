# 官方 DSH 0.2.1-alpha 新能力 × 数字分身套件 采纳分析

> 基线：官方 0.2.1-alpha.1（克隆）/ alpha.2（运行时已升级）vs 0.2.0-rc.2（套件原基线）。
> 分析日期：2026-10-10。方法：全仓 defineTool 扫描（66 工具）+ 包清单能力地图 + 与套件使用面对照。

## 一、官方新能力全景（套件未用部分）

### 高价值（与分身场景强匹配）

| 能力 | 官方包 | 是什么 | 分身场景 |
|---|---|---|---|
| **跨会话历史查询** | session-query（session_search/event_search/trace/SQL） | 对全部会话历史的搜索与结构化查询 | **心智深度分析的证据链增强**：推导议程时直接检索主人全部会话历史，不再只看 timeline tail；也解决「跨会话上下文断裂」 |
| **浏览器自动化** | browser-use（4 后端：chrome-devtools/playwright/runtime/stagehand）+ web 前端 | 真实浏览器操作（网页读取/表单/点击） | 分身「代主人上网」：查安全公告平台、操作内部系统、截图取证 |
| **GitHub webhook** | webhook + webhook-github | 外部事件推送进会话 | 安全值守：私有仓库安全告警 issue → 自动唤醒分身分诊；开发套件自身的 PR 事件响应 |
| **agent-team（官方原生）** | experimental/tool-agent-team + client-ui | send_message/spawn_teammate/team_task_*/wait_agent + 协作 UI | **与自建 task-board+yuyi 战略重叠**——见「决策点」 |
| **语音输入** | experimental/voice-input-bundle + speech-to-text（sensevoice） | 语音转文字输入会话 | 主人移动/驾驶场景语音下指令（配 IM 升级=完全移动化） |
| **文档处理** | document/office-to-pdf + libreoffice-kit 0.1.3 | office 文档读取与 PDF 转换 | 分身读取会议纪要文档、安全报告（docx→可分析文本） |
| **自动审查** | experimental/auto-review | 代码/产出自动审查 | 套件开发时的自审（分身开发分身） |

### 中价值（特定场景可用）

| 能力 | 包 | 场景 |
|---|---|---|
| deliverables 产出物管理 | deliverables/tool-present（已用 present）| 分身工作结果的正式交付与留档 |
| MCP 客户端/资源 | mcp/mcp-client + mcp-resources | 已接 docseal 实例；可扩展更多 MCP 服务（内网系统）|
| SSH 远程 | ssh/fs-ssh | 安全设备/服务器的远程巡检自动化 |
| computer-use | computer-use/cua-driver | 屏幕级操作（无 API 的遗留安全系统）|
| LSP | lsp/tool-lsp | 套件开发的代码智能 |
| spill 上下文溢出 | spill + spill-policy | 超长会话的上下文管理（mind 长会话可用）|
| identity/guard | identity + guard | 分身身份与守卫的官方原语（对照自建 dsh-twin 守卫）|

### 平台机制演进（影响开发方式）

| 机制 | 内容 | 对套件 |
|---|---|---|
| 宪章 §0 落地 | 可选依赖预设行退役 → 各插件 apply 全模式注册（agent/status 生命周期） | dsh-memory v0.3.0 已示范；**dsh-mind 0.10.38 已跟进**（mind 工具全模式挂载）；dsh-task-board/yuyi 的工具挂载方式待对齐 |
| plugin-manager 运行时解析刷新 | 安装/禁用后 runtime package resolution 自动 refresh | 安装体验或可免重启（待实测） |
| HMR 强化 | manifest 刷新/CommonJS 请求刷新 | 开发态收益 |
| profile-resolution 世代化 | Resolution 类化 + successor 计算 | 安装布局语义不变（已验证兼容）|
| schedule bundle 退役 | Web 组合直接挂 Schedule | 我们的 schedule_create 直接可用 ✓ |

## 二、决策点（需要主人裁决）

### 决策 1：agent-team（官方原生）vs 自建 task-board+yuyi

官方 0.2.1 起原生提供 send_message/spawn_teammate/team_task_*/wait_agent + 协作 UI——
功能面与我们的 task-board（审批治理）+ yuyi（跨 agent 通信）高度重叠。

- **自建优势**：IM 审批闭环（企微直达）、L0-L3 治理分级、中国本地化（企微/御驿）、已验证生产运行
- **官方优势**：随运行时演进零维护、协作 UI 原生、与其他官方能力（subagent/workflow）原生集成
- **建议**：短期保持自建（生产已验证），中期观察官方 agent-team 成熟度；两者不互斥
  （官方 team 工具已在 preset 里 disabled 状态挂载，需要时启用即可）

### 决策 2：第一批采纳清单（我的建议排序）

1. **session-query 进心智会话**（成本最低/收益最高）——深度分析的证据链直接增强；
   接入方式：digital-twin 预设 plugins 加 session-query 行（或按宪章 §0 由查询服务全模式）
2. **avatar-tools 会议 → 议程推导**（已就绪待验证）——token 修复后首个真实分析拍验证
3. **webhook-github**（安全值守场景）——需要 GitHub 仓库的 webhook 配置，建议排期
4. **voice-input**（移动场景）——依赖浏览器/客户端支持，排期观察
5. browser-use/computer-use（代操作）——安全团队视角需评估风险（自动化操作双重边界），
   建议放最后并单独做风险评估

## 三、已确认的兼容性结论（上轮分析仍有效）

- rc.2 → 0.2.1-alpha.x 在套件全部集成面（userQuestions/llm/session/web/shell）源码零变更
- 运行时已在 0.2.1-alpha.2 实测运行正常（今日冒烟通过）
- 宪章 §0 全模式注册模式已在 dsh-memory 0.3.0 / dsh-mind 0.10.38 两处实测
