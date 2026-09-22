# 架构评审：分身心智运行时设计草案 v0.1

> 评审对象：`docs/mind-runtime-design.md`（草案 v0.1，2026-09-18）
> 合规基准：`docs/suite-charter.md`（宪章 v1.5）
> 兄弟仓现状对照：`dsh-memory/AGENTS.md`、`dsh-task-board/AGENTS.md`、`dsh-twin/AGENTS.md`、`dsh-yuyi/README.md`（该仓无 AGENTS.md，以 README 替代）
> 参考底稿：`%TEMP%\headlong-research\design\THINKERS_spec.md`、`monolith_thinker.md`
> 评审透镜：架构边界与宪章合规（安全/并发/成本/测试不在本评审展开）

**结论: 需修订后批准**

方向正确：时间线 + 唤醒循环 + 瘦渠道适配器的骨架成立，"渠道不做心智的工作"与宪章联邦原则兼容；Q1 建议新仓 `dsh-mind` 的判断正确。但存在四处开工前必须修订的问题：渠道注册方向自相矛盾、唤醒执行器宿主底座未指定、G4 治理承诺与对外发声路径脱节、§8 准入自查失真。

---

## 阻断项（Blockers）——不改就不能开工

### B1 渠道注册方向自相矛盾：§6.1 与 §6.2 打架，且 §6.2 违反自家第一原则

**依据**：设计 §6.1 注释明确"渠道向 dsh-mind 注册（dsh-mind 提供，渠道惰性调用）"；但 §6.2 第一条写的是反方向——"dsh-mind 惰性 `ctx.get('im-channel')`：在 → 注册投递通路"。这要求心智核心硬编码 `im-channel` 这个具体渠道名、并理解其服务面形态，与 §0.2 第一原则"心智不感知渠道差异"和 G2"心智代码不 import、不感知任何渠道"直接冲突；P2+ 再加 web-bridge 时就得再硬编码一次探测。

**修改建议**：统一为单一路径——**渠道主动注册，心智被动接收**：dsh-mind 按 `dsh-memory` 范本（宪章 §4"早加载 + 被增强方晚注册重试"）声明 `provide('dsh-mind')` 早加载、无硬注入；im-channel 激活/重载时惰性 `ctx.get('dsh-mind')` 并调用 `registerChannel`，拿不到就晚注册重试。删除 §6.2 首条的 mind→channel 探测，改写为"渠道缺席 = 无注册到达 → `share`/`message_out` 降级为仅记时间线，WARN 一次"。降级判定语义不变（无注册即缺席），且可恢复性（宪章 §3.2 第 3 条）由晚注册重试天然满足。此修订同时把 Q5 的 im-channel 上游改动收敛为"激活时注册 + injectObservation + deliver 实现"三件小事，不需要 im-channel 新增投递注册 API。

### B2 唤醒执行器的宿主底座未指定，连锁触发宪章 §3.6 高危区

**依据**：设计 §4.3"每次唤醒 = 一次独立的 LLM 请求（非会话内多轮），带工具面（分身预设的模型工具子集）"，§4.2 菜单里 wake run 允许 `dsh-memory 读写 + task_delegate + web 查询`。但"task_delegate""memory 工具"都是**agent preset 挂载点的工具行**（`dsh-task-board/AGENTS.md` tools.ts、`dsh-memory/AGENTS.md` tools.ts）；宪章 §3.6 第 3 条实证教训："per-agent 宿主服务只能在 agent 挂载点注入，bundle app 层 ctx 的 inject 永不触发"。设计没有回答：唤醒 run 由什么跑？若是裸 LLM 调用 + 自建工具循环，则预设工具行、人格卡、twin-guard 守卫段（`dsh-twin/AGENTS.md`：GUARD_TEXT 是全分身会话的行为约束层）、按轮记忆装配（其注册点在 memory tools.ts 挂载点，非"运行时级覆盖全部会话"——设计 §0.3 首行的表述与该仓现状不符）全都不在位，需要逐项手工补装，且正是 §3.6 警告的静默哑火高发区。

