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
- 知识定位：**知识 = 种子化的权威事实记忆 + harness 技能**，不另建独立知识库。知识种子
  （dsh-twin 向导）以 `statementType: 事实`、`source.origin: seed` 落入 dsh-memory；
  领域技能经 harness 技能体系（skill-filesystem / tool-skill）挂载。检索质量成为瓶颈时，
  再评估独立知识存储（当前决策：不建）。
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
| **dsh-twin**（分身核心） | `dsh-twin`（noteActor / seedMemory / enqueueLearning 等） | agentPresets、systemPrompt、settings、sessions、webServer、timer | dsh-memory（知识种子/记忆整合）→ 缺席则种子不落库；dsh-ledger（主动汇报闸）→ 缺席则跳过闸门；im-channel（转人工/主动投递）→ 缺席则报错文案+能力收窄；dsh-task-board（activity() 活动视图，活动区段唯一数据源）→ 缺席则活动区段整体降级为空；dsh-actors / dsh-regression（关系档案/影子数据）→ HTTP 探测，缺席则卡片空态 | ✅ 人格注入与管理 UI 完整；增强项按上降级 |
| **dsh-memory**（共享记忆） | `dsh-memory`（早加载，见 §4 注） | webServer（可选） | im-channel（渠道身份挂载）→ 缺席则预设工具行以 master 视角工作；dsh-actors（别名归一）→ 规划中，缺席则按原始 userId 过滤 | ✅ |
| **dsh-task-board**（任务看板 = 唯一活动权威） | web 路由 + 客户端看板 + 模型工具（tools 入口：`task_report` 上报 / `task_delegate` 对话内下单）+ `dsh-task-board` 服务（`state()` 状态 / `activity()` 活动视图，tick 每 15s 刷新） | webServer、session APIs、agentPresets、typertGateway | dsh-ledger（L0-L3 治理裁决）→ 缺席走本地降级（L0/L1 放行标注、L2 拦截、L3 拒绝，§5-01 已销账）；dsh-memory（任务结果沉淀为「已验证结果」记忆）→ 缺席则仅看板+账本留痕；im-channel（L2 降级通知主任）→ 缺席跳过通知 | ✅ |
| **dsh-yuyi**（御驿通信） | `yuyi` + `yuyi_*` 工具 | agents、settings | 无套件依赖 | ✅（套件零耦合标杆） |
| **dsh-actors**（实体注册表） | `dsh-actors` | webServer（可选） | dsh-memory（关系档案聚合）→ 缺席则仅注册表视图 | ✅ |
| **dsh-ledger**（委托账本） | `dsh-ledger`；`tools/pre-execute` 治理钩子 | webServer | dsh-twin（否决回流学习）→ 可选 | ✅ |
| **dsh-regression**（回归/影子） | `dsh-regression` | webServer | — | ✅（HostRunner 待接入） |
| **dsh-computer**（电脑操作） | `computer` | settings | — | ✅ |
| **dsh-redact**（出站脱敏） | `redact`（llm/stream 钩子）+ `masking`（已提供，im-channel 出站脱敏消费） | settings、llm | — | ✅ |
| **im-channel**（IM 渠道，dsh-im-bot） | `im-channel`（pushToUser / botsStatus / reload） | agents、agentPresets、approval/question、workspaceRegistry | dsh-memory（共享记忆挂载 + 按回合装配开关）→ 缺席则渠道会话按各自隔离；dsh-twin.noteActor（身份标注）→ 可选；`masking`（出站脱敏，dsh-redact 提供）→ 缺席首次 WARN 显式降级（原登记 #03 已销账） | ✅ |
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
| 01 | ✅ 已销账（2026-09-05） | dsh-task-board 在 dsh-ledger 缺席时 fail-closed 拒绝执行任务（核心功能不可用，违反原则二/3.5） | 已实现**本地降级策略**（governance.ts `adjudicateLocal`）：L0/L1 放行标注「无账本治理」、~~L2 放行 + 尽力通知~~ **L2 拦截 + 尽力通知（审计 F-02 修订：降级不扩权，宪章 §3.2）**、L3 拒绝且任务保留待办列；`state().governance.mode` 驱动客户端治理徽标（✓ 治理就绪 / ⚠ 本地降级）；账本在场行为与原版完全一致。测试 41/41 |
| 02 | ✅ 已销账（2026-09-05） | dsh-memory 存储位于 `~/.dsh/im-channel/credentials/`——写在兄弟插件目录下（违反原则三）且无视 `DSH_HOME`（多实例静默共享） | 存储迁至 `$DSH_HOME/dsh-memory/shared-memory.json`（归档同迁）；首次读取自动从旧路径迁移，旧文件保留作备份。已验证迁移链路 |
| 03 | ✅ 已销账（2026-09-05） | im-channel 消费的 `masking` 服务全工作区无提供者，出站脱敏静默空转（违反原则二的"显式"要求） | dsh-redact `provide('masking')`（`maskTextSync`，会话键 `im-channel-out` 保证占位符跨消息一致，命中计入统计）；im-channel 首次缺失时 WARN 一次（显式降级） |
| 04 | ✅ 已销账（2026-09-05） | dsh-twin 仪表盘/关系档案聚合兄弟插件 HTTP 端点，缺席时的降级表现未逐一保证 | 仪表盘登记缺席数据源：对应卡片显示「— / 提供方插件未安装」灰态，全部缺席且无待办时不再显示"一切正常"空态 |
| 05 | 🟡 部分销账（2026-09-05） | im-channel `bindings.json` 位于机器级 `~/.dsh/im-channel/`（跨实例共享） | **bindings 已迁**：`$DSH_HOME/im-channel/bindings.json`，首次读取自旧路径回退迁移，旧文件保留备份；渠道登录凭证仍留机器级（迁移需重新扫码授权，待排期） |
| 06 | 🟡 登记 | 御驿状态位于机器级 `~/.yuyi`（跨框架 seam，协议使然） | 属 §3.3 允许的例外，README 已标注理由；维持 |
| 07 | ✅ 已销账（2026-09-05） | 同源加固把路由包装器命名为 `register` 且内部调用自身——首条路由注册即无限递归栈溢出（被上层吞掉），`/dsh-memory/*` 全部 404（管理页与读写 API 整体不可达；tool-memory 走服务面不受影响，故分身对话无感） | 包装器改调 `web.register`（一行）；新增路由注册冒烟 + 跨域 403 测试（memory-api.spec.ts）。教训入册：**加固类改动必须在真实服务上冒烟整张路由表**——与自锁事故同族：动安全机制前，先验证它对现有能力面意味着什么 |

