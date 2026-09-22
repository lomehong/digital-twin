# 可靠性/并发评审：分身心智运行时设计草案 v0.1

- 评审人：sre-reviewer（可靠性与并发透镜）
- 评审对象：`docs/mind-runtime-design.md`（dsh-mind 设计草案 v0.1，2026-09-18）
- 依据材料：headlong `design/monolith_backoff.md`、`design/monolith_run_health.md`、`bin/thinkers` 调度器源码；套件先例 `dsh-memory/src/memory-store.ts`（文件锁+原子写）、`dsh-memory/src/memory-autopilot.ts` 头注（LESSONS 2 / LESSONS 8 模式）
- 范围声明：只覆盖可靠性与并发。成本仅在与可靠性交叠处（退避节奏、预算持久化）触及；架构/安全/测试不越界。

**结论: 需修订后批准**

总评：架构方向是对的——时间线 + dispatcher-native 调度 + 每唤醒独立 LLM run，与 headlong 已验证并在事故中进化出的形态一致。但草案在四处只给了名词、没给机制：**调度器本体、并发让位规则、崩溃恢复语义、fail-safe 全局纪律**。headlong 的事故史（setsid 静默失效、435 次 rc=141 被当 idle、六小时假死、22 小时重放旧消息）恰好全部发生在这些空白处，且共同特征是**静默**——心智看起来活着，实际早已停摆。以下修订均为设计文档补写，不动架构，故不到"重大修改"。

---

## 阻断项（Blockers）

### B1 调度器本体缺失：tick、状态存放、恰好一次、看门人分离

**现状**：§2 只有一个"唤醒调度器（退避/wake_at watchdog）"框图，§4.1 一句"调度器按 wake_at 到点"，§5 一句"kill switch = 调度器停"。以下全部未定义：tick 频率与载体；wake_at 与退避状态在内存还是磁盘、进程重启后如何重建；同一 due 唤醒如何保证只触发一次；唤醒与 reactive 注入并发时谁先谁后。

**依据**：
- headlong `monolith_backoff.md` 的演进本身就是这个坑的填法：v1 用 `setsid` 后台 timer——macOS 无 setsid，**静默失效**，自发性直到第一次 reactive 唤醒前全灭；修订为 dispatcher-native（step 写 `run/<name>.wake_at`，常驻 dispatcher 的 1s tick 里到点消费）。设计 §5 已选对方向，但把"dispatcher"背后的机器全省了。
- `bin/thinkers` `_scheduled_wake_check` 的防御细节每一条都有事故背书：文件内容非法即删除（防脏数据卡死循环）；busy 或全局并发满则**留下文件**下个 tick 重试；派发前 `rm -f` 消费（恰好一次）；step 出口重新 arm。
- 退避状态持久化先例：`monolith_backoff_state.json`（level / ticks_at_level / last_wake_ts），"只有 monolith step 写、dispatcher 串行化故无需锁"。

**修改建议**（§5 增补"调度器本体"小节）：
1. **载体与节奏**：dsh-mind 在宿主进程内注册常驻 timer（建议 1–5s tick，headlong 为 1s）。tick 只做：查 due → 判忙 → 消费 → 派发。**明确禁止"在 run 内部 sleep 到下一档"的形态**——headlong 正是因此废弃 in-step sleep（长 cap 会把派发槽钉死整个休眠期，"The idle wait must not occupy the thinker slot at all"）；P1 验收加一条：CAP 调到 30 分钟时，等待期不占任何执行资源。
2. **状态落盘**：wake_at、backoff level/ticks、spend 计数全部进 `$DSH_HOME/dsh-mind/state.json`（临时文件+原子替换，沿 memory-store.ts 先例）；重启后从磁盘重建。state 缺失/损坏 → 从时间线尾部最后一条 wake 步骤保守推断；再不行 → 按 CAP 档起搏，**绝不静默停摆**。
3. **恰好一次**：到点唤醒采用 headlong 语义——先判忙；派发动作 write-ahead 落盘（或先消费 wake_at 再派发），使"重启后同一次 due 二次计费"在时序上不可能。
4. **看门人与被看门人分离**：watchdog 不能只是同一个 timer 的自我检查——timer 若因未捕获异常死亡，同进程内无人再看。要求：tick 函数体全捕获；另设一个独立低频 timer（如 60s）只检查"上次 tick 时间戳是否过期"并复活；`scheduler.lastTick` 暴露到速览页。

### B2 续命责任与崩溃恢复：无 FINAL 的 wake 步骤是弃是续？

