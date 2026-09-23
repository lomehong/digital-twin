# 分身心智运行时（dsh-mind）设计草案

> 状态：**v0.5——P1/P2(核心)/P3(v1)/UI 重造 v1 已实施（见 §9 实施记录）；待主人拍板 D1–D5 中余项（D1 方案 A 已按建议实施）**
> 日期：2026-09-18（v0.2）；2026-09-20（v0.5 UI 重造）
> 评审纪要：`docs/reviews/mind-runtime-review-synthesis.md`（五份完整评审在同目录）
> 关联：`docs/suite-charter.md`、研究底稿克隆 `%TEMP%\headlong-research`

---

## 0. 背景与第一原则

> **分身 = 一个持续存在的心智，拥有单一时间线。**
> Web 控制台、IM、未来任何 CLI 都只是这台心智的**终端**：终端只做两件事——把外部
> 输入作为观察**注入**心智的时间线；把心智的输出**投递**给对应的人。
> **心智不感知渠道差异；渠道不做心智的工作。**

现状缺口：分身是反应式（消息驱动）+ 日程式（cron 清单），无常驻心智；其职责
散落进渠道（im-channel driver 堆满记忆挂载/审批桥/装配开关——渠道在做心智的工作）。
dsh-memory v0.2.7 已把记忆装配升到运行时级覆盖全部会话（对齐第一步），本设计补上
本体：**心智运行时**。

---

## 1. 目标与非目标

**目标**
- G1 常驻心智：按自身节奏持续思考/行动，外部消息只是时间线观察之一
- G2 渠道无关：心智代码不 import、不感知任何渠道；新渠道 = 瘦适配器
- G3 反应性与自发性分离：回应人永不限速；自驱思考分级退避控成本
- G4 治理不旁路（v0.2 收紧）：治理点落在 dsh-mind 执行器内主动 `ledger.check()`
  留痕，**不依赖**兄弟插件的 opt-in 闸；无账本时保守收敛（宪章 §3.5）
- G5 可观察：时间线速览 + 每次唤醒可回放（触发源/用量/交接棒/退避档位全留痕）
- G6 成本可控：两级 spend cap、静音时段、kill switch（fail-safe 到「停」）
- G7 **全局 fail-safe（v0.2 增）**：dsh-mind 内部任何异常绝不击穿宿主（LESSONS 2）
- G8 **可测（v0.2 增）**：唤醒循环可确定性测试（假时钟/假 LLM/假渠道桩）

**非目标**：per-user 会话隔离（访客可见性走既有投影规则）；自我改进 fork/merge
（远期）；替换各渠道 fast-reply 路径（保持现状）。

---

## 2. 架构总览

```
              ┌────── 渠道适配层（瘦：只做注入/投递）──────┐
Web 控制台 ───┤  （P2 起提供适配器；P1 无渠道也可运行）      ├──┐
IM(微信/飞书/企微)┤  渠道侧惰性 ctx.get('dsh-mind') 注册     │  │
              └──────────────┬────────────▲──────────────┘  │
              injectObservation           │ deliver          │
                             ▼           │                  │
        ┌────────────────────────────────┴────────────────┐ │
        │              分身心智运行时 dsh-mind              │ │
        │ ┌─────────────┐ ┌────────────┐ ┌──────────────┐ │ │
        │ │ 心智时间线    │ │ 唤醒调度器   │ │ 唤醒执行器     │ │ │
        │ │ timeline.jsonl│ │ 退避/wake_at│ │ 函数菜单 run  │ │ │
        │ └─────────────┘ └────────────┘ └──────┬───────┘ │ │
        └────────┬───────────────┬─────────────┼─────────┘ │
                 ▼               ▼             ▼           │
           dsh-memory     dsh-task-board   dsh-twin(人格/守卫)│
          (learn/recall)  (act 落地+账本)   (临时无人会话底座)  │
                 └──────────── 投递回渠道 ◄──────────────────┘
```

