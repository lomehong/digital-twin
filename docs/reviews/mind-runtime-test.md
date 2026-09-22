# 可测性/质量评审：分身心智运行时设计草案 v0.1

> 评审人：test-reviewer（可测性/质量透镜）
> 评审对象：`docs/mind-runtime-design.md`（分身心智运行时 dsh-mind 设计草案 v0.1）
> 参照范本：`dsh-yuyi/tests/client.spec.ts` + `dsh-yuyi/tests/fixture-hub.ts`（假 hub/桩 ctx 先例）、`dsh-memory/tests/memory-store.spec.ts`（DSH_HOME 隔离先例）、`dsh-task-board/tests/service.spec.ts`（fake sessions/状态桩先例）
> 范围声明：只评可测性与质量；架构取舍、安全、并发、成本数值不越界。

结论: **需修订后批准**

设计的组件切分天然利于测试——时间线是纯文件、调度天然可参数化、兄弟依赖全部惰性 `ctx.get`，且套件已有三个可照抄的桩/隔离先例。但 v0.1 草案没有给唤醒循环留任何可注入缝（假 LLM、假时钟），P1 三条验收没有一条当前能自动测；§3.1 步骤 schema 缺回放审计的必填字段；kill switch 语义有歧义。以上均为"补几节文字 + 定稿字段"量级的修订，不构成架构返工。

---

## 阻断项（Blockers）

### B1 唤醒循环无 LLM/时钟注入缝——P1 验收全部不可自动测

**依据**：§4 唤醒循环 = 调度器（§5 分级退避 / QUIET_HOURS / SPEND_CAP / watchdog）+ 函数菜单 LLM run（§4.2）。全文未定义 LLM 调用边界，也未说明调度与墙钟的关系。对照套件先例：
- dsh-task-board 把"时间"做成纯函数入参（`collectDueTasks(at)`，`dsh-task-board/tests/service.spec.ts:210-221`），把可选兄弟做成注入点（`injectLedgerGetter` / `injectNotifier`，同文件 :16、:83）；
- dsh-yuyi 用 `vi.useFakeTimers()` + `advanceTimersByTimeAsync` 测轮询节奏（`dsh-yuyi/tests/client.spec.ts:160-174`）。

本设计若不预留同类缝，§9 P1 验收三条（"自主思考并沉淀记忆""成本符合预算""kill switch 有效"）没有任何一条能确定性复现——每次测试都在烧真模型、赌真墙钟。

**建议**：设计补一节"测试缝（必须实现）"，固定两个 port：
1. `MindLlm` 端口：`run(req: { systemPrompt, tools, context }): Promise<{ fn: MenuFn, steps: StepDraft[], final: string, usage?: TokenUsage }>`。生产实现包真模型；测试用脚本化菜单桩（见 N2）。
2. 时钟：退避/唤醒编排写成纯函数——`nextWakeAt(state, now): Date`、`applyOutcome(state, outcome): state`（engagement 归零、HOLD 降档、THOUGHT_CAP 全部收敛于此，时间只作参数传入）；真实定时器只是一层薄壳，才允许 fake timers。

**配套测试清单**（P1 落地即存在，用例名可直接采用）：
- `nextWakeAt：delay(n) 曲线——0、5s、10s、20s…封顶 300s`
- `applyOutcome：产出 action/observation/message_out → 退避归零（§5 engagement 定义）`
- `applyOutcome：纯 thought 连转 → 被 THOUGHT_CAP=60s 压住`
- `applyOutcome：HOLD=3——同档满 3 个空唤醒才降档`
- `scheduler（fake timers）：spontaneous 到点恰好触发一次唤醒 run`
- `scheduler：QUIET_HOURS 窗口内自发唤醒跳过、reactive 注入照常`
- `watchdog：超过 X 分钟无唤醒 → 合成 idle 唤醒 + 告警日志一条`
- `spend：usage 累计触顶 SPEND_CAP_DAILY → 自发唤醒停、reactive 保留（§5 原文语义）`
- `spend：假时钟推过日切 → 累计重置`
- `不变量：任意 scripted 唤醒后，时间线新增 ≥1 步骤且恰有 1 条 FINAL（§4.2"恰好产出"）`

### B2 §3.1 步骤 schema 不满足"回放一次心智决策"（G5 无验收载体）