**修改建议**：§4.3 增补"唤醒 run 执行面"小节，二选一并写死：
- **方案 A（推荐）**：唤醒 run = typertGateway 驱动的**临时无人会话**，物化 digital-twin 预设（task-board runner.ts 已示范此形态）——人格/守卫/工具行/记忆装配随预设自动到位，符合 §3.6 纪律；代价是需处理会话列表噪音与记账归属（见 S5/S6）。
- **方案 B**：裸 LLM + 自建工具循环——则必须显式调用 `assembleMemoryPack`（dsh-memory 服务面）、显式拼装人格卡与守卫文本、自注册工具行，并在设计文档中逐项列出，禁止任何"预设会自动覆盖"的假设。
无论哪种方案，§0.3 表"记忆装配 ✅ 覆盖全部会话"一行须改为如实表述（装配段注册在 agent 挂载点；唤醒 run 是否被覆盖取决于执行面方案）。

### B3 G4 治理承诺与 message_out/share 路径脱节：对外发声无任何治理点

**依据**：设计 G4 宣称"心智的对外动作与 task_delegate 同样过账本裁决（L0–L3）"；但通读 §4–§7，`share`/`message_out`（主动找人、对外投递）的路径是"唤醒选 share → deliver → 渠道投递"，没有任何账本/治理触点——§7 表里 dsh-ledger 一行只覆盖经 task-board 的间接消费。宪章 §0："分身对外行动受委托账本 L0-L3 约束"；§3.5 要求治理缺席时按预定义本地策略收敛到保守侧。主动向 IM 联系人/访客发声是典型的对外行动，当前设计让它成为治理旁路，G4 成立为空话。这正是宪章自锁事故教训（§5：机制与策略从未一起核对真实动作面）的预设重演。

**修改建议**：不必强行使 message_out 全量过 L0–L3（账本动作表是任务语义），但设计必须**显式声明治理位阶**并落一条机制，三选一：(a) message_out 纳入账本裁决（新增动作类型，如"主动触达"，缺账本时按 §3.5 保守降级——静音时段外仅记时间线不投递）；(b) 免裁决但受结构性约束：QUIET_HOURS + spend cap + 每渠道每联系人触达频次上限，缺席降级收敛到"仅记时间线"；(c) 仅对非 master 收件人的 message_out 过裁决，master 免。任选其一写进 §6/§7 并同步 G4 措辞，不留"治理不旁路"的未验证宣称。

### B4 §8 宪章准入自查失真：未实施却预勾可核验项，且漏 §3.6 对照

**依据**：宪章 §6 开宗明义"新插件准入清单（**PR 评审逐项过**）"。设计 §8 把"测试全绿 + 工作区干净""客户端入口 `apply(ctx)` + inject 声明；`plugins.bundle.config` 速览"标为 `[x]`——而 dsh-mind 仓尚不存在、无一行代码，这两项是 PR 时点才可核验的，预勾即失真（宪章 §5 登记册的教训之一就是机制未验证就宣称有效）。同时 §8 完全没有对照宪章 §3.6（打包、发布与挂载，四条实证纪律）——对新仓这是必答题：宿主包落 `dependencies` 不落 peer、桌面 Release 直装须打 tag 发版、per-agent 注入纪律（直接决定 B2 的方案取舍）、profile 注册禁相对链接。

**修改建议**：§8 改为三段式：(1) "设计已按此规划"项（依赖形态、数据目录、降级表）保留 `[x]` 但措辞改为"设计承诺，PR 核验"；(2) 时点项（测试全绿、客户端入口、§2 矩阵、README）一律改回 `[ ]` 并注明核验时点；(3) 新增 §3.6 四条对照行，其中"per-agent 注入纪律"一行显式链接 B2 的执行面决策。

---

## 应改项（Should）

### S1 渠道适配器契约（§6.1）最小但不完备，缺六件套

**依据**：设计 §6.1/§6.3、Headlong `THINKERS_spec.md`（pending 语义）与 `monolith_thinker.md`（"Exactly one reply per message"的幂等机械支撑）对照。逐项缺口：

