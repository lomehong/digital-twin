# dsh 0.1.7-alpha.2 迁移实施手册（数字分身套件）

> 状态：**待实施**（前置条件：dsh 桌面运行时升级到 0.1.7-alpha.2，当前为 0.1.6-alpha.2）
> 依据：dsh-v0.1.6-alpha.2 → dsh-v0.1.7-alpha.2 全量差异审计（1461 commits）+ 宿主源码契约提取
> 关联：`docs/suite-charter.md`（v1.1+）、`docs/task-board-decisions.md`

## 0. 兼容性结论速览

- ✅ 不变（零迁移）：tools/pre|post-execute waterfall（含 PreToolDecision/exec 字段）、
  客户端槽位注册表全部条目、`--dsw-alias-*` 令牌、StateDot/Pill、typert 远程契约、
  客户端模块契约（apply+inject）、会话 API（create/rename/prompt/list/follow/page）、
  webServer、事件白名单、`ctx.effect`、cordis 4.0.4（纯新增）
- 🔴 三组破坏：**设置系统重写**（installSection/get/register 移除 → config-editor 条目 +
  describe/update/mutate；客户端 settingsScope → configForms）、**agent-presets 目录发现
  移除**（.agent-presets/<id>/ 不再被读取 → 预设改为 @dsh-agent-preset 声明行）、
  **dsh-settings-file / dsh-agent-presets 包删除**
- 🟡 小项：`ToolCallOwnerProps` 新增必需 `useDisclosure`（套件现无该槽位注册者，不影响）；
  fork atSeq 语义变更（套件未用）；`setSubagentCatalogOpen/refreshSubagents` 移除（未用）

## 1. 新设置契约（黄金样例 = packages/web/web-search-deepseek 的 0.1.6→0.1.7 官方迁移）

**0.1.6 旧形态**：
```ts
export function apply(ctx: Context, config: Config): void {
  let current: () => Config = () => config
  ctx.inject(['settings'], (sctx) => {
    sctx.settings.installSection(ctx, NS, Config, config, {
      setSource: (source) => { current = source }, onChange: () => {},
    })
  })
}
```

**0.1.7 新形态（完整）**：
```ts
import type { Volatile } from '@deepseek-ai/cordis'

export interface Config {
  hub: Volatile<string>            // 热更字段加 .volatile()；机密加 .role('secret').volatile()
  tokenEnv: Volatile<string>
  device: Volatile<string>
  replyTimeoutMs: Volatile<number>
}

export function apply(ctx: Context, config: Config): void {
  // 读配置：config.hub.get()——loader 把新快照原位写入引用，无需重连注册
  // 需要变更回调时：ctx.on('loader/volatile-update', paths => …)
}
```

- **设置页自动生成**：0.1.7 由 schema 直接投影（ns = profile 行 `- id:`，即插件包名）；
  不再需要自绘设置区块（有特殊需要时 `ctx.inject(['settings'], c => c.effect(() =>
  c.settings.configure({ auto: false }, ctx.fiber)))` 退出自动页）
- **宿主侧写配置**：`ctx.settings.update(ns, patch, expectedRevision?)` 仍存在 ✓
  （im-channel 的 memoryAssemblePerTurn 开关路由可用）；冲突抛
  `SettingsConflictError(code='SETTINGS_CONFLICT')`；变更事件 `settings/document-updated`
- **describe**：`settings.describe({redactSecrets?})` 取全部条目快照（替代 get(ns)）

## 2. 客户端 configForms（替代 settingsScope）

```ts
export const inject = ['slots', 'locale', 'configForms']   // configForms 由 ui-settings 浏览器半提供

export function apply(ctx: ClientContext): void {
  const form = ctx.configForms.get('<profile 行 id>')    // 即旧 NS 字符串
  // ConfigForm<T>: getSnapshot()（status/value/base/user/revision/writable/mode）
  //              subscribe(l) / set(field, value) / unset(field) / mutate(ops, expectedRevision?)
  ctx.configForms.whileServed(['<ns>'], (served) => { /* 服务在场时注册 UI */ })
}
```
参考实现：`packages/client/ui-settings-agent-loop/src/client/index.ts`（0.1.7 树内完整样例）。

## 3. 预设发布（agent-preset 声明行）

- 形态：bundle patch yml 里 `- insert: - id: preset-x / name: '@deepseek-ai/dsh-agent-preset' /
  config: { id, name?, description?, order?, plugins: [行数组] }`；加入包 `dsh.bundle.patch` 列表
- `plugins` 行 = Loader EntryOptions（id/name/config/disabled），`disabled` 支持 `!!js` 表达式
  （可引用 ctx——条件行机制）；提供 service 的行必须在 `group: true, isolate: {...}` 组内