**归属（Q1）**：新仓 `@dsh-extra/dsh-mind`。心智运行时（时间线/节奏/决策）与
dsh-twin（人格投影/学习闭环）是两个关注点；五角色评审一致认可（arch B1 修复见 §6）。

---

## 3. 心智时间线

### 3.1 存储与步骤 schema（v2，test B2 修订）

- 位置：`$DSH_HOME/dsh-mind/timeline.jsonl`；append-only；**单一写路径**（全部经
  dsh-mind 的 API，渠道/面板不得直写——宪章原则三）；半行容错（崩溃残留尾行跳过
  并告警）；滚动归档（默认保留 180 天，归档件 `archive-<月份>.jsonl`）。

```json
{ "v": 2, "seq": 42, "ts": "2026-09-18T10:00:00.000Z",
  "type": "wake", "source": "mind",
  "trigger": "spontaneous | reactive | event | watchdog",
  "wakeId": "w-<ts>-<rand>",
  "content": "…",
  "fn": "act | share | think | learn | recall | goals | idle",
  "final": "交接棒：做了什么/剩什么/下一步",
  "usage": { "llmCalls": 1, "tokensIn": 5000, "tokensOut": 500, "costUsd": 0.0031 },
  "backoffLevel": 0,
  "resolves": "message_in seq（仅交付步骤）",
  "refs": { "memoryId": "…", "taskId": "…" } }
```

`type` 枚举：`thought | observation | action | message_in | message_out | task |
idle | error | wake | run-summary`。必填 pin：`v/seq/ts/type/source`；`wake` 步骤
额外 pin `trigger/wakeId/usage/backoffLevel`（G5 可回放的验收载体）。

### 3.2 可见性与安全（security 修订）

- **时间线对访客不可见 = 硬规则**（原 Q3 升格）：含跨对话聚合信息，属主人
- 插件页速览路由带 **sameOrigin 门禁**（LESSONS #11：插件自有 HTTP 路由不在上游
  认证围栏内；先例：dsh-memory 整改）
- `message_out` 出站**复用渠道出站链**（dsh-redact masking 随之生效；否则为登记册
  #03 翻版）；web 查询结果回填前过 maskTextSync（若已安装）
- **心智的 memory 写入禁止「授权」陈述类型**——授权只能来自批准通道（账本不变量），
  封死"自铸授权再自我放行"循环（security B1）

### 3.3 UI/UX：心智主页（v0.5 UI 重造）

> 第一原则的体验面落实：心智已经是人，UI 必须呈现人。**主语从「插件运行时」
> 换成「TA」**——机器状态一律翻译为第一人称生活语言（narrate.ts 纯函数层，
> 测试覆盖）；治理与成本数据保留但降为细节层（照护抽屉/可展开 detail）。
> 时间线 schema、调度器、治理位阶、访客不可见硬规则零改动。

**三挂点**（客户端，特性检测双写对齐 task-board）：
- `main`（key=`mind`）：侧边栏「心智」一级页面 = TA 的家
- `sidebar.panellist`（id=`mind`）：在场感图标（人形 + 状态点：思考呼吸/睡/停）
- `plugins.bundle.config`（key=包名）：summary=迷你人物卡；page=心智主页

**心智主页信息架构**（人视图默认）：
① 在场感头部：呼吸光环（思考=呼吸绿/睡=暗蓝/停=灰）+ 第一人称状态句
（presenceLine：退避→「安静一会儿」、静音→「我睡着了 01:00–08:00」、
硬顶→「今天想得够多了，省着用」、被叫停→「是你让我停的」）
② 留言（对话闭环）：输入框 → `POST /dsh-mind/say`（message_in 落时间线 +
反应性唤醒，~1s tick 触发）→ TA 的回复（wake step FINAL）同界面呈现
③ 生活流：时间线按天分组（今天/昨天/M月D日）叙事化——wake=时刻卡
（fn→「我在想/我在办一件事/我想告诉你…」，触发源/用量/成本收进可展开 detail）、
message_in=右气泡「你说」、idle 折叠「我歇了一会儿」、error 温和呈现
「有个念头断了」
④ 照护抽屉：预算条（心思花费/软硬顶人话化）、作息、下次自己醒、
「N 件事等你点头」（pendingApprovals）、「让 TA 休息/叫醒 TA」（kill switch
拟照护化，语义不变：显式停持久）

