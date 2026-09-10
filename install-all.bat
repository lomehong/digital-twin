@echo off
setlocal
title DSH Plugin Installer
set "RC="
rem ============================================================================
rem WARNING: keep this cmd section 100% ASCII (7-bit), comments included.
rem cmd.exe decodes batch lines with the active codepage; multibyte characters
rem in a batch file (especially together with `chcp 65001`) can desynchronise the
rem parser mid-character, eating the `rem` prefix and running the comment text as
rem commands. Real failure 2026-09-10: users saw
rem   '<fragment>' is not recognized as an internal or external command
rem where <fragment> was Chinese comment text from this very section.
rem Chinese text is fine inside the embedded JS block below (after `exit /b`):
rem cmd never executes or reads that block, node does.
rem ============================================================================
rem Keep console output UTF-8 so messages from the embedded installer stay
rem readable when the shell/log decodes them as UTF-8.
chcp 65001 >nul 2>nul

rem ==== network environment ==================================================
rem Node fetch/undici neither reads the Windows system proxy nor prefers IPv4.
rem Measured on this machine: system proxy 127.0.0.1:7890 enabled but no
rem HTTPS_PROXY env -> a direct github.com:443 connect timed out after 10s,
rem while PowerShell (which does use the system proxy) always succeeded.
rem NODE_OPTIONS is inherited by every node child this bat spawns
rem (release probe / installer / pnpm), so IPv4-first is applied once here.
set "NODE_OPTIONS=%NODE_OPTIONS% --dns-result-order=ipv4first"
rem Behind a mandatory proxy: respect an existing HTTPS_PROXY. Node 24 needs
rem NODE_USE_ENV_PROXY=1 for fetch to honour it (pnpm reads it natively).
set "NODE_USE_ENV_PROXY=1"

rem ==== locate Node.js: PATH first, then dsh desktop bundled runtime ====
set "NODE_EXE=node"
where node >nul 2>nul
if %errorlevel% neq 0 (
    if exist "%LOCALAPPDATA%\dsh-desktop-app-data\node\node.exe" (
        set "NODE_EXE=%LOCALAPPDATA%\dsh-desktop-app-data\node\node.exe"
    ) else (
        echo [ERROR] Node.js not found. Install dsh desktop first, or add node.exe to PATH.
        goto :fail
    )
)

rem ==== locate DSH_HOME: desktop app dir first, then ~/.dsh ====
if not defined DSH_HOME (
    if exist "%LOCALAPPDATA%\dsh-desktop-app-data\home" (
        set "DSH_HOME=%LOCALAPPDATA%\dsh-desktop-app-data\home"
    ) else (
        set "DSH_HOME=%USERPROFILE%\.dsh"
    )
)

echo ==================================================
echo   DSH local plugin installer
echo   actors / computer / im-bot / ledger / memory /
echo   redact / regression / twin / yuyi
echo   target profile: %DSH_HOME%\profiles\web
echo ==================================================
echo.

rem ==== extract embedded JS (between JS-START / JS-END markers) to temp file ====
rem The temp directory must be a Windows-style path: processes started from
rem Git Bash / MSYS inherit TEMP=/tmp (a POSIX path), and /tmp\dsh-install-all.mjs
rem cannot be written on Windows -> extraction fails -> :fail (real failure
rem 2026-09-10). Fall back level by level:
rem %TEMP% (must be non-POSIX and exist) -> %LOCALAPPDATA%\Temp -> this bat's dir.
set "JSDIR="
if defined TEMP if not "%TEMP:~0,1%"=="/" if exist "%TEMP%\" set "JSDIR=%TEMP%"
if not defined JSDIR if defined LOCALAPPDATA if exist "%LOCALAPPDATA%\Temp\" set "JSDIR=%LOCALAPPDATA%\Temp"
if not defined JSDIR set "JSDIR=%~dp0"
set "JSFILE=%JSDIR%\dsh-install-all.mjs"
"%NODE_EXE%" -e "const fs=require('fs');const s=fs.readFileSync(process.argv[1],'utf8');const M='//==JS-STA'+'RT==';const E='//==JS-E'+'ND==';const a=s.indexOf(M)+M.length,b=s.indexOf(E);if(a<14||b<0){console.error('embedded JS not found');process.exit(2)}fs.writeFileSync(process.argv[2],s.slice(a,b))" "%~f0" "%JSFILE%"
if not exist "%JSFILE%" (
    echo [ERROR] failed to extract embedded installer script to "%JSFILE%".
    goto :fail
)