- 默认预设：registry 行 `config: { default: '<preset-id>' }`（不再走 settings）
- **`.agent-presets/<id>/` 目录发现已死**：0.1.7 不再读取该目录——dsh-twin 的
  `materializePreset` 必须重做（见 §5-T2）
- 参考实现：`packages/bundle/web-app/presets/standard.patch.yml`（0.1.7 树内完整样例）

## 4. 逐仓迁移步骤

### T1 dsh-yuyi（settings + settingsScope + 去 dsh-settings-file）
1. `service.ts`：`static Config` 四字段（hub/tokenEnv/device/replyTimeoutMs）加
   `.volatile()`，tokenEnv 加 `.role('secret')`；构造器接收的 config 改 volatile 引用
   读取（新增 `readField` 助手：`config[k]?.get?.() ?? config[k]` 双运行时兼容）；
   **删除 installSection 块**；重连钩子改挂 `ctx.on('loader/volatile-update', …)`
2. `client/index.ts`：`inject` 中 `settingsScope` → `configForms`；token 设置区块
   （YuyiSettingsSection）在 0.1.7 由 schema 自动表单替代——若保留自绘区块，
   经 `ctx.configForms.get('yuyi')` 读写（参考 ui-settings-agent-loop 样例）
3. `platform-types.d.ts`：settingsScope 声明 → configForms 声明
4. `package.json`：移除 devDep `@deepseek-ai/dsh-settings-file`（0.1.7 已删包）；
   peer/devDeps 升 0.1.7-alpha.2
5. 验证：130/130 + 构建

### T2 dsh-twin（预设机制 + 设置）
1. **预设发布**：新增 `presets/digital-twin.patch.yml`——`- insert: [{ id: preset-digital-twin,
   name: '@deepseek-ai/dsh-agent-preset', config: { id: 'digital-twin', name: '数字分身',
   order: 2, plugins: [<现有 agent.cordis.yml 全部行原样迁入>] } }]`；`package.json`
   `dsh.bundle.patch` 追加该文件；条件行（tool-memory/tool-yuyi/tool-computer 仅装了才加）
   改为 `disabled: !!js "<安装探测表达式>"`（0.1.7 支持 !!js 引 ctx）
2. **materializePreset 退役**：保留函数但改为仅在 0.1.6 运行时探测命中时执行
   （双运行时过渡）；或直接删除并要求 0.1.7（推荐，套件已随 dsh 节奏走）
3. **设置**：twin 的设置向导（index.tsx 自绘）改 configForms 读写（entryId='dsh-twin'）；
   宿主 persona/knowledge 种子写入路径若经 settings 需同步
4. `AgentPreset.path/trust` 读取移除（grep 确认套件未用 ✓）

### T3 im-channel（settings.get + installSection）
1. `login-api.readSettingsSection`：`settings.get(NS)` 已移除 → `settings.describe()` 取
   快照后按 ns 过滤取 value；或经 configEditor 条目配置
2. `installSection` 块（plugin/index.ts:436）迁移；`ctx.settings.update(NS, patch)` 保留 ✓
   （memoryAssemblePerTurn 开关路由继续可用）；变更事件改挂
   `settings/document-updated`（原 onChange 语义）

### T4 dsh-redact（settings.register）
- `settings.register(NS, Config, {base})` 0.1.7 无对应 → 改 describe()/update()/
  replace() 组合；`scope.watch` 改 `settings/document-updated`；客户端设置 Tab 同步

### T5 全套 devDeps
- 各仓 `@deepseek-ai/dsh-*` devDeps 升 `0.1.7-alpha.2`（npmjs 已发布 ✓；npmmirror
  可能滞后，必要时 `--registry=https://registry.npmjs.org`）；`dsh-settings-file`、
  `dsh-agent-presets` 引用删除；`dsh-config-editor`/`dsh-agent-preset(-registry)` 按需新增
- `.volatile()`/configForms 迁移后跑各仓全量测试

## 5. 已知边界与风险

- **双运行时过渡**：迁移后的代码以 0.1.7 API 为准，在 0.1.6 运行时上会失败
  （settings/预设两块）。建议：套件升级与运行时升级**同一窗口内切换**，
  或维持 0.1.6 分支标签过渡
- **reader 插件（dsh-pages）**：其 `harness` 内建 RPC 在 0.1.7 亦不存在——
  与本套件无关的独立适配项（已兜底不阻断启动）
- **「按策略」host 回归**：仍需宿主侧策略命中标注（host-runner 已跳过并注释）

## 6. 验收清单（迁移完成后逐项过）

- [ ] 六仓测试全绿（yuyi/twin/im-channel/redact/memory/task-board/ledger/regression）
- [ ] `node scripts/check-compat.mjs` 0 error
- [ ] 重启后：分身人格卡保存→生效闭环、看板执行+task_report、yuyi 面板、IM 渠道、
      记忆读写、设置各 Tab 可见可改可热更
- [ ] 宪章登记册销账（本手册 §4 各项）