**双模式**：默认永远是人；右上角「工程视图」一键切回五区块运维面板
（原速览：成本行/状态/退避档位/kill/原始时间线），选择持久化 localStorage。

**HTTP 面**（sameOrigin 门禁 + 写操作启动随机键门禁，先例 dsh-memory）：
`GET /status`（v3：+quiet/pendingApprovals/spendLevel）、`GET /timeline?n=`、
`POST /say`（text ≤2000 → message_in + 反应性唤醒）、`POST /kill`、
`GET /token`（下发写门禁键）。

**v0.3.0 存在体（The Being）**（主人拍板：形态=光球或人形剪影、常驻窗口右下角）：
呼吸光球 + 光晕中隐现人形剪影（胸口随呼吸起伏），运行时状态全部翻译为身体语言——
呼吸节奏（思考 2.6s/清醒 6.5s/入睡 11s）、光的色温与明暗、内部涌动（思考漩涡）、
收到留言时的涟漪（attentive）。三处呈现：① shell.overlay 常驻右下角（任何页面
可见，pointer-events 穿透，点击就地展开面板：存在体+留言+最近生活+照护）；
② 心智主页存在体居中为绝对主体（216px），生活流/照护折叠为「TA 的一天」/「照看 TA」；
③ 入口 conversation.view「心智」Tab（当前宿主实测定级）+ main/sidebar.panellist
双写（新宿主自动升级）。形体情态推导 beingMood 为纯函数（叫停>入睡>注意到你>
思考>清醒），测试覆盖。
（v0.2.1 附带修复：唤醒 FINAL 内嵌 `[fn]` 标记致 idle 误判 think、退避不生长——
fnOf 全文搜标记 + idle→empty；叙事层 idle 文本形态识别 + 连续休息折叠 +
0/0 计量缺失不渲染假 detail。）

### 3.4 为什么不是常驻会话（维持 v0.1 结论，补正 arch 意见）

会话语义（人可输入/生灭）与心智时间线冲突；token 计费随会话无限增长。
**补正**：v0.1 "压缩不可行"论据不成立（harness 会话本有 compaction）；真正的
否决理由是治理点与会话语义。**第三形态（事件源 + 状态快照）被评估**：本质与
jsonl+速览等价，P1 采 jsonl（与 mem/traj 哲学一致、可 grep），P4 评估投影为
只读会话。

---

## 4. 唤醒循环

### 4.1 触发源

| 触发 | 来源 | 节奏 |
|---|---|---|
| spontaneous | 调度器按 wake_at 到点 | 分级退避（§5）；最低 5 分钟一醒 |
| reactive | 渠道注入 `message_in` | 立即；不受退避，受 §5.3 反应性护栏 |
| event | task-board 终态/待审批、ledger 裁决 | 立即；纳入频次治理（security 应改） |

### 4.2 函数菜单（每次唤醒选一件事）

`act | share | think | learn | recall | goals | idle`（语义同 headlong monolith，
本地化改写）。规则：
- **pending request 压倒菜单**；完成后 `message_out` 携 `resolves=<seq>` 交付销账
- 每次唤醒恰好产出：≥1 条时间线步骤 + FINAL 交接棒；`idle` 是正当产出
- **禁自铸授权**：learn 的 memory 写入限定陈述类型 ∈ {thought 类}（§3.2）

