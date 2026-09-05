# 数字分身套件宪章（Suite Charter）

> 状态：生效中（v1.0，2026-09-05）
> 适用范围：`digital-twin` 工作区内的全部 dsh 插件（见 §2 成员清单）
> 本文档是套件的**组织法**：新增插件、修改跨插件行为、评审疑似耦合时，以本文为准。
> 配套文档：`docs/task-board-decisions.md`（任务看板专项决策）。

---

## §0 概念模型（我们共同实现的东西）

**一个 dsh 实例 = 一个数字分身。**

- 主任（owner）通过对话、IM 渠道、任务看板安排任务；**分身是唯一执行主体**。
- 分身的配套资产是**实例级全局**的，跨所有会话与渠道共享：人设（四卡：身份/策略/样例/状态）、记忆（共享记忆库）、知识（种子 + 技能）、任务（看板）。
- 会话只是分身的多个"对话窗口"：主人与访客看到的是同一人格的不同隐私投影，不存在按会话分裂的人格。
- 任务分三层，职责互斥：
  | 层级 | 载体 | 回答的问题 |
  |---|---|---|
  | 全局层 | 任务看板（dsh-task-board） | 分身有哪些任务、进展如何（主任视角） |
  | 会话层 | harness tool-todo/goal/jobs | 这个会话里这一步怎么干（执行脚手架，随会话生灭） |
  | 协同层 | 御驿任务链（dsh-yuyi 任务记忆） | 哪些活委派给了哪个远端协作者、干到哪了（跨 Agent 明细） |
- 治理：分身对外行动受委托账本 L0-L3 约束；主任的批准/否决回流分身学习循环。
- 协同位阶：御驿体系内本分身居于 avatar 主理位，worker/coder 是跨设备协作者。

**组织形态**：套件是**插件联邦**——各成员共同实现上述模型，但彼此独立成活（§1）。

---

## §1 联邦原则（宪法四条）

**原则一（加载独立）**：套件插件之间不得存在加载期依赖。禁止对其他套件包的顶层 import 与硬 `inject` 声明。对宿主（`@deepseek-ai/dsh-*`）服务的注入不受此限——那是平台，不是邻居。

**原则二（运行独立 + 显式降级）**：每个插件的**核心功能**必须在任何兄弟插件全部缺席时完整可用。兄弟插件提供的**增强能力**缺席时，必须**显式降级**：UI 标注"未安装"、日志说明、能力收窄——不得抛错阻断核心路径，也不得静默假装能力存在。

**原则三（数据自治）**：插件只把数据写进自己的目录（`$DSH_HOME/<插件id>/`），不写进别的插件的目录或命名空间，不假定兄弟插件的存储格式。跨插件数据引用只能通过服务接口或模型工具约定。

**原则四（安装独立）**：套件安装器（`install-all.bat`）只是便利，不是任何插件工作的前提。每个插件必须可以单独 `dsh plugin --profile <name> add` 后独立发挥其声明的能力。

**跨插件协作的唯一合法形态**：**可选增强**——消费方经 cordis 惰性解析（`ctx.get`）或同源 HTTP 探测兄弟能力；在场则增强，缺席则按预定义降级路径工作。允许的两种签名：
1. 服务惰性解析：`ctx.get('<sibling-service>')` 返回 `undefined` ⇒ 走降级分支（参考：dsh-task-board 对 dsh-ledger 的懒解析、dsh-twin 对 im-channel 的能力探测）。
2. 预设/能力条件装配：检测到兄弟包已安装才追加配置行（参考：dsh-twin 物化预设时对 tool-memory/tool-yuyi/tool-computer 的探测追加——"装了才有行，没装预设依然可用"）。

---

## §2 成员清单与依赖矩阵

> 矩阵列：**提供**（cordis 服务/钩子）、**宿主消费**（允许且不计入耦合）、**套件增强**（可选消费方向）、**单独可用性**（原则二的声明）。
> "可选增强"必须写明**缺席时的降级行为**；写不出来的即视为违规待整改。