**现状**：§4.2 说每次唤醒产出"≥1 条时间线步骤 + FINAL 交接棒"，但没说：run 崩溃/超时/永不返回时，**下一次唤醒由谁保证**？宿主在 run 中途崩溃，重启后发现无 FINAL 的 wake 步骤，续还是弃？

**依据**：
- headlong Issue D（monolith_run_health.md）：唤醒 run 后台 nohup 的 web 服务器握住输出管道 → step 卡在 `read()` **六小时**，EXIT trap 不执行 → `arm_wake` 永不发生 → 心智全静默，而 systemd 全部 active、死亡告警只看 unit，**无任何报警**。教训被铸成铁律（`bin/thinkers` stuck-step guard 注释）："A step that never exits arms no next wake, and the mind goes silent." 对位修复 = stuck-step guard：final 后 grace 300s → TERM（让 EXIT trap 跑完续命）→ 15s 后 KILL → 落 error 步骤。
- headlong 的 EXIT-trap 哲学：arming 是唯一续命机制，"must happen even on a crash/refusal path"——续命属于调度器层，不属于 run 自己。
- Issue C：runaway generation 打满 600s 超时、整次唤醒白烧——run 必须有硬超时。

**修改建议**（§5 或新增小节）：
1. **续命责任在调度器**：派发时登记"在飞 run + 硬超时死线"（建议默认 ≤120s，可配）；超时 → 追加 `error(wake-timeout)` 时间线步骤 → 按**封顶错误退避**续排下一次。run 结束/失败/卡死都不影响下一次唤醒的存在。
2. **重启恢复语义**：启动时扫时间线尾部，发现 wake 步骤无 FINAL 配对 → 追加 `error(wake-interrupted)` 步骤**显式弃单**（不续跑半截 run——半截 run 的中间态不可信），退避按"一次空唤醒"保守推进，并立即续排一次唤醒。一句话规则写进设计：**续 = 只续排程，不续执行**。
3. **让"无 FINAL"可机检**：派发时先写 `wake` 占位（含 dispatched 时间），结束时写配对的 final 交接棒——恢复逻辑靠结构判断，不靠猜。

### B3 并发模型缺失：单飞还是并存？谁让谁？

**现状**：§4.1 说 reactive"立即，永不限速"；§4.3 说越界动作移交 task-board 执行会话。于是三股 LLM 流——心智唤醒 run、task-board 执行会话、im-channel 快速回复——在同一宿主进程、同一模型配额上并存。设计没有回答：并发上限是多少？reactive 到达时在飞 run 怎么办？"永不限速"只排除了退避/预算闸门，没排除撞车。

**依据**：
- headlong 的全套并发治理都有事故背书：每 thinker 串行（`_thinker_busy`，忙则入 pending）；pending 分型——message/action **FIFO 排队（cap 16，丢最旧且丢有日志）**，其余 last-wins coalesced（防积压陈旧 self-wake 烧钱）；槽释放时 **message 优先派发**（"a freed slot answers a waiting human before it services a coalesced self-wake"）；全局 `THINKERS_MAX_CONCURRENT` 兜底。
- 数据层有 memory-store.ts 文件锁+原子写兜底（唤醒 run 与其他会话并发写记忆不会互相覆盖），但 **LLM 限流与宿主进程负载没有任何一层管**。

**修改建议**（§5 增补并发矩阵）：
1. **心智单飞**：P1 同一时刻至多 1 个唤醒 run 在飞。reactive 到达时若在飞 → 入 pending 队列、当前 run 结束后 message 优先派发（headlong 语义，秒级延迟）。明确不选"并发抢跑"：同一心智两个 run 并行会交叠写时间线、双花预算、上下文互不知情。
2. **"永不限速"的精确定义**：永不参与退避/spend-cap/quiet-hours，而非不受并发上限约束。给心智派发设独立并发上限（P1 就是 1），触顶显式排队且速览可见。
3. **让位规则分级**：若在飞的是高退避档的 thought/idle run，允许 reactive 到达时提前 abort（可选优化，P2+）；P1 至少做到排队优先。
4. **run 卫生**：写明"唤醒 run 内不做长任务、不后台驻留进程"——这是 Issue D 的直接教训（唤醒里 nohup 服务器 → 六小时假死）；长活儿一律走 task-board 移交（§4.3 已有此意，升格为硬规则）。

### B4 fail-safe 全局纪律缺失（LESSONS 2）