### 4.3 唤醒执行器底座（v0.2 写死：方案 A，arch B2）

裸 LLM 请求拿不到 preset 挂载的工具行/人格卡/守卫（宪章 §3.6 禁 app 层注入
per-agent 服务）。**执行器 = 经 typertGateway 在临时无人会话上复用 digital-twin
预设**：工具行（含 task_delegate/memory）、人格卡、twin-guard、按轮记忆装配全部
随 preset 到位；run 结束即弃会话。移交协议唯一合法通道 = `task_delegate`
（落到 task-board 执行会话 + 账本治理）。

### 4.4 守卫纪律（security B4）

唤醒系统提示词 = 函数菜单 + 守卫文本 + 人格卡 + 时间线上下文。守卫文本**经
dsh-twin 服务面获取**（禁止运行时值导入，宪章 §3.1 合规）；dsh-twin 缺席时用
内置兜底守卫（身份边界 + "不泄露时间线跨对话内容" + "工具调用前自检治理位阶"）。

### 4.5 治理位阶（v0.2 显式，D2）

| 动作 | 裁决 | 留痕 |
|---|---|---|
| 对 master 的动作（think/learn/recall/goals） | 免裁决 | 时间线 |
| 对外触达（向非 master 渠道投递 / share 给生人） | **受治理**：执行器内主动 `ledger.check()`，L2+ 挂起待批 | 时间线 + 账本 |
| act 落地执行 | task_delegate 原生治理路径 | 账本 |
| 无账本（ledger 缺席） | 对外触达**保守挂起**（只记不发，WARN 一次） | 时间线 |

---

## 5. 节奏与成本护栏

### 5.1 分级退避（继承 v0.1，修正 cost 意见）

```
v0.6 修正（2026-09-22 成本事故）：
  自驱地板 MIN_SPONTANEOUS = 300s（默认；可配）——兑现 G1「最低 5 分钟一醒」。
  实测事故：旧实现 delay(0)=0 + 5s 起跳，engaged 归零后 15–45s 一拍（超设计 20 倍），
  且每拍跑完整 LLM turn（~4.4K tok/次）；配合计量字段错位（记 0），账上看不出血。
  delay(n) = clamp( min(base×factor^(n-1), CAP=300s), MIN_SPONTANEOUS, ∞ )
  HOLD=3；engaged 仍归零（连转意图保留），但归零后同样不早于地板。
  机械空醒短路（idleShortCircuit，默认开）：无新观察、无事件、无待批、上一拍亦空转
  → 不调用模型，记 idle 步骤续排（空转拍成本降为 0）。
  反应性（reactive）/事件（event）**不受地板与短路影响**（G3：回应人永不限速）。
QUIET_HOURS：绑 IANA 时区（默认 Asia/Shanghai），默认开启（01:00–08:00），
             旅行一键切换；静音期 share 缓发（pending 豁免）
```

### 5.2 成本底账与两级 cap（cost B3）

每唤醒 ≈5K tokensIn / 0.5K tokensOut。静默日（CAP=300s）自发唤醒 288 次：
deepseek 级 **$0.18–0.46/日**，Claude 级 **$3.4–6.5/日**。

**两级 cap（Q4 答案）**：deepseek 级 **$1/日**、Claude 级 **$5/日**（≈2–3× 静音
稳态）。80% 软顶：自发唤醒降级快模型；100% 硬顶：停自发，**保留反应性与
pending**。spend 计数持久化（重启不清零）。

### 5.3 反应性护栏（security B5）

`message_in` 触发合并窗口（60s 内同渠道多条合并为一次观察）+ 小时上限（默认
20 次/小时，超出部分静默并入下一窗口观察，**不丢内容只降频**）。

### 5.4 kill switch 与 fail-safe（security B6 / sre B4 / G7）