1. **渠道注销/重载**：契约只有 registerChannel，无 dispose/重注册语义。im-channel 停用或 profile 重载后，mind 手里的 deliver 回调悬空——message_out 投递失败无状态可落。要求：`registerChannel` 返回句柄（或约定渠道重载时重新注册 + 旧注册按 channel id 幂等覆盖），deliver 拒绝时 mind 落 `error` 时间线步骤并告警，不重试到死。
2. **多渠道并存**：`id` 字段有了，但 §3.1 时间线 `message_in`/`message_out` 步骤 schema 没有 `channel`/`from`/`to` 字段，`deliver(payload.to)` 的 `to` 是渠道局部 userId，跨渠道无歧义消除。要求：时间线步骤 schema 补 `channel` 字段；`share` 决策须含目标渠道选择依据（P1 可简化为"仅注册一个渠道时启用 share"）。
3. **消息幂等/去重**：`injectObservation` 无幂等键。渠道超时重发、at-least-once 派发会产生重复 `message_in` → 重复唤醒 → 重复回复。Headlong 用 `reply_to` 传输层盖章 + 位置幂等网解决过同类事故（2026-08-03 双回复循环）。要求：`injectObservation` 增加 `dedupeKey`（渠道消息 id），mind 侧按 `(channel, dedupeKey)` 去重。
4. **观察积压语义**：唤醒 run 进行中或 kill switch 暂停期间到达的观察如何处置，设计未定义。Headlong 的答案可直接借鉴：message 类 FIFO 排队（封顶，溢出丢最旧并记日志），自醒类 last-wins 合并。要求：§6.3 之外补一节"注入积压语义"，至少定义"运行中排队、暂停时仍追加 message_in 但不唤醒、恢复后由 FINAL 交接棒感知"。
5. **pending TTL**：§6.3 说"承诺永不悬空"，但只给了速览展示，没有超时。心智死亡/长期 pause 时 pending 永挂。要求：pending 步骤带 TTL，超时落 `error` 步骤 + 告警，渠道侧可查询以降级告知用户。
6. **deliver 失败语义**：`deliver(): Promise<void>` 无错误契约。要求：约定 reject 的含义（渠道不可达/收件人无效），mind 据此把 `message_out` 标记 `failed` 并进入告警，而不是假装已投递。

**依据文件**：设计 §3.1、§6.1、§6.3；`monolith_thinker.md` 第 91–129 行；`THINKERS_spec.md` "Pending Re-Triggers" 节。

### S2 "渠道在时间线追加 message_in"（§6.3）的措辞违反宪章原则三

**依据**：设计 §6.3"渠道快速回复路径遇到需要深工的请求 → 渠道**在时间线追加** `message_in`"。若按字面实施，就是渠道插件直接写 `$DSH_HOME/dsh-mind/timeline.jsonl`——宪章原则三"插件只把数据写进自己的目录，不写进别的插件的目录"，且正是 §5-02 登记过的同类违规（dsh-memory 曾写进 im-channel 目录）。

**修改建议**：措辞改为"渠道经 `mind.injectObservation({..., pending: true})` **服务调用**追加"；并加一句红线声明：`$DSH_HOME/dsh-mind/` 仅 dsh-mind 进程写入，渠道一切交互走 cordis 服务面。

### S3 §7 关系表缺行：被消费方向整块缺失，宿主消费未列

**依据**：设计 §7 表只有"dsh-mind 消费 X"一个方向；宪章 §2 依赖矩阵是四列（提供/宿主消费/套件增强/单独可用性）。缺口：

- **被消费方向**：im-channel → dsh-mind（§6 的惰性调用方）、P2+ web-bridge → dsh-mind。§7 表和将来的 §2 矩阵都要写"谁消费我"。
- **宿主消费行**（宪章允许且不计耦合，但矩阵必须有）：llm/typertGateway（唤醒 run 执行面，B2）、timer（唤醒调度器，dsh-twin 同款）、webServer（若速览走 HTTP）、**token 计量来源**（§5 SPEND_CAP_DAILY 需要每 run 的 usage 数据来源与记账存储位置，设计未指明——spend.json 归 `$DSH_HOME/dsh-mind/`）。
- **dsh-redact/masking 归属声明**：message_out 出站脱敏必须声明"沿渠道既有出站管线（deliver 由渠道实现，脱敏在渠道侧生效），心智不旁路"。不写这句，将来 mind 直连某渠道传输 API 就会绕过 masking（宪章 §2 redact 行的既有接线的意义所在）。
- **workspace-registry**：dsh-mind 应显式声明**不消费**（`act` 的执行会话由 task-board 既有 runner 路径创建，workspace 归该路径管），把边界闭环，避免实施时臆测。
- **dsh-yuyi**：显式声明不消费（协同经由 task_delegate → 看板既有链路间接可达），维持 yuyi 零耦合标杆（宪章 §2、`dsh-yuyi/README.md`）。
- **时间线自身的增长治理**：append-only jsonl 永续增长无归档/轮转策略。dsh-memory 有归档区先例（其 AGENTS.md"替代链/归档区"）。要求：§3.1 补归档策略占位（如按 seq 分段文件或年度归档，P1 可只留策略声明）。
- **mind 意图/待办的存储层**：§4.2 `goals` 函数"校准意图/待办"未定义存储位置。宪章 §0 任务三层职责互斥：全局层=看板、会话层=harness todo/goal（随会话生灭）、协同层=御驿。mind 无会话，其意图不得伪装成看板任务，也不该用会话脚手架。要求：明确落点（建议 dsh-memory 的 objective 类陈述 + 时间线衍生状态），并在 §7 声明与看板全局层的互斥边界。