rem ==== run installer; %~dp0 (this file's dir) is the plugin repo root; %* forwards mode flags (-Release) ====
"%NODE_EXE%" "%JSFILE%" "%~dp0." %*
set "RC=%errorlevel%"
del "%JSFILE%" >nul 2>nul
if %RC% neq 0 goto :fail

echo.
echo Install OK! Restart DeepSeek Harness (dsh web / desktop) to load plugins.
goto :end

:fail
echo.
echo Install FAILED. See output above.
if not defined RC set "RC=1"

:end
echo.
pause
rem RC must always be defined: `exit /b %RC%` with an empty RC may fail to stop
rem the batch, and cmd then walks into the embedded JS text line by line
rem (producing "is not recognized..." noise). Real failure 2026-09-10.
if not defined RC set "RC=0"
exit /b %RC%

rem ==== hard guard: cmd must never fall into the embedded JS text below ====
rem The extractor slices by markers and ignores this line. If the exit above
rem ever fails to take effect, this line terminates the batch immediately
rem instead of running JS source as commands.
exit /b 1

//==JS-START==
/**
 * DSH local plugin installer (embedded in install-all.bat; do not run directly).
 *
 * Usage (from the bat): node <temp-file> <repo-root> [-Release]
 *
 * -Release: end-user mode. Dependencies point at each plugin repo's GitHub
 * Release tarball (stable URL: /releases/latest/download/<name>-latest.tgz)
 * instead of local link: dirs — no submodule checkout, no build toolchain.
 * ALL plugins must be published: a missing asset aborts before any change.
 * The URL carries ?release=<tag>, so re-running is idempotent within one
 * release and refetches when a new release lands (= the update path).
 *
 * Idempotent: safe to re-run. Links local plugin dirs into the dsh web
 * profile as `link:` deps, registers them as profile bundle layers, runs
 * pnpm install (PATH -> %APPDATA%\npm -> corepack fallback), verifies each
 * package's built entry (lib/) BEFORE installing, repairs the broken
 * junctions pnpm 9 creates for cross-drive absolute link: specifiers on
 * Windows, and removes the digital-twin preset version stamp so the next
 * dsh start re-materializes the preset with the freshly installed optional
 * tool rows (tool-memory / tool-yuyi / tool-computer).
 *
 * Env: DSH_HOME (dsh home dir), DSH_PROFILE (default: web)
 */
import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync, appendFileSync, rmSync, lstatSync, mkdirSync, readdirSync } from 'node:fs'
import { join, resolve, dirname } from 'node:path'

const REPO_ROOT = resolve(process.argv[2] ?? process.cwd())
/** -Release：最终用户模式，依赖直指 GitHub Release tarball，而非本地 link: 目录。 */
const RELEASE = process.argv.slice(3).some((a) => a === '-Release' || a === '--release')
const PROFILE = process.env.DSH_PROFILE ?? 'web'
const desktopHome = join(process.env.LOCALAPPDATA ?? '', 'dsh-desktop-app-data', 'home')
const home = process.env.DSH_HOME
  ?? (existsSync(desktopHome) ? desktopHome : join(process.env.USERPROFILE ?? process.env.HOME ?? '.', '.dsh'))
const profileDir = join(home, 'profiles', PROFILE)

/** dir = local dir; bundle = register as profile layer; sub = subpackage path. */
const PLUGINS = [
  { dir: 'dsh-actors',     pkg: '@dsh-extra/dsh-actors',     bundle: true },
  { dir: 'dsh-computer',   pkg: '@dsh-extra/dsh-computer',   bundle: true },
  { dir: 'dsh-im-bot',     pkg: '@dsh-extra/im-channel',     bundle: true, sub: 'im-channel' },
  { dir: 'dsh-im-bot',     pkg: '@dsh-extra/dsh-client-ui-settings-im', bundle: true, sub: 'ui-settings-im' },
  { dir: 'dsh-ledger',     pkg: '@dsh-extra/dsh-ledger',     bundle: true },
  { dir: 'dsh-memory',     pkg: '@dsh-extra/dsh-memory',     bundle: true },
  { dir: 'dsh-redact',     pkg: '@dsh-extra/dsh-redact',     bundle: true },
  { dir: 'dsh-regression', pkg: '@dsh-extra/dsh-regression', bundle: true },
  { dir: 'dsh-task-board', pkg: '@dsh-extra/dsh-task-board', bundle: true },
  { dir: 'dsh-twin',       pkg: '@dsh-extra/dsh-twin',       bundle: true },
  { dir: 'dsh-yuyi',       pkg: 'dsh-yuyi',                  bundle: true },
]

