$h = "D:\Develop\Coder\nodejs\deepseek-harness"
$inv = [System.Globalization.CultureInfo]::InvariantCulture
# 全仓库扫 defineTool/defineAgentTool 的 name 字段（工具能力地图）
$results = @()
$files = Get-ChildItem $h -Recurse -Include "*.ts","*.tsx" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch 'node_modules|dist|\.git\\|vendor|_test|\.spec\.|benchmarks' }
$idx = 0
$total = $files.Count
foreach ($f in $files) {
  $idx++
  if ($idx % 500 -eq 0) { Write-Output ("...scanned " + $idx + "/" + $total) }
  try {
    $c = [System.IO.File]::ReadAllText($f.FullName)
    if (-not $c.Contains('defineTool') -and -not $c.Contains('defineAgentTool')) { continue }
    foreach ($m in [regex]::Matches($c, "define(?:Agent)?Tool\(\s*\{[^}]*?name:\s*[`"`']([a-z0-9_:. -]{3,50})[`"`']", 'Singleline')) {
      $rel = $f.FullName.Replace($h + '\', '')
      $results += [pscustomobject]@{ tool = $m.Groups[1].Value; file = $rel }
    }
  } catch {}
}
Write-Output ("TOOL_COUNT=" + $results.Count)
$results | Sort-Object tool -Unique | ForEach-Object { Write-Output ("  " + $_.tool + "  <- " + $_.file) }