**依据**：§3.1 wake 步骤只列"函数选择、耗时、token、FINAL 交接棒"（:104）；示例步骤 `"source": "mind"`（:97）没说清 source 是作者还是 §4.1 的三类触发源；一次唤醒的多个步骤之间没有 wakeId 关联；usage 无字段名；error 步骤无字段约定。缺了这些，"事后审计回放"无从下手，G5"失败显式告警不静默"也无法断言。

**建议**：在设计里 pin 死 wake 步骤必填字段：
`{ trigger: 'spontaneous'|'reactive'|'event', triggerRef?, wakeId, fn, durationMs, usage: { inputTokens, outputTokens } | null, backoffLevel, final }`；该唤醒产出的其余步骤带 `refs.wakeId`；`error` 步骤 pin `{ stage, message }`。

**测试**：
- `wake 步骤契约 pin：必填字段齐备（schema 断言，防字段悄悄缩水）`
- `回放元测试：给定任意时间线，可重建每次唤醒的「触发源→菜单选择→步骤序列→FINAL→token」链`——这条元测试就是 G5 可观察性的验收测试
- `LLM run 抛错 → error 步骤落盘 + 告警（不静默）`

### B3 kill switch 语义歧义——"kill switch 有效"写不成测试

**依据**：§5 :169-171"暂停 = 调度器停，时间线与数据不动"。三处未定义：① reactive 注入在 kill switch 下是否仍触发唤醒（对比 QUIET_HOURS / SPEND_CAP 均明写"反应性照常"）；② `config.json` 总闸与插件页开关的合流优先级；③ 暂停状态是否持久（重启后是否仍暂停）。

**建议**：先定稿一句语义（例如："kill switch 仅停自发唤醒，reactive 照常；两处开关任一为 pause 即暂停；状态持久化在 config.json"），然后逐条：
- `killSwitch：开启后 fake timers 推进 N 小时，自发唤醒为 0`
- `killSwitch：injectObservation 照常追加 message_in（是否随之唤醒按定稿语义断言）`
- `killSwitch：插件页开关与 config.json 任一为 pause 即生效`
- `killSwitch：重启后保持暂停`
- `killSwitch：解除后从冻结档位继续，不清零 spend 累计`

---

## 应改项（Should）

### S1 §7 降级矩阵无逐格测试计划，§8 自查项缺测试依据

**依据**：§7 表 6 行降级语义；§8 :233 已打勾"核心功能兄弟全缺席时可用"——打勾应由测试背书，但设计未要求任何对应用例。P1 三条验收之外的"可用性"验收全落在这里。

**建议**：照 dsh-task-board 注入桩模式（`injectLedgerGetter`），为 dsh-mind 定 `stubMemory / stubTaskBoard / stubTwin` 三件套 + `buildMind({ memory?, taskBoard?, twin? })` 夹具，矩阵逐格一条：
- `twin 缺席 → 唤醒 systemPrompt 含 core_identity_prompt 兜底标记（对 prompt 内容断言）`
- `memory 缺席 → learn/recall 跳过、thought/learn 步骤照写、无异常`
- `task-board 缺席 → act 收窄为只读；越清单动作产出 action 步骤移交 + 告警`（§7 :219"挂起并告警"——"挂起"落在哪个状态需先定义，否则无法断言）
- `ledger 缺席（经 task-board 本地降级）→ 按 P1/P2 归属补（见 S5）`
- `actors 缺席 → 归一退化为原始 userId`
- `im-channel 缺席 → message_out 仅记时间线，且 WARN 恰好一次（连续两次投递失败只 warn 一次，§6.2 :200）`
- `全缺席组合 → 自发唤醒仍产出 ≥1 thought + FINAL（§8 :233 的验收测试）`

### S2 外部契约漂移守卫缺失——yuyi 事故同款接缝有四处

**依据**：背景事故（core 0.1.6-alpha.2 strict codec 契约变严 → 手维护的 yuyi 远端贡献静默挂掉）；守卫先例 `dsh-yuyi/tests/client.spec.ts:242-267`（遍历 descriptors 断言 `codec.create()`）。本设计中"外部契约 × 手维护实现"的同款接缝：
1. **函数菜单 LLM 输出解析**（§4.2）——模型或提示词一变，解析静默退化（最坏情形：全部静默回退 idle，看似"诚实休息"实则全瘫）；
2. **时间线步骤 schema**（§3.1）——速览页、pending 扫描、FINAL 读取、P2 投影全是读方，schema 演进会静默破坏旧读方；
3. **渠道适配器契约**（§6.1）——im-channel 侧手维护 `injectObservation` 调用、mind 侧手维护 `deliver` 载荷构造，跨仓无共享运行时校验；
4. **兄弟服务面**——dsh-memory learn/recall、task_delegate 的方法签名漂移。