/** 每个 Package.json 的入口（main 或 exports['.']），dsh 加载的是构建产物而非 TS 源码。 */
function entryFile(pkgDir) {
  const manifest = JSON.parse(readFileSync(join(pkgDir, 'package.json'), 'utf8'))
  const e = manifest.exports?.['.']
  return typeof e === 'string' ? e : (e?.default ?? manifest.main ?? 'index.js')
}

const manifestPath = join(profileDir, 'package.json')
if (!existsSync(manifestPath)) {
  console.error(`[install-all] profile manifest not found: ${manifestPath}\n[install-all] run dsh web once first.`)
  process.exit(1)
}
let manifest
try {
  manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
} catch (error) {
  console.error(`[install-all] cannot parse ${manifestPath}: ${error instanceof Error ? error.message : String(error)}`)
  process.exit(1)
}

if (!RELEASE) {
  for (const item of PLUGINS) {
    const pkgDir = join(REPO_ROOT, item.dir, item.sub ?? '')
    if (!existsSync(join(pkgDir, 'package.json'))) {
      console.error(`[install-all] missing package.json under ${pkgDir}`)
      process.exit(1)
    }
    // dsh 按 package.json 的入口加载构建产物；只装未构建的包会在启动时才爆，这里提前拦。
    const entry = join(pkgDir, entryFile(pkgDir))
    if (!existsSync(entry)) {
      console.error(`[install-all] built entry not found: ${entry}\n[install-all] run "npm run build" in ${item.dir}${item.sub ? '/' + item.sub : ''} first.`)
      process.exit(1)
    }
  }
}

manifest.dependencies ??= {}
manifest.dsh ??= {}
manifest.dsh.profile ??= {}
manifest.dsh.profile.bundles ??= []

// remove the legacy whole-repo dsh-im-bot link (a dir without package.json)
delete manifest.dependencies['dsh-im-bot']
manifest.dsh.profile.bundles = manifest.dsh.profile.bundles.filter(b => b !== 'dsh-im-bot')

// release 模式：依赖 = GitHub Release tarball URL（/releases/latest/download/<name>-latest.tgz）。
// 两条 2026-09-10 需求方确认的规则：
// ① 全量要求：任一插件缺 Release 资产即中止（套件少几块 = 工作台缺功能，比明确失败更糟），
//    不做部分安装、不改动任何状态。
// ② 可更新：URL 带 `?release=<tag>`（tag 取自 /releases/latest 的 302 Location，零 API 配额）。
//    同 Release 重跑 = 同一 specifier = pnpm 幂等跳过；发了新 Release = specifier 变化 =
//    pnpm 重新解析并下载新 tarball——「生产安装」因此同时就是「生产更新」。
const releaseUrl = (item, tag) =>
  `https://github.com/lomehong/${item.dir}/releases/latest/download/${item.pkg.split('/').pop()}-latest.tgz`
    + (tag ? `?release=${encodeURIComponent(tag)}` : '')
