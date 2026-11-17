#!/usr/bin/env node
/**
 * dsh 升级兼容审计（check-compat）——2026-09-16 事故防复发机制。
 *
 * 事故回顾：dsh 0.1.6-alpha.1 移除 @deepseek-ai/dsh-workflow-worker-thread 后，
 * 套件仓库里的 agent 预设模板仍引用旧包名 → 上游 agent-presets 把整份组合判为
 * 不可挂载 → 挂载被拒 / 会话恢复失败。同类风险还有三族：
 *   ① 组合行引用的包在目标解析链上不存在（本审计的主检查）；
 *   ② 构建产物 import 了已被宿主移除/更名的 @deepseek-ai/* 包
 *      （model-failover / plugin-manager 的 dsh-settings 死 import 即此类）；
 *   ③ 预设模板与已物化副本漂移，且物化器版本戳未 bump，修复永远发不下去。
 *
 * 本脚本做三件事（全部只读，绝不修改任何文件）：
 *   A. 组合行审计 —— 扫描仓库内所有 cordis.patch.yml / presets/*.cordis.yml
 *      （以及 $DSH_HOME/.agent-presets 下已物化的预设），取每行 name: 引用的包，
 *      按 Node 解析链验证存在性（自引 → 包内 node_modules → profile node_modules
 *      → 宿主镜像 <home>/profiles/node_modules/@deepseek-ai）。
 *   B. 运行时 import 审计 —— 扫描各包 lib/**\/*.js 对 @deepseek-ai/* 的
 *      import/require 动态导入说明符，验证目标包在解析链上存在。
 *   C. 预设漂移审计 —— 模板 vs 已物化副本（模板每个 name: 必须出现在副本中，
 *      否则 = 副本落后：bump 物化器版本戳并重启）；手工维护的预设（如
 *      standard-yuyi）与 shipped standard 按 name: 集合比对，多出的行须在白名单内。
 *
 * 用法：
 *   node check-compat.mjs [--repo <套件仓库根>] [--home <DSH_HOME>] [--profile web]
 * 退出码：0 = 通过（警告不阻塞）；1 = 存在 ERROR 级问题。
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// ────────────────────────── 参数 ──────────────────────────
const scriptDir = dirname(fileURLToPath(import.meta.url))
function argOf(flag, fallback) {
  const i = process.argv.indexOf(flag)
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback
}
// Desktop home layouts: newer releases use dsh-desktop\home, legacy used
// dsh-desktop-app-data\home. 两者可能同时存在且只有一个是活的——按固定顺序探测会
// 读到过期目录（2026-11 实测：dsh-desktop\home 停在 9 月，活动 home 是 app-data）。
// 因此优先取 profiles/<profile>/package.json 最新的那个；需要精确控制时用 --home。
const PROFILE = argOf('--profile', process.env.DSH_PROFILE ?? 'web')
const desktopHomes = [
  join(process.env.LOCALAPPDATA ?? '', 'dsh-desktop', 'home'),
  join(process.env.LOCALAPPDATA ?? '', 'dsh-desktop-app-data', 'home'),
]
function pickDesktopHome() {
  const existing = desktopHomes.filter((p) => existsSync(p))
  if (existing.length === 0) return undefined
  let best = existing[0]
  let bestTime = -1
  for (const candidate of existing) {
    let time = -1
    try { time = statSync(join(candidate, 'profiles', PROFILE, 'package.json')).mtimeMs } catch { time = -1 }
    if (time > bestTime) { best = candidate; bestTime = time }
  }
  return best
}
const HOME = resolve(argOf('--home', process.env.DSH_HOME ?? (pickDesktopHome() ?? join(process.env.USERPROFILE ?? '.', '.dsh'))))
const REPO = resolve(argOf('--repo', dirname(scriptDir)))

const errors = []
const warnings = []
// 组合/预设行的 name: 只可能是包名（可带子路径）。YAML 里还有大量同名的普通字段
// ——预设显示名（如「安全工程师」）、工具名等——它们不是包，不能当行解析。若不过滤，
// 闸门会把显示名判成「解析链上不存在」并报 ERROR（2026-11 实测安全工程师预设）。
const ROW_SPEC_RE = /^(@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*(\/[a-z0-9._-]+)*$/
const error = (msg) => errors.push(msg)
const warn = (msg) => warnings.push(msg)

// ─────────────────── 解析链根（按优先级） ───────────────────
// 注意：这些根都是 node_modules 层；@scope/pkg 由 resolveRowName 用完整包名拼接。
const mirrorScope = join(HOME, 'profiles', 'node_modules')
const profileNodeModules = join(HOME, 'profiles', PROFILE, 'node_modules')
const homeNodeModules = join(HOME, 'node_modules')
// 宿主本体（dsh 应用自身）的包根。桌面版把 @deepseek-ai/* 平铺在 <home>/../node/node_modules
// 下；老布局才嵌在 dsh/node_modules 里。<home>/profiles/node_modules 的镜像链接指向后者，
// 在桌面版上会全部悬空（2026-11 实测：315 条镜像 314 条悬空）——只认镜像会把宿主自带的行
// 全判成「包不存在」，让兼容闸门在升级后误报 20+ 条 ERROR。两个布局都收，顺序：profile →
// 宿主平铺 → 宿主嵌套 → 镜像。
const hostNodeModules = [
  join(HOME, '..', 'node', 'node_modules'),
  join(HOME, '..', 'node', 'node_modules', '@deepseek-ai', 'dsh', 'node_modules'),
].filter((p) => existsSync(p))

/** 检查包根存在且带 package.json。 */
function pkgOk(pkgDir) {
  return existsSync(join(pkgDir, 'package.json'))
}