### S4 Q1 边界论证不完整：漏了 dsh-twin proactive 与 timer 的重叠归属

**依据**：设计 §10-Q1 建议"新仓"的理由（关注点分离、插件=纯框架、twin 保持人格内聚）成立，本评审**支持新仓**。但论证漏了一个现存事实：`dsh-twin/AGENTS.md` 明列 `proactive.ts`（**状态卡汇入+主动触达**）与 timer 调度。若 dsh-mind P2 落地 `share` 主动发声，套件将同时存在两套自主触达通路（twin timer 驱动的 proactive、mind 退避驱动的 share），双渠道主动轰炸主人、双份 token 支出（且 twin 的 timer 支出不受 mind spend cap 约束）。设计 §0.3 现状对照表对 twin proactive 只字未提。

**修改建议**：Q1 建议补第三条论据与归属拍板项：新仓后，dsh-twin proactive 或者 (a) 迁移为 mind 的一个触发源/函数（twin 只供状态卡数据），或者 (b) 明确划界共存（如 twin proactive 仅限状态卡汇入类、share 仅限内容分享类，并在双方 README 互相声明）。同时 kill switch 应声明覆盖范围："一键暂停"是否也停 twin proactive，须写明。

### S5 §3.3 否决"常驻会话"的论据有一处不成立，且第三形态未评估

**依据**：设计 §3.3 列的三条否决理由中，"会话上下文无限增长与 token 计费冲突"不成立——harness 会话本有 compaction，宪章 §0 也会话层明载该机制；且 task-board runner 已示范"无人输入的临时分身会话"形态，"会话=人可输入"的前提也不完全对。结论（时间线 + 每唤醒独立 run）仍然正确，但正确的论据是：**append-only 审计语义**（会话压缩/改写破坏"心智的一生可回放"）、**逐动作治理拦截点**（§4.3 的清单外动作移交机制依赖时间线步骤而非会话工具面）、**永续生命周期**（会话生灭由人驱动）。另有一个被忽略的第三形态值得留档：**事件源 + 状态快照**——timeline.jsonl 作事件日志，另派生 `state.json`（当前工作集/FINAL/open loops）原子重写，唤醒时读快照而非回放全量，长生命时间线下这是必要的扩展缝。

**修改建议**：§3.3 重写论据为上述三条，并补记第三形态的评估与取舍（P1 可不做快照，但应声明这是已知扩展点而非永久设计）。

### S6 唤醒 run 的会话形态必须与看板活动视图的"自由会话"识别协调

**依据**：宪章 §5 第五批整改记录：dsh-task-board tick 经 session/list 观察把"运行中自由会话（未归属任务）"纳入活动视图缓存。若 B2 选方案 A（临时会话执行唤醒），每次唤醒都会以"自由会话"面目出现在主人活动视图里——轻则噪音，重则被误认为失控会话。这是两个既有机制的真实交互，设计 §7 未提及。

**修改建议**：约定唤醒会话命名规范（如 `mind-wake-<seq>`），并要求在 dsh-mind 或 dsh-task-board 一侧把该命名模式排除出"自由会话"维度（哪个仓改，随 B2 的执行面决策一并定，进 Q5 协调清单）。

---

## 建议（Nice）