| 插件 | 提供 | 宿主消费 | 套件增强（缺席降级） | 单独可用性 |
|---|---|---|---|---|
| **dsh-twin**（分身核心） | `dsh-twin`（noteActor / seedMemory / enqueueLearning 等） | agentPresets、systemPrompt、settings、sessions、webServer、timer | dsh-memory（知识种子/记忆整合）→ 缺席则种子不落库；dsh-ledger（主动汇报闸）→ 缺席则跳过闸门；im-channel（转人工/主动投递）→ 缺席则报错文案+能力收窄；dsh-actors / dsh-regression（关系档案/影子数据）→ HTTP 探测，缺席则卡片空态 | ✅ 人格注入与管理 UI 完整；增强项按上降级 |
| **dsh-memory**（共享记忆） | `dsh-memory`（早加载，见 §4 注） | webServer（可选） | im-channel（渠道身份挂载）→ 缺席则预设工具行以 master 视角工作；dsh-actors（别名归一）→ 规划中，缺席则按原始 userId 过滤 | ✅ |
| **dsh-task-board**（任务看板） | web 路由 + 客户端看板 | webServer、session APIs、agentPresets | dsh-ledger（L0-L3 治理裁决）→ **现状：缺席即拒绝执行（违宪，见 §5-01，整改中）**；目标态：内嵌最小本地策略的"无治理模式" | ⚠️ 整改中 |
| **dsh-yuyi**（御驿通信） | `yuyi` + `yuyi_*` 工具 | agents、settings | 无套件依赖 | ✅（套件零耦合标杆） |
| **dsh-actors**（实体注册表） | `dsh-actors` | webServer（可选） | dsh-memory（关系档案聚合）→ 缺席则仅注册表视图 | ✅ |
| **dsh-ledger**（委托账本） | `dsh-ledger`；`tools/pre-execute` 治理钩子 | webServer | dsh-twin（否决回流学习）→ 可选 | ✅ |
| **dsh-regression**（回归/影子） | `dsh-regression` | webServer | — | ✅（HostRunner 待接入） |
| **dsh-computer**（电脑操作） | `computer` | settings | — | ✅ |
| **dsh-redact**（出站脱敏） | `redact`（llm/stream 钩子）；规划：可选提供 `masking` | settings、llm | — | ✅ |
| **im-channel**（IM 渠道，dsh-im-bot） | `im-channel`（pushToUser / botsStatus / reload） | agents、agentPresets、approval/question、workspaceRegistry | dsh-memory（共享记忆挂载）→ 缺席则渠道会话按各自隔离；dsh-twin.noteActor（身份标注）→ 可选；`masking`（出站脱敏）→ 缺席需**显式标注**（现状静默，见 §5-04） | ✅ |
| **ui-settings-im**（IM 设置界面） | settings.plugins.tab + shell.overlay | runtime、locale、slots | — | ✅ |

---

## §3 合规细则

### 3.1 边界（原则一、四的落地）

- 套件内**禁止**：`import ... from '@dsh-extra/*'`（构建期值导入）；cordis `inject` 数组出现其他套件插件的服务名；把兄弟包写进自己的 `peerDependencies` 的硬依赖位置（可选增强用文档声明，不用包约束表达）。
- 允许：`ctx.get('<service>')` 惰性解析；同源 HTTP 探测；预设行条件装配；约定式事件（如 ledger 的 `tools/pre-execute` 钩子——钩子是账本的本职治理面，缺席不影响他人）。
- 类型共享：跨插件**只允许类型级参考**（复制或 `import type`，构建期擦除），不得共享运行时值；契约以文档 + 测试固定。

### 3.2 降级（原则二的落地）

显式降级三要素：
1. **可发现**：用户能在 UI 上看到"某增强未安装"（空态卡片、状态徽标、日志 WARN），而不是报错堆栈或无声缺失；
2. **安全收敛**：降级后的行为必须是**无增强的基础能力**，且默认收敛到更保守的一侧（治理类增强缺席时不得扩大权限面）；
3. **可恢复**：兄弟插件后装/重载后，增强能力应在下一次探测/轮询时自动恢复，无需重启或手工干预。

### 3.3 数据自治（原则三的落地）

- 每个插件的数据目录：`$DSH_HOME/<插件id>/`；文件原子写（tmp + rename，0600）。
- **禁止**把数据写进兄弟插件的目录（反例登记：dsh-memory 曾把记忆库放在 `~/.dsh/im-channel/credentials/` 下，见 §5-02）。
- 实例级 vs 机器级：默认**实例级**（`DSH_HOME` 相对）。只有天然跨实例边界的 seam（如御驿 `~/.yuyi`——与 opencode/omp 等共享协议状态）允许机器级，且必须在 README 标注理由与影响。

### 3.4 身份自治

- 每个插件自持身份基线：渠道类插件用渠道 userId，web/预设类用 `'master'` 语义，不假定兄弟插件提供身份服务。
- dsh-actors 是**可选身份增强**（实体归一/别名解析/角色锚定）：在场时各方顺带注册与归一；缺席时各方按基线身份独立工作，能力不受损。不得为身份归一引入对 actors 的硬依赖。

### 3.5 治理自治

- 委托账本（L0-L3）是**可选治理层**：在场时按账本裁决；缺席时插件必须按预定义的本地策略收敛（保守侧），并将"治理降级"显式告知用户。治理缺席**不得**成为核心功能不可用的理由（见 §5-01）。

---

## §4 既有先例（合规范本）

