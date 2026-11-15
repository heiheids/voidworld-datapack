param(
  [Parameter(Mandatory = $true)][string]$World,
  [string]$Label = 'reset',
  [switch]$KeepBackup
)
# 备份并删除指定存档的三个维度 region 目录，让当前数据包重新生成区块。
# 已生成的区块不会因换数据包而回溯清理，这是"冰山还在""祭坛没有"这类现象最常见的原因。
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$worldDir = if ([System.IO.Path]::IsPathRooted($World)) { $World } else { Join-Path $root $World }
if (-not (Test-Path -LiteralPath $worldDir)) { Write-Output ('存档不存在: ' + $worldDir); exit 1 }

$regionDirs = @()
$dimsRoot = Join-Path $worldDir 'dimensions'
if (Test-Path -LiteralPath $dimsRoot) {
  $regionDirs += Get-ChildItem -LiteralPath $dimsRoot -Recurse -Directory -Filter 'region' -ErrorAction SilentlyContinue
}
$mainRegion = Join-Path $worldDir 'region'
if (Test-Path -LiteralPath $mainRegion) { $regionDirs += Get-Item -LiteralPath $mainRegion }

if ($regionDirs.Count -eq 0) { Write-Output '没有找到 region 目录，无需清理'; exit 0 }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $root ('backup\world-' + $stamp + '_' + $Label)
if (-not $KeepBackup) { New-Item -ItemType Directory -Force -Path $backupDir | Out-Null }

$total = 0
foreach ($rd in $regionDirs) {
  $files = @(Get-ChildItem -LiteralPath $rd.FullName -Filter '*.mca' -File -ErrorAction SilentlyContinue)
  if ($files.Count -eq 0) { continue }
  if (-not $KeepBackup) {
    $rel = $rd.FullName.Substring($worldDir.Length).TrimStart('\')
    $target = Join-Path $backupDir ($rel -replace '[\\/:]', '_')
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $files | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $target -Force }
  }
  $files | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
  $total += $files.Count
  Write-Output ('  已清理 ' + $rd.FullName.Substring($worldDir.Length) + ' : ' + $files.Count + ' 个 .mca')
}

Write-Output ('共清理 ' + $total + ' 个区域文件')
if ($KeepBackup) { Write-Output '（未备份，已按要求跳过）' } else { Write-Output ('备份位置: ' + $backupDir) }
Write-Output '下次进入游戏时，这些维度会按当前数据包重新生成区块'