- **N1 时间线存储工程细节**：`seq` 分配在"调度器唤醒 + 渠道并发注入"下需要单写者保证——参照 `dsh-memory/AGENTS.md` memory-store 的"文件锁+原子写"先例；尾行截断容忍（进程崩溃留下半行 JSON，读取侧跳过并告警）。深并发归并发评审人，此处只主张"存储格式必须定义单写者语义"。
- **N2 learn 沉淀的来源归因**：经 dsh-memory 落库的 learn 步骤应带 `source.origin: 'dsh-mind'` + `refs.timelineSeq`，符合 dsh-memory 认识论治理的来源归因设计（其 AGENTS.md"六类陈述类型/来源归因"），主人可回溯每条记忆到时间线原点。
- **N3 兜底人格的来源定义**：§7"dsh-twin 缺席 → `core_identity_prompt` 兜底"未说明该值从哪来——应定义为 dsh-mind 自持配置项（`$DSH_HOME/dsh-mind/config.json`），否则兜底本身悬空。
- **N4 渠道感知心智状态**：`registerChannel` 返回值或回调中带 mind 运行状态（运行/暂停/降级），渠道可在 UI 告知用户"分身心智已暂停，回复会延迟"——比 pending TTL 更早的用户体验兜底。
- **N5 P2 时间线只读投影**：§3.2 P2 的"只读会话投影"若落地，建议复用既有会话 UI 槽位机制而非新建视图，且沿用 Q3 的访客不可见判定（与宪章 §5"可见性红线：访客视图一律不注入"先例一致）。

---

## 给主人的问题

1. **dsh-twin proactive 的归属**（S4）：新仓 dsh-mind 后，twin 的主动触达是迁移给 mind（twin 只供数据），还是划界共存？本评审倾向前者——一条主动发声通路、一份预算。
2. **message_out 的治理位阶**（B3）：主动发声你希望 (a) 纳入账本裁决、(b) 免裁决但受静音时段+频次上限约束、还是 (c) 仅对非 master 收件人过裁决？建议 (c)：对主人的投递免裁决保持亲密感，对外触达受治理。
3. **唤醒执行面**（B2）：接受"唤醒 run = typertGateway 临时无人会话（复用 digital-twin 预设）"的方案 A 吗？它多花一点会话开销，但让守卫/人格/工具/记忆装配全部按既有纪律自动到位。
4. **im-channel 上游改动排期**（Q5 + S6）：B1/S6 修订后，im-channel 侧改动收敛为"激活时晚注册 + injectObservation（带 dedupeKey）+ deliver 实现 + 唤醒会话命名排除"四件小事，是否授权与 im-channel 仓协调排期？

---

## 评审依据清单

| 发现 | 依据 |
|---|---|
| B1 | 设计 §0.2、G2、§6.1 vs §6.2；宪章 §1、§4（dsh-memory 早加载范本） |
| B2 | 设计 §4.2、§4.3、§0.3；宪章 §3.6 第 3 条；`dsh-memory/AGENTS.md`、`dsh-task-board/AGENTS.md`、`dsh-twin/AGENTS.md` |
| B3 | 设计 G4、§6、§7；宪章 §0、§3.5、§5 自锁事故教训 |
| B4 | 设计 §8；宪章 §6、§3.6 |
| S1 | 设计 §3.1、§6.1、§6.3；`monolith_thinker.md` 幂等章；`THINKERS_spec.md` pending 节 |
| S2 | 设计 §6.3；宪章 §1 原则三、§5-02 |
| S3 | 设计 §5、§7；宪章 §0、§2、§3.3；`dsh-memory/AGENTS.md` 归档区 |
| S4 | 设计 §0.3、§10-Q1；`dsh-twin/AGENTS.md`（proactive.ts/timer） |
| S5 | 设计 §3.3；宪章 §0（compaction/会话层）；`dsh-task-board/AGENTS.md`（runner 无人会话先例） |
| S6 | 宪章 §5 第五批整改记录（活动视图自由会话观察）；设计 §4.3、§10-Q5 |
| N1–N5 | `dsh-memory/AGENTS.md`、设计 §3.1–§3.2、§7、宪章 §5 可见性红线 |

> 合规总评：设计声明的插件间耦合形态（全量惰性 `ctx.get`、无 `@dsh-extra` 值导入、`$DSH_HOME/dsh-mind/` 数据自治、每项增强缺席降级）方向上全部符合宪章 §1/§3；阻断项集中于**契约方向一致性、执行面落点、治理位阶、自查诚实度**四处，均为文档级修订，不动摇架构骨架。