/**
 * 解析一个组合行 name:（可含 ./subpath）。
 * @param {string} name        如 '@deepseek-ai/dsh-tools'、'dsh-yuyi/tools'
 * @param {string[]} extraRoots 包自身 node_modules 等优先根
 * @returns {{ ok: boolean, via: string, subpath: string | null }}
 */
function resolveRowName(name, extraRoots = []) {
  const segments = name.split('/')
  const pkgName = segments[0].startsWith('@') ? segments.slice(0, 2).join('/') : segments[0]
  const subpath = segments.slice(pkgName.split('/').length).join('/')
  const roots = [
    ...extraRoots,
    profileNodeModules,
    homeNodeModules,
    ...hostNodeModules,
    pkgName.startsWith('@deepseek-ai/') ? mirrorScope : null,
  ].filter(Boolean)
  for (const root of roots) {
    const pkgDir = join(root, pkgName)
    if (pkgOk(pkgDir)) {
      if (subpath) {
        const ok = exportsHasSubpath(pkgDir, `./${subpath}`)
        return { ok, via: pkgDir, subpath: subpath || null }
      }
      return { ok: true, via: pkgDir, subpath: null }
    }
  }
  return { ok: false, via: '', subpath: subpath || null }
}

/** package.json exports 是否声明某子路径（宽松：无 exports 视为通过）。 */
function exportsHasSubpath(pkgDir, subpath) {
  try {
    const manifest = JSON.parse(readFileSync(join(pkgDir, 'package.json'), 'utf8'))
    if (!manifest.exports) return true
    const entry = manifest.exports[subpath]
    if (entry === undefined) return false
    return true
  } catch {
    return true // manifest 不可读交由 pkgOk 判断，这里不重复报错
  }
}

// ─────────────────── A. 组合行审计 ───────────────────
const ROW_NAME_RE = /^\s*(?:-\s+)?name:\s*['"]?([^'"\n]+?)['"]?\s*$/gm
function auditCompositionFile(file, label, extraRoots = []) {
  let text
  try {
    text = readFileSync(file, 'utf8')
  } catch (e) {
    warn(`${label}: 无法读取（${e.message}）`)
    return
  }
  ROW_NAME_RE.lastIndex = 0
  let m
  const seen = new Set()
  while ((m = ROW_NAME_RE.exec(text)) !== null) {
    const name = m[1].trim()
    if (name === 'cordis:group' || !ROW_SPEC_RE.test(name) || seen.has(name)) continue
    seen.add(name)
    const r = resolveRowName(name, extraRoots)
    if (!r.ok) {
      // 仓库内自引行（包目录在 REPO 下、带 package.json + cordis.patch.yml）且未部署：
      // 属"本地开发包"的已知状态，降级为 WARN；其余解析失败保持 ERROR（2026-09-16 事故类）。
      const tail = name.split('/').pop()
      const localDir = join(REPO, tail)
      const selfReferenced = existsSync(join(localDir, 'package.json')) && existsSync(join(localDir, 'cordis.patch.yml'))
      if (selfReferenced) {
        warn(`${label}: 行 name: '${name}' 当前未部署（仓库内本地包，link:/Release 部署后生效）`)
      } else {
        error(`${label}: 行 name: '${name}' 在解析链上不存在（profile=${PROFILE}）—— 升级后该行会让整份组合拒绝挂载`)
      }
    }
  }
}