**建议**：新仓第一天就有 `tests/contract-guard.spec.ts`：
- `菜单解析器黄金样本：7 个函数（act/share/think/learn/recall/goals/idle）各一条输出 → 解析结果 pin`
- `菜单输出未知函数名/畸形载荷 → error 步骤 + 告警，禁止静默回退 idle`（"禁止静默回退"要写进设计正文，再由本用例钉死——这正是本次事故的教训）
- `菜单输出 schema 走 strict codec，且必带 create() 工厂`（照抄 yuyi 守卫，防 core 再变）
- `时间线读取器容忍未知 type 行：跳过 + 计数上报，不崩`
- `时间线读取器容忍文件末尾半行（崩溃残留）`
- `适配器契约 round-trip：假渠道 registerChannel → injectObservation → scripted LLM → deliver 载荷字段 pin（to/text/refs）`
- `registerChannel 缺 deliver → 注册显式失败`
- `兄弟服务面：type-only import 兄弟仓类型（typecheck 即守卫）+ 桩实现 pin 方法签名`
- 若 dsh-mind 自身暴露服务/远端贡献：`所有 strict codec 带 create()` 守卫从第一天就有

### S3 QUIET_HOURS 时区与 spend 状态持久化未定义，两条成本护栏不可测

**依据**：§5 :163-164 两项均只写"可配"。时区基准（本地/UTC）、spend 累计落盘位置（`$DSH_HOME/dsh-mind/` 下哪个文件）、日切按哪个时区、spend 文件损坏时的语义——全部缺失，`spend 跨日重置`与`QUIET_HOURS 边界`写不出来。

**建议**：设计各补一行；补测 `QUIET_HOURS 起/止分钟边界`、`spend 跨日重置按定稿时区`、`spend 文件损坏 → 按定稿语义（归零或保守沿用）`。

### S4 pending"承诺永不悬空"只有展示、没有升级语义

**依据**：§6.3 :209"时间线速览展示未销账的 pending 列表"——展示不等于保证；不定义超时行为，"承诺永不悬空"（:209）不可断言。

**建议**：定义升级语义（如：pending 超 N 次唤醒未销账 → 显式告警步骤/待办标记）。测试：
- `pending 压倒菜单：有 pending 时唤醒直接以 act 开工，不依赖 LLM 选择（§4.2 :140-141）`
- `message_in(pending) → act 处理 → message_out 携带 resolves → 列表销账`（P2 闭环主用例）
- `pending 超 N 唤醒未销账 → 告警`
- `resolves 指向不存在 seq → 显式告警不崩`

### S5 P1 分期与 §4.3 工具面不一致，降级矩阵格的归属不清

**依据**：§4.3 :150 唤醒 run 允许 `task_delegate`，但 §9 P1 行只列"人格兜底 + dsh-memory learn/recall"，task-board 未入 P1 清单，P2 才接渠道。若 P1 无 task-board，§7 第 3/4 行降级格（task-board/ledger 缺席）在 P1 就处于"缺席态"运行，设计未点明该状态要测。另外 §4.1 事件触发的"惰性探测"（:130）未定义探测方式与间隔，启用前需定稿才能测。

**建议**：二选一并写明——P1 即以"task-board 缺席态"运行并测 S1 对应格；或把 task_delegate 从 P1 工具面挪到 P2。测试清单按定稿归属。

---

## 建议（Nice）

### N1 测试布局建议（新仓 dsh-mind）