**现状**：§7 降级表管的是"兄弟插件缺席"，不管"dsh-mind 自己病了"。通篇没有一句"任何 dsh-mind 内部异常必须绝不击穿宿主"。

**依据**：LESSONS 2（`dsh-memory/src/memory-autopilot.ts` 头注："宿主接缝的同步抛错会击穿宿主"，autopilot 对所有宿主回调全 try/catch 防御）。dsh-mind 是常驻 timer + 高频 LLM/文件 IO，是全套件里最容易周期性抛错的部件；一次未捕获异常若打到宿主，代价按 LESSONS 2 是**整个 harness fatal**。headlong 的对应纪律是"failure-open"：dispatcher 的 `_append_traj_error` 永不阻塞派发，错误只落时间线。

**修改建议**（§7 开头加全局纪律段，并列为准入验收项）：
- dsh-mind 所有接缝——`ctx.get` 结果的每次调用、渠道 `injectObservation`/`deliver` 回调、timeline/state 全部 IO、LLM 调用、JSON 解析——逐层 try/catch；异常 → `error` 时间线步骤 + WARN 日志 + 封顶错误退避，继续运行；**绝不向上抛、绝不 unhandledRejection**。
- config.json 损坏 → 回默认值 + 告警，不 fatal。
- 速览页与本体故障隔离：速览读失败只影响页面，不影响调度。
- 验收加故障注入项：喂坏 timeline 行、坏 config、LLM 全 5xx，宿主与调度循环必须存活。

---

## 应改项（Should）

### S1 时间线增长与读取成本：tail 原语 + 大字段外置 + 滚动归档

依据：monolith_run_health.md A2/A3——19k 步轨迹因大字段内联涨到 **312 MB**；532 MB 文件曾导致一次上下文构建 **78 秒**；修法 = 大字段 spill + 只读 tail（O(N) 不 O(file)），headlong web reader（byte-offset seek、append-aware 增量缓存）是参考实现。设计 §3.2 的速览要"最近 N 步"，§9 P3 的金字塔管的是**记忆粗化**，不是存储/读取成本——两件事正交，设计应分开写明，避免误以为 P3 顺带解决了 timeline 增长。建议：① P1 就写死读路径纪律：速览与唤醒上下文读时间线一律 tail 原语（从文件尾反读 N 步），**禁全文件扫描**（含内部"取最后 seq"这类读）；② 单字段大小上限（正文超阈值外置 blob 文件、行内留 ref）；③ 轮转（P2 可做）：按大小/时间切段，整段 mv 归档、绝不重写活跃段，归档保留期可像 memory-assemble 回执 90 天清理那样配置化。

### S2 时间线不可重写纪律 + seq 游标健壮性（rewind 对位防护）

依据：2026-09-12 headlong 事故（`bin/thinkers` rewind guard 注释）：外部脚本 `grep -v > tmp && mv` 重写轨迹 → `tail -F` 按名跟随从第 1 行重放 1.5 GB → **回答一个月前的旧消息 22 小时**；对位 = ts 游标 + 容差 + step_id 去重的 rewind guard，以及 inode/size 变化的 TRAJECTORY REPLACED 检测。dsh-mind P1 无 tail-follow，风险形态不同，但 **seq 承担游标职责**（FINAL 交接棒、resolves 引用、重启续扫）。建议写明：① timeline.jsonl **永不就地重写**——修正 = 追加步骤，清理 = 整段轮转（接 S1）；② 启动扫描校验：seq 单调递增、末尾半行丢弃（崩溃撕裂容忍，headlong 在 feeder 死亡时同样丢半行而非拼接），发现倒序/跳跃 → error 步骤告警并按文件尾重建游标；③ 轮转/归档后 seq 引用仍可解析（段文件名可寻址），或明文规定跨段引用降级为告警、不断链不静默。

### S3 errored run ≠ idle：失败不得推进正常退避

依据：monolith_run_health.md Issue B——435 次 rc=141（SIGPIPE）被当普通 idle 计，"错误完全不可见，且静默把心智减速到像在休息"；修法 B2 = error 步骤 + 独立封顶错误退避。建议 §4.2/§5 明确三分：**干净 idle**（正常退避）/ **真实工作**（退避归零）/ **失败**（error 步骤 + 封顶错误退避 + 速览红点）。这是 G5"失败显式告警不静默"的落地细则，现在 G5 只有口号。

### S4 watchdog 细化 + 静默告警