- kill switch = 插件页开关 + config 总闸；**config 损坏/被删 → fail-safe 到「停」**
- 暂停态：调度器停，watchdog 合成唤醒**不得复活暂停态**
- 全局纪律：dsh-mind 任何接缝 try/catch + 错误退避，**绝不击穿宿主**（LESSONS 2）

---

## 6. 渠道适配器契约（arch B1 修订：单向注册）

### 6.1 注册方向（修复 v0.1 自相矛盾）

**渠道侧惰性注册**：渠道（如 im-channel）在会话挂载点惰性
`ctx.get('dsh-mind')`，缺席则晚注册重试（宪章 §4 dsh-memory 早加载范本同款）。
**dsh-mind 零渠道感知**（G2）；dsh-mind 缺席时渠道行为与今天完全一致（零回归）。

### 6.2 mind 侧暴露的 API（渠道调用，非直接写文件——宪章原则三）

```ts
mind.registerChannel({ id, deliver(payload): Promise<void> })   // 注册/更新/注销
mind.injectObservation({ channel, from, isMaster, text, refs? }) // 追加 message_in（可触发唤醒）
mind.markDelivered(seq) / mind.markFailed(seq, reason)           // 投递状态机回写
```

### 6.3 契约六件套（arch 应改）

① 渠道注销（dispose 清投递路由，pending 转"渠道离线"态）② 多渠道并存 schema
（channel 字段全程携带）③ 幂等键（injectObservation 带 messageId，重复注入去重）
④ 观察积压语义（心智单飞期间排队，message 优先）⑤ pending TTL（默认 24h，超时
降级告知"此事受阻"）⑥ deliver 失败语义（failed 状态可重发，重发前 24h 指纹
去重豁免——失败从未送达）。

### 6.4 pending-request 协议（cost B2 修订：不吞单）

- 渠道快速回复路径遇到深工请求 → 先 **t=0 承诺话术**（"收到，我在办，稍后给你
  结果"）→ injectObservation 带 `pending: true`
- 心智 `act` 完成 → `message_out` 携 `resolves` → 渠道投递销账
- **护栏不吞单**：kill switch / spend cap / watchdog 触发时 pending **不销账**，
  恢复后先排空；**15 分钟无进展** → 降级告知"此事受阻，原因 X"
- 未销账 pending 在速览常驻展示

---

## 7. 与现有组件的关系（arch 应改：补被消费方向与宿主消费）

| 方向 | 明细 |
|---|---|
| dsh-mind 消费 | dsh-twin（人格卡+守卫文本，服务面）、dsh-memory（learn/recall）、dsh-task-board（act 落地+治理）、dsh-ledger（经 task-board 或直接 check）、im-channel（投递，P2）、llm（唤醒 run）、token-meter（用量计量） |
| 被消费 | 渠道（im-channel 注入/回写，P2）；插件页速览（自读） |
| 显式不消费 | workspace-registry、yuyi（远期评估）、compaction（时间线自有归档） |
| 宿主消费 | timer/tick 载体、sessions（方案 A 临时无人会话） |

| 兄弟缺席 | 降级 |
|---|---|
| dsh-twin | 内置兜底人格+守卫 |
| dsh-memory | 时间线即记忆 |
| dsh-task-board / dsh-ledger | act 收窄为只读；对外触达保守挂起 |
| im-channel | message_out 仅记时间线（WARN 一次） |

**D4（拍板项）**：dsh-twin `proactive.ts` 主动触达并入 mind 的 `share` 函数
（消除双主动源），P2 实施，涉 dsh-twin 上游。

---

## 8. 宪章准入自查（arch B4 修订：实施时逐项验收，v0.1 预勾选作废）