/** 最新 Release 的 tag：跟随 github 的 302 Location，不消耗 API 配额；取不到返回 null。 */
async function latestTag(repo) {
  try {
    const r = await fetch(`https://github.com/lomehong/${repo}/releases/latest`, { method: 'HEAD', redirect: 'manual' })
    const m = /\/releases\/tag\/([^/?#]+)/.exec(r.headers.get('location') ?? '')
    return m ? decodeURIComponent(m[1]) : null
  } catch { return null }
}
/** PowerShell 兜底探测：走 Windows 系统代理，实测比 node 直连稳定得多
 * （本机：node fetch 对同一 URL 200/失败交替，PowerShell 一直 200）。
 * 只解析状态码：2xx=ok、404=missing、其余/异常=unreachable。 */
function headProbePowerShell(url) {
  const script = "try { $r = Invoke-WebRequest -UseBasicParsing -Method Head -MaximumRedirection 5 -TimeoutSec 20 -Uri '"
    + url + "'; $r.StatusCode } catch { if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'ERR' } }"
  const done = spawnSync('powershell', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8' })
  const out = String(done.stdout ?? '').trim().split(/\s+/).pop() ?? ''
  if (out === '200' || out === '204') return 'ok'
  if (out === '404') return 'missing'
  return `unreachable(ps:${out === '' ? 'no-output' : out})`
}
/** 带重试的 HEAD 探测，返回 'ok' | 'missing' | 'unreachable(原因)'。
 * 生产安装对全量有硬要求，一次网络抖动/限流不能误判成「该插件没发 Release」
 * （2026-09-10 实测：连续两轮探测，第二轮 11 个全被判缺，实为限流）。
 * 只有明确的 404 才算未发布；429/5xx/网络异常退避重试后仍失败记为 unreachable，
 * 最后用 PowerShell（系统代理）兜底再判一次。 */
async function headProbe(url, attempts = 3) {
  let last = 'network'
  for (let i = 0; i < attempts; i++) {
    try {
      const r = await fetch(url, { method: 'HEAD' })
      if (r.ok) return 'ok'
      if (r.status === 404) return 'missing'
      last = `HTTP ${r.status}`
    } catch { last = 'network' }
    await new Promise((done) => setTimeout(done, 400 * (i + 1)))
  }
  return headProbePowerShell(url)
}
const AVAILABLE = new Map()
if (RELEASE) {
  console.log('[install-all] release mode: probing GitHub Releases ...')
  const tags = new Map()
  const missing = []
  for (const item of PLUGINS) {
    const url = releaseUrl(item, null)
    const status = await headProbe(url)
    if (status !== 'ok') { missing.push(`${item.pkg}  (${url}) — ${status}`); continue }
    if (!tags.has(item.dir)) tags.set(item.dir, await latestTag(item.dir))
    const tag = tags.get(item.dir)
    // tag 拿不到时退化为时间戳戳：宁可 URL 略有噪音，也要保证「再点一次能拿到最新」
    AVAILABLE.set(item.pkg, releaseUrl(item, tag ?? `t${Date.now()}`))
  }
  if (missing.length > 0) {
    const unreachable = missing.filter((line) => line.includes('unreachable'))
    console.error(`[install-all] release install requires every plugin published; ${missing.length} unavailable:`)
    for (const line of missing) console.error(`[install-all]   - ${line}`)
    console.error(
      unreachable.length > 0
        ? '[install-all] aborted before changing anything：网络不可达或被限流（稍后重试即可）'
        : '[install-all] aborted before changing anything：有插件尚未发布 Release'
    )
    process.exit(1)
  }
}

for (const item of PLUGINS) {
  const { pkg, dir, sub, bundle } = item
  if (RELEASE) {
    const url = AVAILABLE.get(pkg)
    if (!url) continue
    manifest.dependencies[pkg] = url
  } else {
    const link = `link:${join(REPO_ROOT, dir, sub ?? '').replace(/\\/g, '/')}`
    manifest.dependencies[pkg] = link
  }
  if (bundle && (!RELEASE || AVAILABLE.has(pkg))) manifest.dsh.profile.bundles = [...new Set([...manifest.dsh.profile.bundles, pkg])]
}

// ==== 宿主锚定：release 模式把宿主已有的 @deepseek-ai/* 全钉到宿主版本 ====
// 为什么必须（2026-09-10 实测）：
// ① dsh 0.1.x 全在预发布标签上（latest 停在 0.0.1-rc.1，0.1.5-* 只在 alpha/next），
//    插件 manifest 的普通 semver 区间（如 ^0.1.2 → >=0.1.2 <0.2.0-0）按 semver 规则
//    匹配不到任何预发布版本 → ERR_PNPM_NO_MATCHING_VERSION，安装直接失败；
// ② 即便能解析，也会拉进 0.1.2 线的旧副本，与宿主正在跑的版本形成双份物理实例。
// 钉到宿主版本后：解析恒成立、版本与宿主一致、pnpm 复用宿主同一 store 实体，
// 插件与宿主共用同一份 harness 模块（单例语义正确）。
// link 模式则清理该字段——两个通道互相切换时不留残留，manifest 始终只有当前形态。
function hostHarnessVersions() {
  const scope = join(home, 'profiles', 'node_modules', '@deepseek-ai')
  const out = {}
  if (!existsSync(scope)) return out
  for (const entry of readdirSync(scope)) {
    const manifestPath = join(scope, entry, 'package.json')
    if (!existsSync(manifestPath)) continue
    try {
      const version = JSON.parse(readFileSync(manifestPath, 'utf8')).version
      if (typeof version === 'string' && version !== '') out[`@deepseek-ai/${entry}`] = version
    } catch { /* 读不了的条目跳过：锚定是加固，不是链路必需 */ }
  }
  return out
}
// pnpm ≥10 的设置新家是 pnpm-workspace.yaml（package.json 的 "pnpm" 字段不再被
// 读取——2026-09-10 实测 pnpm 12.3.4：overrides 静默失效 + 构建脚本默认拦截，
// ERR_PNPM_IGNORED_BUILDS 直接安装失败）。overrides（宿主锚定）与构建脚本许可
// 统一写到 workspace yaml，对 pnpm 9/11/12 均有效；manifest 遗留 pnpm 字段一并
// 清理（pnpm 12 会对它告警）。
function upsertWorkspaceYaml(profileDir, managed) {
  const CR = String.fromCharCode(13), LF = String.fromCharCode(10)
  const EOL = new RegExp(CR + '?' + LF)
  const wsPath = join(profileDir, 'pnpm-workspace.yaml')
  const srcLines = existsSync(wsPath) ? readFileSync(wsPath, 'utf8').split(EOL) : []
  const dropKeys = new Set(Object.keys(managed).map((k) => k.toLowerCase()))
  const kept = []
  let dropping = false
  for (const line of srcLines) {
    if (/^[A-Za-z][A-Za-z0-9-]*:/.test(line)) dropping = dropKeys.has(line.slice(0, line.indexOf(':')).toLowerCase())
    if (!dropping) kept.push(line)
  }
  while (kept.length > 0 && kept[kept.length - 1].trim() === '') kept.pop()
  for (const [key, value] of Object.entries(managed)) {
    kept.push(key + ':')
    if (Array.isArray(value)) {
      for (const item of value) kept.push('  - ' + item)
    } else {
      for (const [k, v] of Object.entries(value)) kept.push('  ' + JSON.stringify(k) + ': ' + (typeof v === 'string' ? JSON.stringify(v) : String(v)))
    }
  }
  writeFileSync(wsPath, kept.join(LF) + LF)
}
// 构建脚本许可：protobufjs/node-pty/koffi/esbuild 是套件依赖里已知带 install 脚本的包
const BUILD_ALLOWED = { protobufjs: true, 'node-pty': true, koffi: true, esbuild: true }
if (RELEASE) {
  const overrides = hostHarnessVersions()
  const count = Object.keys(overrides).length
  if (count === 0) {
    console.error('[install-all] host store has no @deepseek-ai/* packages — run dsh web once before installing the suite.')
    process.exit(1)
  }
  upsertWorkspaceYaml(profileDir, { overrides, allowBuilds: BUILD_ALLOWED, onlyBuiltDependencies: Object.keys(BUILD_ALLOWED) })
  console.log(`[install-all] pinned ${count} host harness packages into pnpm-workspace.yaml overrides`)
} else {
  upsertWorkspaceYaml(profileDir, { allowBuilds: BUILD_ALLOWED, onlyBuiltDependencies: Object.keys(BUILD_ALLOWED) })
}
delete manifest.pnpm
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)

// pnpm refuses to add deps to the workspace root unless this check is off
const npmrcPath = join(profileDir, '.npmrc')
if (!existsSync(npmrcPath) || !readFileSync(npmrcPath, 'utf8').includes('ignore-workspace-root-check=true')) {
  appendFileSync(npmrcPath, 'ignore-workspace-root-check=true\n')
}
// 套件插件的 @deepseek-ai/* peer 由**宿主上层 store**（<home>/profiles/node_modules）
// 满足，pnpm 看不到那层、会在报告里逐条标 missing peer——实测运行时解析完全正常
// （2026-09-10 逐插件 import 探针全 OK）。显式关掉严格 peer 检查：这些是信息性告警，
// 不能让未来某个 pnpm 版本把它升级成硬错误、把生产安装整死。
if (!existsSync(npmrcPath) || !readFileSync(npmrcPath, 'utf8').includes('strict-peer-dependencies=false')) {
  appendFileSync(npmrcPath, 'strict-peer-dependencies=false\n')
}

// ==== locate pnpm: PATH first, then %APPDATA%\npm, then corepack ====
// 桌面版 dsh 的 pnpm 不在 PATH（历史上 ENOENT 过）；PATH 也没有时 node 自带的
// corepack 是最后兜底。返回 { cmd, args } 或 null。
function locatePnpm() {
  if (spawnSync('pnpm', ['--version'], { stdio: 'ignore', shell: process.platform === 'win32' }).status === 0) {
    return { cmd: 'pnpm', args: [], via: 'PATH' }
  }
  const appdataPnpm = join(process.env.APPDATA ?? '', 'npm', 'pnpm.cmd')
  if (existsSync(appdataPnpm)) return { cmd: appdataPnpm, args: [], via: appdataPnpm }
  if (spawnSync('corepack', ['--version'], { stdio: 'ignore', shell: process.platform === 'win32' }).status === 0) {
    return { cmd: 'corepack', args: ['pnpm'], via: 'corepack' }
  }
  return null
}

const pnpm = locatePnpm()
if (pnpm === null) {
  console.error('[install-all] pnpm not found (PATH / %APPDATA%\\npm / corepack all missing). Install pnpm or Node.js with corepack.')
  process.exit(1)
}
console.log(`[install-all] manifest updated (${RELEASE ? AVAILABLE.size : PLUGINS.length} packages${RELEASE ? ' from GitHub Releases' : ''}), running pnpm install (via ${pnpm.via})...`)
const result = spawnSync(pnpm.cmd, [...pnpm.args, 'install'], { cwd: profileDir, stdio: 'inherit', shell: process.platform === 'win32' })

// pnpm 9 on Windows creates broken junctions for cross-drive absolute link:
// deps (target becomes profile-relative). Detect and recreate them.
function fixJunction(linkPath, target) {
  if (existsSync(join(linkPath, 'package.json'))) return true
  spawnSync('cmd', ['/c', 'rmdir', linkPath], { stdio: 'ignore' })
  if (existsSync(linkPath)) return false // a real dir lacking package.json; leave it
  const created = spawnSync('cmd', ['/c', 'mklink', '/J', linkPath, target], { stdio: 'pipe', shell: false })
  return created.status === 0 && existsSync(join(linkPath, 'package.json'))
}

if (!RELEASE) {
  for (const { pkg, dir, sub } of PLUGINS) {
    const linkPath = join(profileDir, 'node_modules', ...pkg.split('/'))
    if (!fixJunction(linkPath, join(REPO_ROOT, dir, sub ?? ''))) {
      console.error(`[install-all] cannot create junction: ${linkPath}`)
      process.exit(1)
    }
  }
} // release 模式装的是解压后的真实目录，无需 junction 修复

// ==== link: 模式对等依赖解析修复（真实故障 2026-09-10）====
// junction 链接的插件经 Node ESM 按真实路径解析依赖：从插件目录向上走，
// 永远到不了宿主 hoisted 仓库（<home>/profiles/node_modules）。插件未声明
// （或声明了但 workspace 未装全）的 @deepseek-ai/* 导入，会在 dsh 下次启动
// 时 ERR_MODULE_NOT_FOUND——当天 dsh-memory 的 dsh-tools 即此雷，表现为
// 「装完一重启服务就崩」。
// 策略：用 Node 自身做「入口 import 探针」（复现 dsh 启动的加载路径），缺
// 哪个包就从宿主 hoisted 仓库建 junction 补进该插件 node_modules，循环到
// 探针通过。junction 指向宿主同一物理副本——模块单例语义保持正确。
// 浏览器端 client.js / JSX 视图不在探针范围（不经 Node 解析）。
if (!RELEASE) {
  const hostScope = join(home, 'profiles', 'node_modules', '@deepseek-ai')
  const probeEntry = (entryPath) => spawnSync(process.execPath, [
    '-e',
    'import(process.argv[1]).then(()=>{},e=>{console.error((e.code??"")+" "+(e.message??""));process.exit(1)})',
    'file:///' + entryPath.replace(/\\/g, '/'),
  ], { encoding: 'utf8' })
  for (const item of PLUGINS) {
    const pkgDir = join(REPO_ROOT, item.dir, item.sub ?? '')
    const entryPath = join(pkgDir, entryFile(pkgDir))
    let probed = false
    for (let round = 0; round < 12 && !probed; round++) {
      const r = probeEntry(entryPath)
      if (r.status === 0) { probed = true; break }
      const stderr = r.stderr ?? ''
      const m = /Cannot find package '(@deepseek-ai\/[a-z0-9-]+)'/.exec(stderr)
      if (!m) {
        // 非 @deepseek-ai 的解析失败 = 插件自身依赖没装全（探针复现的正是启动路径）
        const other = /Cannot find package '([^']+)'/.exec(stderr)
        if (other) {
          console.error(`[install-all] ${item.pkg} cannot resolve ${other[1]} (not a host-scope package) — run "pnpm install" in ${pkgDir} first.`)
        } else {
          console.error(`[install-all] probe failed for ${item.pkg}: ${stderr.split('\n')[0]}`)
        }
        process.exit(1)
      }
      const dep = m[1].split('/')[1]
      const hostPkg = join(hostScope, dep)
      if (!existsSync(join(hostPkg, 'package.json'))) {
        console.error(`[install-all] ${item.pkg} imports ${m[1]}, but the host store has no such package — upgrade the dsh core or fix the plugin's declared deps.`)
        process.exit(1)
      }
      const linkDir = join(pkgDir, 'node_modules', '@deepseek-ai', dep)
      mkdirSync(dirname(linkDir), { recursive: true })
      // lstat 不跟随链接：悬空 junction（目标被清理过）也要先摘掉再重建
      try { lstatSync(linkDir); spawnSync('cmd', ['/c', 'rmdir', linkDir], { stdio: 'ignore' }) } catch { /* name absent */ }
      const made = spawnSync('cmd', ['/c', 'mklink', '/J', linkDir, hostPkg], { stdio: 'pipe' })
      if (made.status !== 0 || !existsSync(join(linkDir, 'package.json'))) {
        console.error(`[install-all] cannot create peer junction: ${linkDir} -> ${hostPkg}`)
        process.exit(1)
      }
      console.log(`[install-all] repaired peer resolution: ${m[1]} -> host store (${item.pkg})`)
    }
    if (!probed) {
      console.error(`[install-all] peer repair did not converge for ${item.pkg} after 12 rounds.`)
      process.exit(1)
    }
  }
}

