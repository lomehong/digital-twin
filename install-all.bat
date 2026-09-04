@echo off
setlocal
title DSH Plugin Installer
set "RC="

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
set "JSFILE=%TEMP%\dsh-install-all.mjs"
"%NODE_EXE%" -e "const fs=require('fs');const s=fs.readFileSync(process.argv[1],'utf8');const M='//==JS-STA'+'RT==';const E='//==JS-E'+'ND==';const a=s.indexOf(M)+M.length,b=s.indexOf(E);if(a<14||b<0){console.error('embedded JS not found');process.exit(2)}fs.writeFileSync(process.argv[2],s.slice(a,b))" "%~f0" "%JSFILE%"
if %errorlevel% neq 0 (
    echo [ERROR] failed to extract embedded installer script.
    goto :fail
)

rem ==== run installer; %~dp0 (this file's dir) is the plugin repo root ====
"%NODE_EXE%" "%JSFILE%" "%~dp0."
set "RC=%errorlevel%"
del "%JSFILE%" >nul 2>nul
if %RC% neq 0 goto :fail

echo.
echo Install OK! Restart DeepSeek Harness (dsh web / desktop) to load plugins.
goto :end

:fail
echo.
echo Install FAILED. See output above.

:end
echo.
pause
exit /b %RC%

//==JS-START==
/**
 * DSH local plugin installer (embedded in install-all.bat; do not run directly).
 *
 * Usage (from the bat): node <temp-file> <repo-root>
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
import { existsSync, readFileSync, writeFileSync, appendFileSync, rmSync } from 'node:fs'
import { join, resolve } from 'node:path'

const REPO_ROOT = resolve(process.argv[2] ?? process.cwd())
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

manifest.dependencies ??= {}
manifest.dsh ??= {}
manifest.dsh.profile ??= {}
manifest.dsh.profile.bundles ??= []

// remove the legacy whole-repo dsh-im-bot link (a dir without package.json)
delete manifest.dependencies['dsh-im-bot']
manifest.dsh.profile.bundles = manifest.dsh.profile.bundles.filter(b => b !== 'dsh-im-bot')

for (const { pkg, dir, sub, bundle } of PLUGINS) {
  const link = `link:${join(REPO_ROOT, dir, sub ?? '').replace(/\\/g, '/')}`
  manifest.dependencies[pkg] = link
  if (bundle) manifest.dsh.profile.bundles = [...new Set([...manifest.dsh.profile.bundles, pkg])]
}
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)

// pnpm refuses to add deps to the workspace root unless this check is off
const npmrcPath = join(profileDir, '.npmrc')
if (!existsSync(npmrcPath) || !readFileSync(npmrcPath, 'utf8').includes('ignore-workspace-root-check=true')) {
  appendFileSync(npmrcPath, 'ignore-workspace-root-check=true\n')
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
console.log(`[install-all] manifest updated (${PLUGINS.length} packages), running pnpm install (via ${pnpm.via})...`)
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

for (const { pkg, dir, sub } of PLUGINS) {
  const linkPath = join(profileDir, 'node_modules', ...pkg.split('/'))
  if (!fixJunction(linkPath, join(REPO_ROOT, dir, sub ?? ''))) {
    console.error(`[install-all] cannot create junction: ${linkPath}`)
    process.exit(1)
  }
}

const allLinked = PLUGINS.every(({ pkg }) => existsSync(join(profileDir, 'node_modules', ...pkg.split('/'), 'package.json')))
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

console.log(`[install-all] done (${PLUGINS.length} links verified)! Restart dsh web to load plugins.`)
//==JS-END==