- [ ] 无 `@dsh-extra/*` 值导入；inject 不含套件服务名（全部惰性 ctx.get）
- [ ] 数据目录 `$DSH_HOME/dsh-mind/`，原子写 0600
- [ ] 核心功能兄弟全缺席可用（§7 降级矩阵逐格测试，含"全缺席"组合用例）
- [ ] 每项增强缺席显式降级（UI/日志）
- [ ] §2 依赖矩阵更新；README 单独安装一节
- [ ] 测试全绿 + 工作区干净（每期提交纪律）
- [ ] 客户端入口 `apply(ctx)` + inject；速览走 `plugins.bundle.config`
- [ ] **§3.6 打包挂载纪律对照**：行引用的包已装才写行（可选行物化时探测追加）；
      per-agent 服务不经 app 层注入（方案 A 经 preset 挂载点天然合规）
- [ ] contract-guard 全绿（§10.4）

---

## 9. 实施分期与记录

| 期 | 内容 | 状态 |
|---|---|---|
| **P1 心智本体** | 时间线（schema v2+归档）+ 调度器（§11 规格）+ 函数菜单唤醒 run（方案 A 底座 + 兜底人格/守卫 + dsh-memory learn/recall）+ 两级 cap + kill switch + 速览 | ✅ 完成（@dsh-extra/dsh-mind v0.1.0，22/22 绿，GitHub Release tarball 已发布） |
| **P2 渠道接入** | im-channel 注入观察（driver 惰性 injectObservation，缺席零回归）+ masking 复用；pending 深工显式协议 P2.1 跟进 | ✅ 核心完成（im-channel cbaa38c）+ share 投递通道（channels.ts registerChannel/deliver，v0.3.7） |
| **D4 主动源让位** | dsh-twin proactive 检测 dsh-mind 在场即让位（移交日志一次；状态卡汇入照旧） | ✅ 完成（twin a0dd0c0） |
| **P3 记忆金字塔 v1** | 时间线分层 recap（F=10 机械卷积零成本版）接入唤醒上下文；LLM 逐层摘要与 dsh-memory 实体金字塔远期 | ✅ v1 完成（recap.ts，28/28 绿） |
| **P3.5 UI/UX 重造 v1** | 心智主页（TA 的存在界面）：main/侧边栏一级入口 + 插件页人物卡 + narrate 叙事层 + 留言闭环（/say→message_in→反应性唤醒）+ 照护抽屉 + 工程/人双模式 + 写门禁键 HTTP 面 | ✅ 完成（v0.2.0，44/44 绿） |
| **P4 远期** | 时间线只读会话投影、goals 精化、自我改进评估 | — |

### 实施记录（2026-09-18）

- 仓库：`lomehong/dsh-mind`（workflows：ci.yml/release.yml）；Release v0.1.0
  tarball（CI 全绿后发布，审计=lib/index.js+lib/client.js+cordis.patch.yml）。
- 实施修正：①§4.3 "run 结束即弃会话" 落地为**常驻心智会话 + 超阈值重建**
  （避免会话列表污染；输入 token 由 stream usage 实测）；②客户端 bundle 需
  esbuild `charset: 'utf8'`（默认 ASCII 转义会让中文不可 grep）。
- 踩坑沉淀：dsh-yuyi/docs/LESSONS.md（async effect 调度 / create() 契约 /
  peerDep 测试图卫生——2026-09-18 同批三事故）。

---

## 10. 可测性设计（test 评审落地）

### 10.1 可注入缝
- `MindLlm` port：唤醒 run 的 LLM 调用边界（测试注入 `scriptedMindLlm` 桩——按
  脚本返回函数选择与步骤，一份桩覆盖行为/不变量/计量/提示词断言四类测试）
- 调度纯函数化：`collectDueMindTriggers(now, state)` 无副作用可直测
  （先例：task-board `collectDueTasks(at)`）
- 时钟注入：`now()` 由宿主传入

