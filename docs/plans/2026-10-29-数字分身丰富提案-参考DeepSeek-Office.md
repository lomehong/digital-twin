# 数字分身丰富提案——参考 DeepSeek-Office/DS Bot 的机制映射

> 日期：2026-10-29
> 参考：wyx135230/DeepSeek-Office v0.7.1（Apache-2.0 代码；基于 Fei2411/DeepSeek-Bot；
> Tauri 式插件壳内为 Three.js 正交视角 + Phaser 模拟；验证于 DSH 0.2.0-rc.2 / 0.2.1-rc.2）
> 原则：**不引入其团队系统**（DS Bot 与官方 agent-team 是并行范式），只吸收机制与体验设计，
> 落点全部映射到现有套件包（dsh-twin / dsh-mind / dsh-memory / dsh-ledger / dsh-task-board）。

## 一、DS Bot/Office 值得参考的机制清单（实测源码核验）

| # | 机制 | DS Bot 实现 |
|---|---|---|
| M1 | Bot = 长寿命 Session | 每个 Bot 是 DS Bot 工作区里的一个 dsh Session：独立 name/role/instructions/model/**权限预设**（Read only / Workspace / Full）/工作目录；群聊可统一成员权限 |
| M2 | 团队工具面 | `message_bot`（转交）、`create_bot`/`update_bot`（建/配 Bot）、`ask_user`（**非阻塞**提问卡：不阻塞其他 Bot） |
| M3 | 群聊协作语义 | 成员轮流发言、先读最新消息；`@Name` 转交回合；`[PASS]` 安静（无可新增就明说不发言）；每成员每群一个**隐藏 Session**（群不读私聊）；`+引用聊天` 作为上下文注入 |
| M4 | 分层记忆 | 每 Bot 跨会话笔记 + 团队共享一份（两份独立） |
| M5 | Secrets 卡片 | Bot 要 API key 时发卡片进自己的聊天，**Bot 永远看不到值**（宿主代管） |
| M6 | 长对话自管 | Bot Session 关掉 dsh 自动 compaction，按模型窗口行自管（可用窗口 = 窗口 − 回复预留，硬线 95%） |
| M7 | 会话活动→可视化 | 实时显示会话「读什么/编辑什么/跑什么」；文件编辑显示文件名与 +N −M；头顶气泡 + 紧凑活动卡；会议室墙屏 = 完整群对话 |
| M8 | 休闲/存在系统 | 咖啡/阅读/街机/午餐/调饮/拉伸；衣柜换装、季节装扮、Poke 交互；本地时间→阳光/晚灯；手机层（随处私聊/群聊/网页） |
| M9 | 周报 | 每周一早上的可分享周报图片，历史留本机 |

## 二、数字分身现状对照（已具备 vs 缺口）

已具备（不需要从 Office 学）：长寿命身份（数字分身/四卡）、共享记忆（dsh-memory）、
治理审批（dsh-ledger）、任务看板（dsh-task-board）、非阻塞审批（ledger 卡片）、
时间线（dsh-mind）、存在体（Being 呼吸/状态色/请求涟漪）、状态坞、周报素材（recap）。

**缺口**（按价值排序）：

1. **会话活动→存在体行为**（M7 的精神）：Being 目前只反映「忙/睡/请求」三态；
   分身在做什么（读哪个文件/跑什么命令/改了多少行）不可见
2. **子代理的持久身份与权限预设**（M1/M5 的精神）：agent-team 成员/子代理
   缺「独立权限预设 + 工作目录 + 密钥代管卡」的成套范式
3. **群组协作语义**（M3）：agent-team 群组的回合转交/安静语义未确认成文
4. **办公室级可视化**（M7/M8 本体）：把「分身 + 团队 + 任务」渲染成场景——
   大工程，但数据源全部现成（dsh-mind 时间线 / dsh-task-board / ledger 审批 / agent-team 状态）

## 三、落地提案（P0 → P2）

### P0 · 存在体行为映射（dsh-mind client，~1-2 天）
- 数据：dsh-mind 时间线已有 tool/step 事件；agent-team/子代理事件经 mind 已可见
- 行为映射（参考 Office activity cards 语义）：
  - `tool/call(read)` → Being 微字幕「正在读 <文件>」+ 呼吸加速
  - `tool/call(命令)` → 「正在运行 <命令>」+ 轻微涌动
  - 审批请求 → 现有涟漪 + 请求角标（已有）
  - turn/end → 回归平静呼吸
- 交互增强（参考 poke/换装）：点击 Being 出现「摸头/喂咖啡」等轻交互与状态台词
  ——纯前端，无新依赖

### P1 · 子代理持久身份范式（agent-team 成员配置，~2-3 天）
- 参照 M1/M5 给 agent-team 成员补成套字段：权限预设（Read only/Workspace/Full）、
  工作目录绑定（敏感目录拒绝——DS Bot 同款校验）、密钥代管卡（宿主代管、
  成员只见卡片不见值）
- 群组协作语义成文：@转交 / [PASS] / 每成员隐藏会话，写入 agent-team 使用手册

### P2 · 数字分身办公室（可视化层，~1-2 周或独立立项）
- 定位：**渲染者不做聚合**（宪章先例：task-board 活动区段）——新建一个可视化插件或
  dsh-twin 的 client 页，数据全部从既有服务读取：
  - 成员与状态：agent-team 花名册 + 各自活跃度
  - 分身状态：dsh-mind 时间线（读/写/运行/审批）
  - 任务：dsh-task-board 状态条
  - 审批：ledger 待批
- 场景映射（Office 语义 → 分身语义）：
  - 工位 = 各成员日常会话位置；会议室 = agent-team 群组会话（墙上屏 = 群消息流）
  - 咖啡吧/阅读角 = 分身 learn/think 的休闲动画；放映室 = 周报/回顾回放
  - 时光照明 = 沿用 Being 的静音时段呼吸变化
- 技术形态：Three.js 正交视角即可（Phaser 可选）；参考其「程序化建筑 + GLB 角色」
  的资产策略（资源随包捆绑、离线可用）

### 明确不做
- DS Bot 团队壳本体（Bot=Session/群聊/create_bot 等）——与官方 agent-team 重叠，
  引入即双团队范式（主人已拍板不要）
- Office 的 Updater/版本检查机制（本套件已有 install-all/发布流程）

## 四、风险与边界

- P2 的 3D 渲染常驻会占浏览器资源（Office 提供 Quiet motion 降载开关——照搬）
- P0/P1 不依赖 Office 代码本身（只借语义），无许可证负担；P2 若直接复用其
  场景资产需遵守 NOTICE/资产许可（代码 Apache-2.0，Mochi 名字/形象/音效 © 保留——
  分身办公室应使用自有形象：数字分身 Being 的视觉延展正好是自有 IP）