const EXPECTED = RELEASE ? PLUGINS.filter(({ pkg }) => AVAILABLE.has(pkg)) : PLUGINS
const allLinked = EXPECTED.every(({ pkg }) => existsSync(join(profileDir, 'node_modules', ...pkg.split('/'), 'package.json')))
if (result.status !== 0 || !allLinked) {
  console.error('[install-all] install failed, see output above.')
  process.exit(1)
}

// ==== 让数字分身预设按新安装状态重物化 ====
// materializePreset 只在版本戳与 PRESET_VERSION 不一致时重写；本轮若只是
// 新装了可选依赖（如 dsh-computer），版本戳不变就不会追加 tool-* 行——
// 「装了却不生效」。删掉戳，下次 dsh 启动 dsh-twin apply 时必然重物化。
const stampPath = join(home, '.agent-presets', 'digital-twin', '.materialized-version')
if (existsSync(stampPath)) {
  try { rmSync(stampPath); console.log('[install-all] removed digital-twin preset stamp (will re-materialize on next start).') }
  catch (e) { console.warn(`[install-all] could not remove preset stamp: ${e instanceof Error ? e.message : String(e)}`) }
}

// ==== 安装后校验：物化预设必须包含已装可选依赖的工具行 ====
// 重物化发生在下次 dsh 启动；这里只做提示级校验，不阻塞安装。
const presetYml = join(home, '.agent-presets', 'digital-twin', 'agent.cordis.yml')
if (existsSync(presetYml)) {
  const yml = readFileSync(presetYml, 'utf8')
  const missing = [
    ['@dsh-extra/dsh-memory', 'tool-memory'],
    ['dsh-yuyi', 'tool-yuyi'],
    ['@dsh-extra/dsh-computer', 'tool-computer'],
  ]
    .filter(([pkgName]) => manifest.dsh.profile.bundles.includes(pkgName))
    .filter(([, rowId]) => !yml.includes(`- id: ${rowId}`))
  if (missing.length > 0) {
    console.warn(`[install-all] note: preset rows not yet materialized: ${missing.map(m => m[1]).join(', ')} — restart dsh to apply.`)
  }
}

const skipped = RELEASE ? PLUGINS.filter(({ pkg }) => !AVAILABLE.has(pkg)).map(({ pkg }) => pkg) : []
console.log(`[install-all] done (${EXPECTED.length} links verified${skipped.length ? `, ${skipped.length} skipped: ${skipped.join(', ')}` : ''})! Restart dsh web to load plugins.`)
//==JS-END==