### 10.2 P1 确定性用例（≥10）
退避曲线（engagement 归零/HOLD=3 逐档/THOUGHT_CAP）/ reactive 合并窗口与小时上限
/ spend 软顶降级与硬顶停自发（持久化重启不清零）/ watchdog 合成唤醒不复活暂停态
/ config 损坏 fail-safe 到停 / 崩溃弃单（无 FINAL wake）+ 只续排程 / pending 不吞
单（四条护栏路径）/ 降级矩阵逐格（含全缺席）/ 时间线 schema pin 与半行容错 /
create()-式外部契约守卫（菜单输出解析、适配器契约、兄弟服务面）

### 10.3 回放验收
任一历史唤醒可从时间线单独回放：触发源 → 装配的上下文摘要 → 函数选择 → 步骤 →
FINAL → 用量（G5 验收载体）。

### 10.4 contract-guard（流程门禁）
菜单输出解析 / 时间线 schema / 渠道适配器契约 / 兄弟服务面四处接缝各一组守卫
（先例：dsh-yuyi v0.1.8 create() 契约守卫）；流程约定：core 升级 PR 必须带各仓
contract-guard 全绿。

---

## 11. 调度器规格（sre B1–B4 落地）

- **tick 载体**：宿主 timer（1s 级 tick；tick 只做"读 wake_at + 到期派发"，轻量）
- **wake_at 状态**：`run/wake-at.json` 原子写（tmp+rename 0600）；重启从「时间线
  尾部 wake 步骤 + wake-at 文件」重建调度态
- **恰好一次**：rm-then-dispatch 语义（消费即删，派发失败重排队）；同一 due 幂等
- **续命归调度器**：唤醒 run 硬超时（默认 10 分钟）；派发即续命，不依赖 run 成功
- **崩溃弃单**：重启见无 FINAL 的 wake 步骤 → 显式 `error` 步骤弃单（不复活执行），
  只续排程
- **并发模型（P1）**：心智单飞——唤醒 run 期间 reactive/event 触发进 pending 队列
  （message 优先），run 结束先排空 message 再按退避续排
- **禁止** in-step sleep 形态（headlong 教训：占调度槽 + cap 无法长大）

---

## 12. 生命周期与常驻保证（v0.3 增）

### 12.1 插件 = 宿主进程内的代码，不是独立进程

dsh-mind 的调度器是宿主 timer 上的 tick 循环：**宿主进程活着，心智就活着**。
与 task-board 的 cron 调度、dsh-twin 的 timer 完全同级——套件已验证的常驻模式，
心智不引入新的存活机制。进程内韧性：

- 状态全落盘（timeline / wake-at / spend 计数）；**宿主重启、插件热重载后从磁盘
  恢复调度态**（重启见无 FINAL 的 wake 步骤 → 显式 `error` 弃单，只续排程）
- 错过的多次 due **只补一次**（对齐 task-board cron「错过不补跑」纪律——下线期间
  的空闲不变成恢复后的补课轰炸；headlong 的时间线同样把 idle 折叠为一条）
- watchdog：超阈值无唤醒 → 合成 idle 唤醒 + WARN（计数排除暂停态）
- 任何接缝异常 try/catch + 错误退避，绝不击穿宿主（LESSONS 2）

### 12.2 kill switch 双状态（v0.2「一律到停」的修正）

| 失效类别 | fail-safe 方向 | 理由 |
|---|---|---|
| **显式停止**（主人在插件页/配置关闸） | 持久化为显式意愿状态，重启后**仍停** | 主人的明确意愿必须被尊重 |
| **意外损坏**（config 解析失败/文件缺失） | 回落内置默认**保守运行**（cap 按最保守值、静音默认开） | 意外不应当机；默认即最保守档 |

两者状态分离存储：`stopped-by-master`（显式）与 config 解析结果互不覆盖。

### 12.3 宿主常驻 = 部署前提（对整个分身成立，非心智独有）

宿主进程停 = 整个分身下线（IM/看板/账本/Web 全停），心智只是其中之一；心智抬高的
是宿主在线率的 stakes。部署矩阵（对齐 headlong deploy/ 的 systemd + 告警模式）：