> 登记册由套件维护者更新；销账需在对应插件仓库留有整改提交并在本表标注结果。
> 补充整改记录（2026-09-05，随 01-04 同批）：im-channel 补声明缺失的 devDep `@deepseek-ai/dsh-util-values`（修复 wecom-mcp-registry 构建错误）。
> 补充整改记录（2026-09-05，第二批·任务层间挂链 + 安全加固）：
> - dsh-task-board 新增 `task_report` 模型工具（tools 入口 + dsh-twin 预设条件追加，预设版本 8→9）：分身上报结构化执行结果，直接落定运行记录终态并回填账本真实摘要；turn/end 推断降级为兜底；
> - 看板投递提示词声明三层任务契约（task_report 上报 / todo-goal 属会话脚手架 / 御驿委派沿用看板任务号）；
> - 修复 cron 触发任务提示词误标「手动触发」的死代码（launchScheduled 并入 launch(trigger)）；新增可配置投递重试（launchRetries，默认关闭）；
> - dsh-ledger 挂接 `tools/post-execute` 执行留痕（已放行→已执行闭环，markExecutedForAction 按动作匹配，isError 不留痕）；
> - dsh-memory 管理 API 增加同源门禁（带 Origin 且跨源一律 403，覆盖 token 下发与全部读写路由）；
> - smoke 脚本硬编码绝对路径改为可移植相对路径；dsh-ledger 补声明 typescript/vitest/@types/node devDeps。
> 补充整改记录（2026-09-05，第三阶段·分身能力深化）：
> - 分身向导：全新配置（人格未配置）默认勾选「设为默认预设」——开箱即分身；已保存配置以用户选择为准；
> - **actors 可选软接线**：im-channel 会话创建/恢复时顺带在 dsh-actors 注册对话者实体（主人 bindMaster 锚定、访客 provision 为生人）；actors 缺席/失败静默跳过，身份基线仍由渠道 userId 自持（宪章 §3.4）；
> - **按回合记忆装配**：dsh-memory 服务面新增 `assemblePack`（装配 + 审计回执），im-channel 以 `memoryAssemblePerTurn` 配置开关接入（**默认关**），开启后逐回合注入相关记忆包，装配失败不阻断派发；
> - **HostRunner 接入**：dsh-regression 经宿主 typertGateway 驱动真实分身会话跑回归场景（每个场景一个临时 digital-twin 会话，轮询 turn/end 结算并抽取分身真实回复）；「按策略 + policyRef」场景需策略命中标注，host 模式跳过；
> - **知识层定位**写入宪章 §0：知识 = 种子化权威事实记忆 + harness 技能，不另建独立知识库。
> 补充整改记录（2026-09-05，审计响应闭环：第一/第二轮审计 F-01～F-07、G-01～G-04）：
> - **F-01（Blocking）账本执行闸按宿主真实契约重写**：waterfall(exec, next)、exec.name/arguments 取动作、
>   放行 {kind:'allow'} / 拦截 {kind:'deny', reason}；留痕改 callId→recordId 精确登记（isError 亦留痕）；
>   移除按动作模糊匹配的 markExecutedForAction；health.gateChannel 标注真实契约
> - **F-02**：无账本 L2 改为拦截（不扩权，宪章 §3.2），任务保留待办列并尽力通知主任；
>   task-board-decisions.md 决策二已补宪章修订备注
> - **F-03**：task_report 以 exec.agent.id 与运行记录执行会话比对，不一致拒绝落终态（防伪造）
> - **F-04**：dsh-ledger 新增 GET /dsh-ledger/approvals；今日待办渲染待批列表 + 批准/驳回按钮，
>   批准后解析 digest 中看板任务号自动重跑（授权在位，grantCovers 放行）
> - **G-01**：actors 身份增强改在 router 绑定点以真实渠道 kind 注册（移除 driver 硬编码 'im'）；
>   主人锚定冲突 WARN 不静默
> - **G-02**：bind-store 测试隔离 DSH_HOME（防真实数据经迁移回退泄入断言）；持久化断言更新到实例级新路径
> - **G-03**：回归会话改名 regression-<场景id> 供审计；沙箱工作区建议与风险注记已写入 host-runner
> - **G-04**：dsh-regression 补 vitest devDep + classifyHostOutput 4 个单测；dsh-memory 建 vitest 骨架
>   （迁移/可见性/装配回执 4 用例）
> - **F-07**：宪章 §2 redact/im-channel 行修正；预设头注释 CONVERSATION-FIRST → conversation-first governed agent
> **⚠ 自锁事故记录（2026-09-05，已根治）**：F-01 修复让账本执行闸首次真实运行后，
> 其「未知名兜底 L2」策略把 read/pwsh/grep 等日常工作工具全数拦截（含主人会话），
> 分身瘫痪。根因：闸机制与闸策略从未一起核对过真实工具面——机制长期失效掩盖了
> 策略缺陷。根治：闸改为 **opt-in**（只裁决显式声明 args.actionType 的调用，普通
> 工具一律放行=决策六），health.gatePolicyProbe 常备探针，探针失败记入 issues。
> 教训入册：**修复一个失效的安全机制前，必须先审计它在真实环境下会拦截什么**。
> 遗留登记：#05 渠道登录凭证仍机器级（迁移需重新扫码授权，待排期）；#06 御驿 seam 维持例外；
> 「按策略 + policyRef」host 回归需宿主侧策略命中标注（已在 host-runner 跳过并注释）
> 补充整改记录（2026-09-05，第五批·全局活动感知 + 对话内下单，主任拍板：**看板 = 唯一活动权威**）：
> - dsh-task-board：tick 顺带维护**活动视图缓存**（进行中任务的执行现场 / 待审批 /
>   运行中自由会话（未归属任务，经 session/list 观察，排除任务现场）/ 最近完成 5 条），
>   provide 扩展为 `state()` + `activity()`（同步读缓存，绝无网络等待）；
> - dsh-twin：新增 `twin-activity` systemPrompt 区段（order 27）——每轮对话同步读看板缓存，
>   主任在**任何通道**问「在忙什么」都自带全局视野；**访客完全不可见**（拍板 3）；
>   空闲/看板缺席 → 空串零 token；twin 不做活动聚合（废弃直连 typertGateway 的草案）：
>   **看板是大脑，twin 只是报告者**；
> - 对话内下单：tools 入口新增 `task_delegate`（主任口头布置 → `createWithGovernance`
>   立项即预裁决（L2+ 产生审批令牌，fail-closed）→ `run_now` 立即执行；cron 任务默认不立即跑）
>   ——决策五「会话归属任务」的数据闭环自此打通；
> - 可见性红线：活动视图含其他工作现场标题，访客视图一律不注入（同源/tokens 门禁照旧）。
> - **原生 goal 联动（L1-L4 一批，主任拍板全量）**：①看板 tick 为自由会话折叠 `goal/change`
>   （L1）——活动视图新增 `goals` 维度（objective 截断 40 字，封顶 3）；②执行会话播种原生
>   goal（L2：L1 级 2 轮 / L2 级 3 轮，经 `goals/create` 远程面，播种失败降级 turn/end 结算）；
>   ③结算感知 goal 相位（L4 判断采**不结算继续等**：active → 下一轮、complete → 成功、
>   blocked → 失败带受阻原因、paused 走 legacy）；④task_delegate 描述补自由会话目标转正
>   指引（L3）。goal **状态**治理权归宿主：看板只对自己创建的执行会话做 goals/create
>   播种与事件折叠读取，不暂停/改写/终结 goal（跨包纪律照旧）。
> - **六角色团队评审修复（安全/并发/架构/测试/SRE/主任体验，2026-09-05）**：
>   ①tick 整体兜底 catch——任何 fs/网关抖动不得以 unhandledRejection 击穿宿主（SRE H1）；
>   ②结算 transact 内复查「运行中」（并发 Medium-1 覆盖竞态闭合）；
>   ③turn/end reason 白名单：aborted/interrupted → 已取消、error/blocked/max-tokens → 失败，
>   中止不再洗成"成功"（Medium-2）；④滞留兜底：运行中超 6h 强制取消（High-2 死区收敛）；
>   ⑤task_delegate 调用方会话绑定 + 外发/破坏性动词强制提级（L0/L1→L2、破坏性→L3）+
>   createWithGovernance 全级别落账本（digest 含 prompt 摘要）——封堵降级申报旁路（安全 H1）；
>   ⑥/dsh-memory/assemble 收敛为 token 门禁（安全 H2：不信任请求体自报 isMaster）；
>   ⑦scheduler 空载零写入（SRE H2：无命中绝不 transact）；⑧driver 硬编码 'im' 的
>   重复 actors 注册路径移除，统一 router onActorsBind（架构 M-1）；⑨governance 头注释
>   同步 L2 拦截语义（架构 M-2）；⑩provide 收窄为 activity 专用视图——完整 state 仅走
>   同源 HTTP 供浏览器 UI（架构 M-3，服务面同受访客红线约束）；⑪dashboard 重跑失败
>   显性化告知主任（架构 L-2）；⑫goals 维度翻页改 follow 取 cursor 反向取最新窗口
>   （并发 High-1：throughSeq:0 只返回会话第一条事件——该维度曾因此静默失效）；
>   ⑬task_delegate 输出补声明 action_level 并加「返回键 ⊆ output schema」回归测试
>   （宿主按 additionalProperties:false 校验工具输出，多余键即拒——主任会话实测发现）；
>   ⑭账本已知动作表扩展（主任拍板）：开发/修复/重构/编码/写文档/整理汇报/提交代码 → L1
>   （内部开发动作放行留痕，终结"未知类型兜底 L2"卡死开发任务的问题）；
>   ⑮task_delegate 关键词地板 v2：只对明确对外/破坏性词提级（v1 把"删除几行 DEBUG 打印"
>   误伤成 L3 致任务永不执行）+ 看板 ▶ 执行反馈弹窗（治理拦截/待审批不再静默无响应）；
>   ⑯对话内批准闭环：tools 入口新增 `task_approve`（主任说"同意/批准"→ 账本 approve →
>   自动重跑；防自批强校验：调用会话 ≠ 执行会话，令牌过期 fail-closed）+ twin 活动区段
>   待审批行补任务号——审批全链路（布置→执行→上报→批准→沉淀）在对话内即可完成。
> 补充整改记录（2026-09-05，任务记忆沉淀——决策五「记忆是经验积累」落地，审计路线 P1-6）：
> - dsh-task-board 任务落定终态（task_report 自报或 turn-end 兜底结算）自动把结果摘要写入
>   dsh-memory：`statementType=已验证结果` + `verify={status:'已验证', method:'看板结算'}`、
>   `type=task`、`scope=master`、`source={origin:'task-board', ref:任务号}`——主任问
>   「最近完成了哪些工作」即可被 tool-memory / 按回合装配检索到；
> - 惰性解析接入（`injectMemoryGetter`，与 dsh-ledger 同形态）：dsh-memory 缺席 WARN 一次
>   显式降级，写入失败不影响看板终态；成功与失败都写（失败同样是已验证的经验）；
> - 宪章 §2 dsh-task-board 行同步更新（矩阵新增 dsh-memory 增强方向；#01 销账描述
>   同步 F-02 后的 L2 拦截语义）。测试 41/41（新增 memory.spec.ts 4 用例）。

---

## §6 准入与检查

**新插件准入清单**（PR 评审逐项过）：
- [ ] 未 import 任何 `@dsh-extra/*`（构建期）；cordis `inject` 不含套件服务名
- [ ] 数据目录为 `$DSH_HOME/<插件id>/`，原子写；如需机器级路径，已注明例外理由
- [ ] 核心功能在兄弟全缺席时可用；每项增强缺席有显式降级（UI + 日志）
- [ ] 本表 §2 依赖矩阵已更新（提供/宿主消费/增强/单独可用性）
- [ ] README 含"单独安装"一节：最小安装、单独使用方式、降级行为
- [ ] **改动仓测试全绿 + 工作区干净**（无未提交改动/未跟踪产物）——提交前纪律，2026-09-05 审计后固化为常备项

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
| v1.1 | 2026-09-05 | 审计响应闭环（F-01~F-07、G-01~G-04、R-01~R-04）：自锁事故记录与 opt-in 闸策略、知识定位入 §0、准入清单固化「改动仓测试全绿 + 工作区干净」 |