依据：`bin/thinkers` `_watchdog_check`——忙或有 pending 时刷新时钟（长 run 不误报），合成 idle 走同一退避；headlong 另有 silence alert（轨迹超 6×CAP 无 touch → 告警，恢复报 "is back"）。Issue D 的静默之所以六小时无人知，就是告警只看 unit、unit 是好的。建议 §5 watchdog 行补三点：① 窗口测的是"空闲且静默"时长，在飞 run 刷新时钟；② 合成唤醒按真实 idle 计退避（防 watchdog 自己变成全速空转源）；③ P1 版静默告警：时间线超 K×CAP 无 touch → WARN 日志 + 速览状态徽标（P2 可经 im-channel pushToUser 推给主人）。

### S5 kill switch 期间 pending 的语义 + 队列上限

依据：§6.3"承诺永不悬空"与 §5"kill switch = 调度器停"相撞：主人暂停心智的同时，渠道移交的 pending 深工请求（对真人的承诺）到达或未完成——静默无回应即承诺悬空。headlong 的 pending 有形：FIFO cap 16、丢最旧、丢有日志。建议：① 明确 kill switch 粒度：默认只停 spontaneous（与 spend-cap 同语义）；pending 是否豁免列为开放问题（见提问 Q3）；若不豁免，渠道侧必须感知"心智已暂停"并回退自己的兜底文案，速览未销账列表标红；② pending 队列设上限，丢弃必须留显式事件（error/idle 步骤或日志），防渠道风暴时无声积压。

### S6 spend 计数持久化：重启不得清零日预算

依据：§5 SPEND_CAP_DAILY；headlong backoff state 落盘先例。计数若只在内存，宿主崩溃重启 = 预算清零；崩溃循环的宿主会反复重置预算，spend cap 形同虚设。建议：日计数随每次 LLM 调用原子落盘（并入 state.json），按本地日界重置，重启读盘；"触顶停发"状态也在速览可见，而非静默停。

### S7 写入完整性：单一写路径 + seq 分配 + 半行容错

依据：memory-store.ts 头注先例（读-改-写全事务在文件锁内、临时文件+原子重命名）；设计 §3.1 只写了"原子追加 0600"。建议：① seq 由 dsh-mind **单一写路径**分配——渠道 `injectObservation` 也排进同一入口，渠道不得自行拼行写文件；② 追加前校验文件尾以 `\n` 结束（防在崩溃半行后拼接损坏行）；③ state.json 等读改写文件走锁+临时文件原子替换；④ 点明前提：P1 各写方同进程，单写路径即可成立；若未来多进程写时间线，需升级为文件锁（沿 memory-store 先例）。

---

## 建议（Nice）

- **N1 高退避档降档**：深层 idle 用快模型或先跑一次廉价 peek（"现在值得全模型醒来吗？"）再决定是否升级为完整 run——monolith_backoff.md 的 optional second lever，与设计 Q2 的快模型方向呼应。
- **N2 share-nudge**：每 N 次自发唤醒注入一次 share 路由提示（headlong 默认每 12 次），防 share 通道因无提示而自然死亡。
- **N3 速览增量读取**：插件页读端做 append-aware 增量缓存（headlong web trajectory.py 模式：byte-offset 续读、O(new-steps) 轮询），配合 S1 的 tail 原语。
- **N4 机械步骤过滤**：wake/error 等机械步骤不进唤醒上下文的 recent-tail（headlong `_recent_stream` allowlist 模式）——既防上下文被机械行稀释，也防模型模仿机械行格式（Issue C 的模板模仿事故教训）。

---

## 给主人的问题

1. **并发让位**（B3）：reactive 到达时在飞的自发 run，接受"排队等它跑完（受硬超时约束）"吗？还是希望高退避档可被打断？建议 P1 排队、P2 再评估打断。
2. **无 FINAL 处置**（B2）：同意"显式弃单 + 只续排程不续执行"吗？还是希望从中间态恢复？（建议弃：半截 run 的中间态不可信。）
3. **kill switch 豁免**（S5）：心智暂停期间，pending 的深工承诺（对真人的答复）要不要照常服务？不豁免的话，可接受渠道兜底文案代替吗？
4. **时间线保留**（S1/S2）：全量永久保存（P4"分身一生可浏览"的前提）还是滚动归档（如 90 天活跃 + 永久归档段）？这决定轮转的实施形态。
5. **idle CAP 默认值**（§5）：headlong 默认 CAP=300s（对应 $1–2/小时量级）。分身要不要更冷静起步（如 10–30 分钟）？§5 写的"对齐 headlong 实测量级"是按哪个 CAP 折算的？
