# dsh 运行时升级检查清单（数字分身套件）

> 2026-09-16 事故复盘产物：dsh 0.1.2-alpha.x → 0.1.6-alpha.1 升级时，
> `@deepseek-ai/dsh-workflow-worker-thread` 被移除，仓库内预设模板与
> 手工快照预设仍引用旧包名 → 上游 agent-presets 把整份组合判为不可挂载
> → 挂载徽章失败、绑定了该预设的会话恢复报错。
> 本清单 + `scripts/check-compat.mjs` 把"升级会不会坏"变成机器可判定。

## 标准升级流程

### 0. 升级前基线
```bat
node scripts\check-compat.mjs
```
必须 **0 error** 才开始升级。把当时的输出存档（方便升级后 diff 出"新坏了什么"）。

### 1. 升级 dsh 核心（应用内"升级到最新"）后立即重跑
```bat
node scripts\check-compat.mjs
```
ERROR 的三种形态与处置：

| 形态 | 含义 | 处置 |
|---|---|---|
| `组合 …: 行 name: '…' 在解析链上不存在` | 组合/预设行引用了被移除/更名的宿主包 | 对齐新版 shipped standard（在 `<home>\profiles\node_modules\@deepseek-ai\dsh-agent-presets\presets\standard\agent.cordis.yml`）改模板行；**改模板必须 bump 物化器版本戳**（见下） |
| `运行时 …: import '…' 不存在` | 某包 lib/ 硬 import 了宿主已移除的具名导出/包 | 迁移到新 API。范式见 `dsh-remote/src/index.ts`（settings: `ctx.inject(['settings']) → settings.installSection(...)`）；改完 `npm run build && npm test` |
| `预设漂移: …` | 模板与已物化副本不同步 | 同步后 bump 物化器版本戳并重启 dsh，或手工同步挂载副本 |

### 2. 改过预设模板 = 必 bump 版本戳
- dsh-twin：`src/index.ts` 的 `PRESET_VERSION`（当前 `'12'`）
- architect（另一仓库）：`dsh-architect/src/materialize.ts` 的 `PRESET_VERSION`（当前 `'2'`）

不 bump 的话物化器看到戳一致就跳过，修复永远发不到已物化副本
——2026-09-16 时 architect 挂载副本是手修的，坏模板全靠"戳碰巧相等"才没写回。

### 3. 重建 + 测试 + 重装
```bat
scripts\build-all.bat
scripts\test-all.bat
install-all.bat            rem 内置 check-compat 闸门，审计不过会中止安装
```
发布通道：各子模块仓库发 GitHub Release → `install-all.bat -Release`。

### 4. 挂载验证
三个预设逐一验证可挂载（`standard-yuyi` / `digital-twin` / `architect`）：
- 任意 Cordis 会话经 `agentPresets.standingKeyFor(id)` 校验；或
- 直接用各预设开新会话，确认工具清单（present / workflow / yuyi_* / memory_* …）。

### 5. 已知的手工快照
`standard-yuyi`（`$DSH_HOME\.agent-presets\standard-yuyi\`）**没有仓库源**，
是 shipped standard 的手工副本 + 御驿/记忆工具行 + Windows shell 门硬编码。
它的防复发兜底就是 check-compat 的"shipped standard 漂移检测"：
升级后如果 shipped standard 增删了行，这里会报 `缺少来源行` / `多出来源外行`。

## 审计脚本本身
- 位置：`scripts/check-compat.mjs`（架构师套件另有一份副本，改动需两仓同步）
- 接入点：`install-all.bat` 内嵌安装器在安装收尾阶段强制执行
- 判定：0 warning～若干 warning 通过；任何 ERROR 中止
- 白名单：预设漂移的"多出来源外行"在 SUITES 配置的 `allowExtras` 里维护
  （物化器按安装状态追加的可选行都登记在内）
