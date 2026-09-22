# 分身心智运行时设计评审纪要（v0.1 → v0.2）

> 评审团：架构（arch）· 安全/治理（security）· 可靠性/并发（sre）· 成本/体验（cost-ux）· 可测性（test）
> 评审对象：`docs/mind-runtime-design.md` v0.1
> 完整评审原文：本目录 `mind-runtime-{arch,security,sre,cost-ux,test}.md`
> **总裁决：五票一致「需修订后批准」。架构骨架（时间线 + 唤醒循环 + 瘦渠道适配器）成立，无推翻性发现；共 18 个阻断项全部可修，已归并为五大类并入设计 v0.2。**

---

## 一、阻断项归并（18 → 5 类）

### A. 治理与授权（security B1/B2/B4，arch B3）
- **G4 治理不旁路在 v0.1 不成立**：账本执行闸是 opt-in（只裁决显式 actionType），mem 写入/web 查询不过闸；share/message_out 路径零治理触点
- **授权记忆自铸循环**：心智持 memory 写权限 + GUARD_TEXT 把「授权」记忆当不可逆动作依据 → 被诱导可先写假授权再自我放行，绕过账本不变量
- **守卫缺位**：心智是独立 LLM 请求，宿主不会注入 twin-guard；渠道原话/网页内容直达提示词
- **v0.2 对策**：①治理点落在 dsh-mind 执行器内，主动 `ledger.check()` 留痕（不依赖 opt-in 闸）；②位阶显式化——对 master 动作免裁决仅留痕，对外/对生人触达受治理，无账本时保守挂起；③心智的 memory 写入禁止「授权」陈述类型（授权只能来自批准通道）；④唤醒提示词自注入守卫（守卫文本经 dsh-twin 服务面获取，合规于宪章 §3.1 禁运行时值导入）

### B. 执行器底座与工具面（arch B2，security B3）
- §4.2「act 工具面=分身预设工具」与 §4.3 白清单自相矛盾；且裸 LLM run 拿不到 preset 挂载点的工具行/人格卡/twin-guard（撞宪章 §3.6 per-agent 服务禁 app 层注入）
- **v0.2 对策**：写死方案 A——唤醒 run 经 typertGateway 在**临时无人会话**上复用 digital-twin 预设（工具行/人格卡/守卫/装配全部随 preset 到位，run 结束即弃）；移交协议唯一合法通道 = task_delegate

### C. 调度器本体与可靠性（sre B1–B4，test B1/B3）
- 调度器本体缺失（tick 载体/wake_at 原子性/恰好一次消费/重启重建/崩溃续命与弃单/并发模型/fail-safe 方向）
- **v0.2 对策**：新增调度器规格节——宿主 timer tick + wake_at 状态文件原子写 + rm-then-dispatch 恰好一次 + 重启从时间线尾部重建 + 崩溃弃单（无 FINAL wake 显式弃单、只续排程不续执行）+ 禁 in-step sleep + 续命归调度器（硬超时）；并发模型 P1 心智单飞 + reactive 排队 message 优先；全局 fail-safe 纪律（内部异常绝不击穿宿主、config 损坏 fail-safe 到「停」、watchdog 不得复活暂停态）

### D. 成本与防骚扰（cost B1–B3，security B5）
- share 防噪音纯靠提示词必然失守；pending 存在四条吞单路径；spend cap 空缺且无软硬两级；reactive「永不限速」可被高频消息变成烧钱泵
- **v0.2 对策**：①deliver 前 24h 指纹去重硬拒绝 + 投递状态机（pending/delivered/failed 可重发）+「永不 status ping」规范全文 + 中文写作规范对照表；②pending 不吞单条款（护栏触发不销账、恢复先排空）+ t=0 承诺话术 + 15 分钟超时兜底；③两级 cap（80% 软顶降级快模型 / 100% 硬顶停自发留反应性）+ reactive 合并窗口（60s 同渠道合并）+ 小时上限；④成本底账修正——deepseek 级 $0.18–0.46/日、Claude 级 $3.4–6.5/日（v0.1 照搬的"$1–2/小时"只在高档模型成立）

### E. 文档与契约修订（arch B1/B4，test B2/B3，sre 应改）
- 注册方向自相矛盾（§6.1 vs §6.2）→ 统一为**渠道侧惰性 ctx.get('dsh-mind') 晚注册重试**（宪章 §4 dsh-memory 范本）
- §6.3「渠道在时间线追加」字面违反宪章原则三 → 渠道调 mind API 注入，不直接写文件
- §8 自查失真（未实施却预勾选）→ 回退未勾选 + 补 §3.6 四条打包挂载纪律对照
- 契约六件套补齐：渠道注销、多渠道 schema、幂等键、观察积压语义、pending TTL、deliver 失败语义（状态机可重发）
- 时间线 schema v2：补 trigger/wakeId/usage/backoffLevel + schemaVersion + 必填 pin + 单一写路径 + 半行容错 + 滚动归档
- MindLlm port + 调度纯函数化（`collectDueMindTriggers(at)` 先例）+ scriptedMindLlm 桩 + 10 条确定性用例 + contract-guard 守卫清单

---

## 二、决策台账

### 已采纳默认（工程项，评审建议直采）
1. registerChannel 单向化：渠道侧惰性注册，mind 零渠道感知
2. 时间线访客不可见：Q3 建议升格硬规则；速览路由 sameOrigin 门禁（LESSONS #11）
3. message_out 复用渠道出站链（masking 生效）；web 查询过 maskTextSync
4. 生人投递默认挂起待批
5. 两级 spend cap：deepseek 级 $1/日、Claude 级 $5/日；80% 软顶/100% 硬顶
6. QUIET_HOURS 绑 IANA 时区（默认 Asia/Shanghai）、默认开启、旅行一键切换
7. THOUGHT_CAP 默认 = CAP（60s 旧值是 headlong 遗迹）
8. spend 计数持久化（重启不清零）；errored run ≠ idle；时间线滚动归档（默认 180 天）
9. 回归守卫：contract-guard.spec（菜单输出/时间线 schema/适配器契约/兄弟服务面四处接缝）；「core 升级 PR 必须带 contract-guard 全绿」流程门禁
10. 中文消息写作规范对照表（禁 AI 腔黑名单）入唤醒提示词

### 需主人拍板（战略项，已给建议默认）
| # | 问题 | 建议默认 |
|---|---|---|
| D1 | 唤醒执行器底座：方案 A（typertGateway 临时无人会话复用 digital-twin 预设）vs B（逐项补装清单） | A |
| D2 | 治理位阶：对 master 免裁决仅留痕；对外/生人触达受治理；无账本保守挂起 | 按建议 |
| D3 | spend cap 数字（deepseek $1/日、Claude $5/日） | 按建议，可改 |
| D4 | dsh-twin proactive.ts 主动触达并入 mind 的 share 函数（消除双主动源，涉 dsh-twin 上游） | 并入，P2 实施 |
| D5 | im-channel 上游适配器小改的排期授权（P2 前置） | 授权后 P2 启动 |

---

## 三、对 v0.1 的肯定（保持不变的骨架）

时间线 jsonl（否决常驻会话）、调度器掌钟（dispatcher-native scheduled wake）、
函数菜单（act/share/think/learn/recall/goals/idle）、瘦渠道适配器、新仓 dsh-mind
（Q1）、P1–P4 分期——五份评审全部认可，v0.2 不改骨架，只补机制与规格。