```
dsh-mind/tests/
  timeline-store.spec.ts     # 追加、seq 重启续号、0600、读取容错（S2）
  scheduler.spec.ts          # 纯函数 nextWakeAt/applyOutcome + fake timers 薄壳
  menu-run.spec.ts           # scripted LLM：菜单选择、步骤产出、prompt 断言
  spend.spec.ts              # 计量、触顶、日切（B1/S3）
  kill-switch.spec.ts        # B3
  adapters.spec.ts           # 假渠道 round-trip（S2）
  contract-guard.spec.ts     # S2 全清单
  client/panel.spec.ts       # 速览页，照 dsh-yuyi client.spec 的桩 ctx 模式
  fixtures/
    fake-llm.ts              # 见 N2
    fake-channel.ts          # 记录式函数桩 deliveries: DeliverPayload[]——适配器是进程内函数契约，借 fixture-hub"记录 + 可编排旋钮"的思路即可，无需起真实 ws 服务
    siblings.ts              # stubMemory/stubTaskBoard/stubTwin + buildMind(...)（S1）
```

隔离模板逐字照抄 `dsh-memory/tests/memory-store.spec.ts`：
- `mkdtempSync` 双临时目录（homedir + DSH_HOME）、`process.env.DSH_HOME` 设/清、`vi.mock('node:os')` 只换 homedir、afterEach 逆序 `rmSync` + try/catch（Windows 文件锁）；
- 注意该范本的两个坑位细节：mock 闭包在调用时读 `home`（:13-21）；模块在导入时读环境，所以用例内先设 env 再 `await import(...)`（:51、:90）。timeline 追加走异步落盘，断言前同样要逐条 await（:89-91 的教训）。

时钟用法分层：纯函数优先（时间作入参，照 `collectDueTasks(at)` 先例）；定时器薄壳才 `vi.useFakeTimers + advanceTimersByTimeAsync`（照 yuyi 先例），afterEach `vi.useRealTimers()`。

### N2 fake-llm 桩形态：一份"菜单脚本"驱动四类测试

```ts
// scriptedMindLlm([{ fn: 'think', steps: [...], usage: { inputTokens: 1200, outputTokens: 300 } },
//                  { fn: 'idle', final: '无事可做' }])
// 同时记录每次 run 收到的 { systemPrompt, tools, context }，供 prompt 内容断言
```

一个桩覆盖四类测试需求：①菜单选择行为（pending 压倒菜单、idle 正当产出）；②步骤产出与"≥1 步骤 + 1 FINAL"不变量；③token 计量（spend 测试的数据源）；④prompt 内容断言（twin 兜底是否注入、recall 是否发生）。另备 throwing 变体覆盖 error 路径。这是唤醒循环确定性的核心投入，比逐个 mock 整个插件 ctx 划算。

### N3 速览页与杂项

- `plugins.bundle.config` 速览页三件套（最近 N 步 / 当前状态 / spend 统计，§3.2）+ kill switch 开关 + pending 列表，client 测试照 `dsh-yuyi/tests/client.spec.ts` 的 `slots.register` 捕获 + `component({ view })` 检视模式（:113-119、:221-239）。
- 日志降级"WARN 一次"用 exactly-once 断言（S1 中 im-channel 格）。
- `重启后 seq 续号不重复`（时间线完整性的最小用例，归 timeline-store.spec.ts）。

### N4 CI 与流程守卫

- 每仓：`npm test`（vitest run）+ `npm run typecheck`；含 client 的话加 `typecheck:client`（照 dsh-task-board 的 scripts 约定）。
- 套件层流程约定：**core 版本升级的 PR 必须带各仓 contract-guard.spec.ts 全绿**——把本次 yuyi 事故从"事后补守卫"变成"升级前置门禁"。

---

## 给主人的问题

1. **kill switch 是否连 reactive 唤醒一起停？**（§5 只写"调度器停"；决定 B3 的测试语义）
2. **P1"成本符合预算"的 token usage 从哪里来**——宿主 LLM 会回传 usage 吗？若拿不到，验收是否降级为可测的"自发唤醒次数 ≤ 日预算次数"？（决定 B1 spend 测试的桩形态）
3. **QUIET_HOURS 与 spend 日切的时区基准**（本地 / UTC）？
4. **时间线步骤要不要加 `v` 字段**（schema 版本）？这是跨版本读取漂移守卫里成本最低的一招。
5. **回放审计存到什么粒度**——全量 prompt 快照，还是 refs 摘要（memoryIds / 人格卡版本）即可？影响 wake 步骤的体积上限与 B2 字段定稿。
6. **P1 是否包含 task_delegate？**（见 S5；决定 §7 降级矩阵哪些格 P1 就要测）