| 方案 | 形态 | 说明 |
|---|---|---|
| 本机常驻 | `dsh web` 注册 Windows 自启（服务/计划任务，禁睡眠） | 最简单 |
| **专用盒子（推荐）** | NAS/小主机 7×24 跑 `dsh web`，配进程守护 + 死亡/静默告警（对齐 headlong `headlong-thinkers@.service` + `*-alert` 单元） | 真 7×24 |
| 云端 VPS | 同上托管 | 无本地硬件时 |

实施期（P1）交付《宿主常驻部署指南》（本机自启脚本 + 专用盒子 systemd 模板）。

---

## 13. 决策台账

**已采纳默认（工程项）**：注册单向化；时间线访客不可见硬规则 + sameOrigin 门禁；
message_out 复用出站链（masking）；生人投递默认挂起；两级 cap 数字（deepseek
$1/日、Claude $5/日）；QUIET_HOURS IANA + 默认开启；THOUGHT_CAP=CAP；spend 持久
化；errored run ≠ idle；滚动归档 180 天；contract-guard 四组 + 流程门禁；中文消
息写作规范对照表入提示词。

**待主人拍板**：
| # | 问题 | 建议 |
|---|---|---|
| D1 | 执行器底座方案 A（typertGateway 临时无人会话复用 digital-twin 预设）vs B | **A** |
| D2 | 治理位阶（master 免裁决留痕 / 对外受治理 / 无账本保守挂起） | 按建议 |
| D3 | spend cap 数字（deepseek $1/日、Claude $5/日，80%/100% 两级） | 按建议 |
| D4 | dsh-twin proactive.ts 并入 mind share（P2，涉上游） | 并入 |
| D5 | im-channel 适配器小改排期（P2 前置） | 授权后 P2 启动 |

---

## 14. 修订记录

| 版本 | 变更 |
|---|---|
| v0.1 | 初稿（方向对齐：心智运行时 + 渠道纯适配器） |
| v0.2 | 吸收五角色评审 18 阻断项：调度器规格（§11 新增）、执行器底座方案 A（§4.3）、治理位阶与守卫注入（§4.4/4.5）、禁自铸授权（§3.2）、两级 cap 与反应性护栏（§5.2/5.3）、kill switch fail-safe（§5.4）、契约单向化+六件套（§6）、pending 不吞单（§6.4）、时间线 schema v2+归档（§3.1）、可测性设计（§10 新增）、§8 自查回退+§3.6 对照、§7 补被消费/宿主消费与 D4 |
| v0.3 | 新增 §12 生命周期与常驻保证：插件=宿主内代码的常驻语义（磁盘状态恢复/错过 due 只补一次/watchdog）、kill switch 双状态（显式停持久 vs 意外损坏回落保守运行——修正 v0.2 的一律到停）、宿主常驻部署矩阵（本机/专用盒/云） |
| v0.5 | UI/UX 系统性重造（P3.5，主人拍板：人/工程双模式 + 独立心智页面 + 留言闭环）：§3.3 重写为心智主页三挂点（main/侧边栏/人物卡）+ narrate 叙事层（机器语义→第一人称生活语言）+ 照护抽屉（治理拟照护化）+ 留言闭环（/say → message_in 落时间线 + 反应性唤醒）；HTTP 面加写门禁键（先例 dsh-memory）；schema/调度/治理/红线零改动 |
| v0.6 | 成本护栏修正（2026-09-22 主人套餐严重超支事故）：§5.1 新增自驱地板 MIN_SPONTANEOUS=300s（兑现 G1「最低 5 分钟一醒」——旧实现 5s 起跳 + engaged 归零，实测 15–45s/拍）+ 机械空醒短路（无新事不调用模型）；runner 用量字段对齐宿主 TokenUsage 契约（inputTokens/outputTokens，旧字段致计量恒 0、两级 cap 失效）；反应性/事件触发不受限 |
