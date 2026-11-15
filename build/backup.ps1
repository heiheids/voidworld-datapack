param(
  [Parameter(Mandatory = $true)][string]$Label,
  [string]$Note = '',
  [string]$ConfigFile = 'config.json'
)
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$cfg = Get-Content (Join-Path $PSScriptRoot $ConfigFile) -Raw -Encoding UTF8 | ConvertFrom-Json

$bk = $cfg.backup
$logName = if ($bk -and $bk.log_file) { $bk.log_file } else { 'voidworld工程备份.txt' }
$bkDirName = if ($bk -and $bk.dir) { $bk.dir } else { 'backup' }
$include = if ($bk -and $bk.include) { $bk.include } else { @('build', 'behavior', 'README.md') }

$logPath = Join-Path $root $logName
$bkDir = Join-Path $root $bkDirName
if (-not (Test-Path -LiteralPath $bkDir)) { New-Item -ItemType Directory -Path $bkDir -Force | Out-Null }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$safe = ($Label -replace '[\\/:*?"<>|\s]+', '_')
$zipName = "$stamp`_$safe.zip"
$zipPath = Join-Path $bkDir $zipName

$files = New-Object System.Collections.Generic.List[string]
foreach ($item in $include) {
  $p = Join-Path $root $item
  if (Test-Path -LiteralPath $p -PathType Container) {
    Get-ChildItem -LiteralPath $p -Recurse -File | ForEach-Object { $files.Add($_.FullName) }
  } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
    $files.Add($p)
  }
}

$fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($f in $files) {
  $rel = $f.Substring($root.Length).TrimStart('\', '/')
  $entry = $zip.CreateEntry($rel)
  $es = $entry.Open()
  $bytes = [System.IO.File]::ReadAllBytes($f)
  $es.Write($bytes, 0, $bytes.Length)
  $es.Dispose()
}
$zip.Dispose(); $fs.Dispose()

$lines = @(
  ''
  '================================================================'
  ('时间: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  ('备份: ' + $bkDirName + '\' + $zipName + '  (' + $files.Count + ' 个文件)')
  ('即将进行的操作: ' + $Label)
  ('说明: ' + $Note)
  '================================================================'
)
Add-Content -LiteralPath $logPath -Value $lines -Encoding UTF8
Write-Output ('backup=' + $zipName + ' files=' + $files.Count + ' log=' + $logName)