- **dsh-twin 条件预设装配**：物化时探测兄弟工具包，"装了才有行，没装预设依然可用"——可选增强的标准写法。
- **dsh-twin 转人工**：im-channel 缺席时报结构化错误文案并收窄能力，不阻断会话——显式降级的标准写法。
- **dsh-yuyi**：套件内零依赖，只面向宿主服务编程——加载独立的标杆。
- **dsh-memory 早加载**：无硬注入、声明 `provide` 后即刻可用——被增强方（im-channel）以"晚注册重试"对接——服务型插件的挂载范本。
- **看板↔账本契约**：两个函数（`check` / `fillResult`）+ 惰性 `ctx.get`——除 fail-closed 策略待改（§5-01）外，接口形态是跨插件契约的推荐宽度。

---

## §5 违规登记册（活页：发现即登记，整改后销账）

| # | 状态 | 描述 | 整改方向 |
|---|---|---|---|
| 01 | ✅ 已销账（2026-09-05） | dsh-task-board 在 dsh-ledger 缺席时 fail-closed 拒绝执行任务（核心功能不可用，违反原则二/3.5） | 已实现**本地降级策略**（governance.ts `adjudicateLocal`）：L0/L1 放行标注「无账本治理」、L2 放行 + 尽力经 im-channel 通知主任（注入式 notifier，缺席跳过）、L3 拒绝且任务保留待办列；`state().governance.mode` 驱动客户端治理徽标（✓ 治理就绪 / ⚠ 本地降级）；账本在场行为与原版完全一致。测试 36/36 |
| 02 | ✅ 已销账（2026-09-05） | dsh-memory 存储位于 `~/.dsh/im-channel/credentials/`——写在兄弟插件目录下（违反原则三）且无视 `DSH_HOME`（多实例静默共享） | 存储迁至 `$DSH_HOME/dsh-memory/shared-memory.json`（归档同迁）；首次读取自动从旧路径迁移，旧文件保留作备份。已验证迁移链路 |
| 03 | ✅ 已销账（2026-09-05） | im-channel 消费的 `masking` 服务全工作区无提供者，出站脱敏静默空转（违反原则二的"显式"要求） | dsh-redact `provide('masking')`（`maskTextSync`，会话键 `im-channel-out` 保证占位符跨消息一致，命中计入统计）；im-channel 首次缺失时 WARN 一次（显式降级） |
| 04 | ✅ 已销账（2026-09-05） | dsh-twin 仪表盘/关系档案聚合兄弟插件 HTTP 端点，缺席时的降级表现未逐一保证 | 仪表盘登记缺席数据源：对应卡片显示「— / 提供方插件未安装」灰态，全部缺席且无待办时不再显示"一切正常"空态 |
| 05 | 🟡 登记 | im-channel `bindings.json` 与渠道凭证位于机器级 `~/.dsh/im-channel/`（跨实例共享；历史路径，暂容忍） | 评估迁移至 `$DSH_HOME`，与 02 同批处理（02 已完成，05 待排期） |
| 06 | 🟡 登记 | 御驿状态位于机器级 `~/.yuyi`（跨框架 seam，协议使然） | 属 §3.3 允许的例外，README 已标注理由；维持 |

> 登记册由套件维护者更新；销账需在对应插件仓库留有整改提交并在本表标注结果。
> 补充整改记录（2026-09-05，随 01-04 同批）：im-channel 补声明缺失的 devDep `@deepseek-ai/dsh-util-values`（修复 wecom-mcp-registry 构建错误）。

---

## §6 准入与检查

**新插件准入清单**（PR 评审逐项过）：
- [ ] 未 import 任何 `@dsh-extra/*`（构建期）；cordis `inject` 不含套件服务名
- [ ] 数据目录为 `$DSH_HOME/<插件id>/`，原子写；如需机器级路径，已注明例外理由
- [ ] 核心功能在兄弟全缺席时可用；每项增强缺席有显式降级（UI + 日志）
- [ ] 本表 §2 依赖矩阵已更新（提供/宿主消费/增强/单独可用性）
- [ ] README 含"单独安装"一节：最小安装、单独使用方式、降级行为

**边界检查（可脚本化）**：
```sh
# 构建产物/源码中不得出现对套件包的值导入：
grep -rn "from '@dsh-extra/" <plugin>/src --include="*.ts" --include="*.tsx" \
  | grep -v "import type"   # import type 允许（构建期擦除）
# cordis inject 不得声明套件服务名：
grep -rn "inject = \[" <plugin>/src | grep -E "dsh-(memory|twin|ledger|actors|regression|task-board|yuyi|computer|redact|im-channel)"
```

**例外流程**：确需超出可选增强的深度协作时，须在本宪章 §5 登记例外 + 双方 README 声明 + 给出缺席降级路径，经套件维护者同意后方可实施；默认答复为"改为可选增强"。

---

## §7 修订记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1.0 | 2026-09-05 | 首次成文：概念模型、联邦四原则、依赖矩阵、合规细则、范本、违规登记册、准入检查 |