/** 仓库内组合文件清单（不动 node_modules；深度 ≤3）。 */
function findCompositionFiles(root) {
  const out = []
  const walk = (dir, depth) => {
    if (depth > 3) return
    let entries
    try {
      entries = readdirSync(dir)
    } catch {
      return
    }
    for (const entry of entries) {
      if (entry === 'node_modules' || entry.startsWith('.')) continue
      const full = join(dir, entry)
      let st
      try { st = statSync(full) } catch { continue }
      if (st.isDirectory()) {
        walk(full, depth + 1)
      } else if (entry === 'cordis.patch.yml' || (entry.endsWith('.cordis.yml') && full.includes(join(root, 'presets')))) {
        out.push(full)
      }
    }
  }
  walk(root, 0)
  return out
}

// ─────────────────── B. 运行时 import 审计 ───────────────────
const IMPORT_RES = [
  /from\s+['"](@deepseek-ai\/[a-z0-9-]+(?:\/[a-z0-9.-]+)*)['"]/g,
  /import\(\s*['"](@deepseek-ai\/[a-z0-9-]+(?:\/[a-z0-9.-]+)*)['"]\s*\)/g,
  /require\(\s*['"](@deepseek-ai\/[a-z0-9-]+(?:\/[a-z0-9.-]+)*)['"]\s*\)/g,
]
function walkJsFiles(dir, out = []) {
  let entries
  try { entries = readdirSync(dir) } catch { return out }
  for (const entry of entries) {
    if (entry.endsWith('.map') || entry.endsWith('.d.ts')) continue
    const full = join(dir, entry)
    let st
    try { st = statSync(full) } catch { continue }
    if (st.isDirectory()) walkJsFiles(full, out)
    // lib/client.js（及 client/ 目录）是浏览器半产物：由页面 ModuleLoader 解析，
    // 不经 Node 镜像（如 dsh-client-ui-primitives 这类前端内置模块），跳过 Node 解析审计
    else if (entry.endsWith('.js') && !isClientArtifact(full, dir)) out.push(full)
  }
  return out
}
function isClientArtifact(file, libDir) {
  if (file.toLowerCase() === join(libDir, 'client.js').toLowerCase()) return true
  return file.toLowerCase().startsWith(join(libDir, 'client').toLowerCase() + '\\')
    || file.toLowerCase().startsWith(join(libDir, 'client').toLowerCase() + '/')
}
function auditRuntimeImports(pkgDir, label) {
  const libDir = join(pkgDir, 'lib')
  if (!existsSync(libDir)) return
  const ownNodeModules = join(pkgDir, 'node_modules')
  const files = walkJsFiles(libDir)
  const seen = new Set()
  for (const file of files) {
    const text = readFileSync(file, 'utf8')
    for (const re of IMPORT_RES) {
      re.lastIndex = 0
      let m
      while ((m = re.exec(text)) !== null) {
        const spec = m[1]
        const pkgName = spec.split('/').slice(0, 2).join('/')
        if (seen.has(pkgName)) continue
        seen.add(pkgName)
        const inOwn = pkgOk(join(ownNodeModules, pkgName))
        const inMirror = pkgOk(join(mirrorScope, pkgName))
        const inProfile = pkgOk(join(profileNodeModules, pkgName))
        const inHost = hostNodeModules.some((root) => pkgOk(join(root, pkgName)))
        if (!inOwn && !inMirror && !inProfile && !inHost) {
          error(`${label}: 运行时 import '${pkgName}' 不存在于宿主镜像/解析链 —— 启动即 ERR_MODULE_NOT_FOUND（若宿主已移除该包，需迁移代码）`)
        }
      }
    }
  }
}

// ─────────────────── A2. 代码内预设行审计 ───────────────────
// 预设从 YAML 迁到代码（agentPresets.register(presetDefinition())）之后，A 段只能看到
// 仓库里剩下的 YAML 组合文件——预设行真正的来源是 TS 里的行字面量，A/B/C 三段会全绿，
// 而生产环境整份预设仍可能不可挂载。2026-11 实测事故：dsh 0.2.2 把
// `@deepseek-ai/dsh-tool-subagent-control/list-agents` 收回主入口，行只存在于
// dsh-twin/src/index.ts 里 → 该行 never started → 数字分身预设整份被拒。
// 本段扫 src（无 src 时扫 lib）里的 `{ id: 'row', name: '<spec>' }` 字面量，按同一
// 解析链核对包与 exports 子路径。运行时按可解析性 gating 的条件行需在原文件行上方
// 标注 `preset-row:conditional`，命中时降级为 WARN（提示确认 gating 真的生效）。
const CODE_ROW_RE = /\{\s*id:\s*['"]([^'"]+)['"]\s*,\s*name:\s*['"]([^'"]+)['"]/g
const CONDITIONAL_MARKER = 'preset-row:conditional'

/** 包内 src/lib 的源码文件（跳过测试、类型声明、浏览器半产物）。 */
function codeRowFiles(dir, out = []) {
  let entries
  try { entries = readdirSync(dir) } catch { return out }
  for (const entry of entries) {
    if (entry === 'node_modules' || entry.startsWith('.')) continue
    const full = join(dir, entry)
    let st
    try { st = statSync(full) } catch { continue }
    if (st.isDirectory()) {
      if (entry === 'client' || entry === 'tests' || entry === '__tests__') continue
      codeRowFiles(full, out)
      continue
    }
    if (/\.(ts|tsx|mts|cts|js|mjs|cjs)$/.test(entry) && !/\.(d\.ts|test\.(ts|tsx|js)|spec\.(ts|tsx|js))$/.test(entry)) out.push(full)
  }
  return out
}

function auditPresetCodeRows(pkgDir, label) {
  const srcDir = join(pkgDir, 'src')
  const libDir = join(pkgDir, 'lib')
  const root = existsSync(srcDir) ? srcDir : (existsSync(libDir) ? libDir : null)
  if (root === null) return
  for (const file of codeRowFiles(root)) {
    let text
    try { text = readFileSync(file, 'utf8') } catch { continue }
    CODE_ROW_RE.lastIndex = 0
    let m
    while ((m = CODE_ROW_RE.exec(text)) !== null) {
      const spec = m[2].trim()
      if (spec === 'cordis:group' || !ROW_SPEC_RE.test(spec)) continue
      const rowLabel = `${label} 行 ${m[1]} (${spec})`
      const conditional = text.slice(Math.max(0, m.index - 400), m.index).includes(CONDITIONAL_MARKER)
      const resolved = resolveRowName(spec, [join(pkgDir, 'node_modules')])
      if (resolved.ok) continue
      if (conditional) {
        warn(`${rowLabel}: 条件行，当前解析链上不可解析 —— 运行时应按可解析性跳过（确认 gating 真实生效，勿只按“包已安装”判定）`)
      } else {
        error(`${label}: 预设行 name: '${spec}'（${file.replace(REPO, '')}）在解析链上不可解析 —— 该行会让整份预设挂载被拒（never started）`)
      }
    }
  }
}

// ─────────────────── C. 预设漂移审计 ───────────────────
function rowNames(file) {
  const text = readFileSync(file, 'utf8')
  const names = new Set()
  ROW_NAME_RE.lastIndex = 0
  let m
  while ((m = ROW_NAME_RE.exec(text)) !== null) {
    const name = m[1].trim()
    if (name !== 'cordis:group') names.add(name)
  }
  return names
}
const userPresetsRoot = join(HOME, '.agent-presets')
function auditPresetDrift(spec) {
  const mountedFile = join(userPresetsRoot, spec.mountedId, 'agent.cordis.yml')
  if (!existsSync(mountedFile)) {
    warn(`预设漂移: ${spec.mountedId} 未物化（${mountedFile} 不存在），跳过`)
    return
  }
  const sourceFile = spec.templateFile ?? spec.shippedStandardFile
  if (sourceFile !== undefined && !existsSync(sourceFile)) {
    warn(`预设漂移: 来源模板不存在（${sourceFile}）——0.1.7 起预设改为编程注册/宿主 bundle patch，漂移审计跳过（行覆盖改由包内单测保证）`)
    return
  }
  const mounted = rowNames(mountedFile)
  const sourceNames = rowNames(sourceFile)
  for (const name of sourceNames) {
    if (!mounted.has(name)) {
      error(`预设漂移: ${spec.mountedId} 缺少来源行 name: '${name}'（来源=${spec.templateFile ? '仓库模板' : 'shipped standard'}）—— 模板已演进但副本未重物化：bump 物化器 PRESET_VERSION 后重启，或手工同步`)
    }
  }
  const allow = new Set(spec.allowExtras ?? [])
  for (const name of mounted) {
    if (!sourceNames.has(name) && !allow.has(name)) {
      error(`预设漂移: ${spec.mountedId} 多出来源外行 name: '${name}' 且不在白名单 —— 确认是有意增量（加入 allowExtras）还是残留`)
    }
  }
}

// ─────────────────── D. 宿主服务级 invoke 契约审计 ───────────────────
// 2026-11-16 事故防复发：宿主 0.2.2-rc.3 把 InvokeRemoteRequest.peer 升为必填
// （"every carrier and in-process caller names it explicitly"），而既有审计只对比
// wire 面产物哈希——wire 路径由载体自动补 peer，哈希一致、套件进程内调用全灭。
// 服务级契约（插件进程内 typertGateway.invoke 的请求形状）必须单独审计：
//  D1. 读已装宿主 InvokeRemoteRequest 的必填字段集与核心版本，与基线文件
//      （scripts/host-invoke-contract.baseline.json）比对——漂移 = WARN
//      （宿主自愈升级绕过人工闭环时，install-all/check-compat 闸门会带出提醒）。
//  D2. 宿主要求必填字段（如 peer）而套件内消费 typertGateway 的包 lib 无任何
//      该字段装配痕迹 → ERROR（v0.10.4 事故形态：包裹装层整层缺失）。
//      逐调用点覆盖由各包单测保证，本段只拦整层缺失。
const INVOKE_TYPES_RE = /export interface InvokeRemoteRequest \{([\s\S]*?)\n\}/
const dshInstallRoot = dirname(HOME) // app-data 根（HOME=app-data\home）
const dshBundledScope = join(dshInstallRoot, 'node', 'node_modules', '@deepseek-ai', 'dsh', 'node_modules')
function resolveHostPkg(name) {
  const candidates = [
    join(mirrorScope, name),
    join(profileNodeModules, name),
    join(dshBundledScope, name),
  ]
  for (const dir of candidates) {
    if (pkgOk(dir)) return dir
  }
  return null
}
function readCoreVersion() {
  try {
    const v = readFileSync(join(dshInstallRoot, 'last-core-version'), 'utf8').trim()
    if (v !== '') return v
  } catch { /* 回落 dsh 元包版本 */ }
  try {
    return String(JSON.parse(readFileSync(join(dshBundledScope, '..', 'package.json'), 'utf8')).version ?? '')
  } catch { return '' }
}
function auditHostInvokeContract() {
  const gwPkg = resolveHostPkg('@deepseek-ai/dsh-api-gateway')
  if (gwPkg === null) {
    warn('宿主契约: @deepseek-ai/dsh-api-gateway 不在解析链上，服务级 invoke 契约审计跳过')
    return
  }
  const typesFile = join(gwPkg, 'lib', 'types', 'types.d.ts')
  let required = []
  try {
    const text = readFileSync(typesFile, 'utf8')
    const m = INVOKE_TYPES_RE.exec(text)
    if (m !== null) {
      const fieldRe = /readonly\s+(\w+)(\?)?\s*:/g
      let fm
      while ((fm = fieldRe.exec(m[1])) !== null) {
        if (fm[2] === undefined) required.push(fm[1])
      }
    }
  } catch (e) {
    warn(`宿主契约: 无法读取 ${typesFile}（${e.message}），审计跳过`)
    return
  }
  if (required.length === 0) {
    warn('宿主契约: 未能从 InvokeRemoteRequest 识别必填字段（结构可能已变）——人工复核 types.d.ts 并更新基线')
    return
  }
  // D1. 基线比对（必填字段集 + 核心版本）
  const baselineFile = join(scriptDir, 'host-invoke-contract.baseline.json')
  let baseline
  try {
    baseline = JSON.parse(readFileSync(baselineFile, 'utf8'))
  } catch {
    warn(`宿主契约: 基线缺失（${baselineFile.replace(REPO, '')}）——以当前已装宿主创建基线并提交`)
    return
  }
  const prev = new Set(baseline.invokeRemoteRequestRequired ?? [])
  const added = required.filter((f) => !prev.has(f))
  const removed = [...prev].filter((f) => !required.includes(f))
  if (added.length > 0 || removed.length > 0) {
    warn(`宿主契约: InvokeRemoteRequest 必填字段漂移（新增 [${added.join(', ')}] 移除 [${removed.join(', ')}]）——复核套件网关封装（gateway/host-runner lib）并更新基线`)
  }
  const coreNow = readCoreVersion()
  if (coreNow !== '' && typeof baseline.coreVersion === 'string' && baseline.coreVersion !== '' && baseline.coreVersion !== coreNow) {
    warn(`宿主契约: 核心版本 ${baseline.coreVersion} → ${coreNow}（自愈升级可能已绕过套件重验）——重跑本审计并 install-all 重装套件`)
  }
  // D2. 套件消费面装配检查（仅当宿主要求 peer）
  if (!required.includes('peer')) return
  for (const pkgName of readdirSync(REPO)) {
    if (pkgName === 'node_modules' || pkgName.startsWith('.')) continue
    const pkgDir = join(REPO, pkgName)
    try { if (!statSync(pkgDir).isDirectory()) continue } catch { continue }
    const candidates = [pkgDir, join(pkgDir, 'im-channel')]
    for (const dir of candidates) {
      const libDir = join(dir, 'lib')
      if (!existsSync(libDir) || !existsSync(join(dir, 'package.json'))) continue
      let usesGateway = false
      let attachesPeer = false
      for (const file of walkJsFiles(libDir)) {
        let text
        try { text = readFileSync(file, 'utf8') } catch { continue }
        if (text.includes('typertGateway') || text.includes('TypertGateway')) usesGateway = true
        if (/peer:\s*[A-Za-z_$][\w$]*/.test(text)) attachesPeer = true
      }
      if (usesGateway && !attachesPeer) {
        error(`宿主契约: ${dir.replace(REPO, '')} 消费 typertGateway 但 lib 无任何 peer 装配——宿主要求 invoke 必带 peer；进程内调用须经 connection.createPeer 构造 owner Peer 并随 spec 注入（2026-11-16 事故形态）`)
      }
    }
  }
}

// ─────────────────── 套件识别 ───────────────────
const shippedStandard = join(mirrorScope, '@deepseek-ai', 'dsh-agent-presets', 'presets', 'standard', 'agent.cordis.yml')
const SUITES = []
if (existsSync(join(REPO, 'dsh-twin', 'package.json'))) {
  SUITES.push({
    label: '数字分身套件',
    presetRoots: ['dsh-twin/presets'],
    drift: [
      {
        mountedId: 'digital-twin',
        templateFile: join(REPO, 'dsh-twin', 'presets', 'digital-twin', 'agent.cordis.yml'),
        // 物化器按安装状态追加的可选行：模板里没有属正常增量
        allowExtras: ['@dsh-extra/dsh-memory/tools', 'dsh-yuyi/tools', '@dsh-extra/dsh-computer/tools', '@dsh-extra/dsh-task-board/tools', '@dsh-extra/dsh-architect/tools'],
      },
      {
        mountedId: 'standard-yuyi',
        shippedStandardFile: shippedStandard,
        allowExtras: ['dsh-yuyi/tools', '@dsh-extra/dsh-memory/tools', '@dsh-extra/dsh-computer/tools', '@dsh-extra/dsh-task-board/tools'],
      },
    ],
  })
}
if (existsSync(join(REPO, 'dsh-architect', 'package.json'))) {
  SUITES.push({
    label: '数字架构师套件',
    presetRoots: ['dsh-architect/presets'],
    drift: [
      {
        mountedId: 'architect',
        templateFile: join(REPO, 'dsh-architect', 'presets', 'architect', 'agent.cordis.yml'),
        allowExtras: ['dsh-yuyi/tools', '@dsh-extra/dsh-memory/tools'],
      },
    ],
  })
} else if (existsSync(join(REPO, 'presets', 'architect', 'agent.cordis.yml'))) {
  // 脚本放进 dsh-architect 包内（scripts/check-compat.mjs）时：REPO 即包根
  SUITES.push({
    label: '数字架构师套件（dsh-architect 包内）',
    presetRoots: ['presets'],
    drift: [
      {
        mountedId: 'architect',
        templateFile: join(REPO, 'presets', 'architect', 'agent.cordis.yml'),
        allowExtras: ['dsh-yuyi/tools', '@dsh-extra/dsh-memory/tools'],
      },
    ],
  })
}
if (SUITES.length === 0) {
  // 兜底：无已知套件标记时按通用布局扫描
  SUITES.push({ label: `通用扫描（${REPO}）`, presetRoots: [], drift: [] })
}

// ─────────────────── 执行 ───────────────────
console.log(`[check-compat] home=${HOME} profile=${PROFILE} repo=${REPO}`)
for (const suite of SUITES) {
  console.log(`[check-compat] ── ${suite.label} ──`)
  // A. 仓库内组合文件
  const compFiles = findCompositionFiles(REPO)
  for (const file of compFiles) {
    // 自引解析根：该文件所属包目录（link: 自引时包就在 profile 里，但仓库内也核一份）
    auditCompositionFile(file, `组合 ${file.replace(REPO, '')}`)
  }
  // A+. 已物化预设审计（每个用户预设的每一行都按当前 profile 解析链核对）
  if (existsSync(userPresetsRoot)) {
    for (const entry of readdirSync(userPresetsRoot)) {
      const yml = join(userPresetsRoot, entry, 'agent.cordis.yml')
      if (existsSync(yml)) auditCompositionFile(yml, `已物化预设 ${entry}`)
    }
  }
  // B. 各包运行时 import（lib/ 存在的包）
  for (const pkgName of readdirSync(REPO)) {
    if (pkgName === 'node_modules' || pkgName.startsWith('.')) continue
    const pkgDir = join(REPO, pkgName)
    try { if (!statSync(pkgDir).isDirectory()) continue } catch { continue }
    const candidates = [pkgDir, join(pkgDir, 'im-channel'), join(pkgDir, 'ui-settings-im'), join(pkgDir, 'dsh-client-ui-settings-im')]
    for (const dir of candidates) {
      if (existsSync(join(dir, 'package.json'))) {
        auditRuntimeImports(dir, `运行时 ${dir.replace(REPO, '')}`)
        // A2. 代码内预设行（编程注册的预期组合；YAML 已不再是唯一来源）
        auditPresetCodeRows(dir, `预设行 ${dir.replace(REPO, '')}`)
      }
    }
  }
  // C. 漂移
  for (const spec of suite.drift) auditPresetDrift(spec)
}
// D. 宿主服务级 invoke 契约（全局一次，不随套件重复）
auditHostInvokeContract()

// 汇总
console.log('')
for (const w of warnings) console.log(`[WARN ] ${w}`)
for (const e of errors) console.log(`[ERROR] ${e}`)
console.log(`[check-compat] 结果：${errors.length} error, ${warnings.length} warning`)
process.exit(errors.length > 0 ? 1 : 0)
