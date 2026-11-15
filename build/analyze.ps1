param(
  [string]$World = 'voidtest',
  [string]$Dim = 'overworld',
  [string]$ConfigFile = 'config.json'
)
# 汇总某个维度所有 region 文件里出现的方块 id 及其所在 section(Y) 分布。
# 用于验证「只允许 Y=floor 一层台阶」等约束，输出可疑方块清单。
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\nbt.ps1')
. (Join-Path $PSScriptRoot 'lib\region.ps1')

$cfg = Get-Content (Join-Path $PSScriptRoot $ConfigFile) -Raw -Encoding UTF8 | ConvertFrom-Json
$regDir = Join-Path $root (Join-Path 'test' (Join-Path $World ('dimensions\minecraft\' + $Dim + '\region')))
if (-not (Test-Path -LiteralPath $regDir)) { Write-Output ('missing region dir: ' + $regDir); exit 1 }

$byId = @{}
$chunks = 0
$sections = 0
foreach ($mca in (Get-ChildItem -LiteralPath $regDir -Filter '*.mca' -File)) {
  foreach ($ch in (Get-RegionChunkBytes $mca.FullName)) {
    $rootNbt = $null
    try { $rootNbt = Read-NbtRoot $ch.Bytes } catch { continue }
    $chunks++
    foreach ($sec in (Get-SectionPalettes $rootNbt)) {
      $sections++
      foreach ($id in $sec.Ids) {
        if (-not $byId.ContainsKey($id)) { $byId[$id] = New-Object System.Collections.Generic.List[int] }
        if (-not $byId[$id].Contains($sec.Y)) { $byId[$id].Add($sec.Y) }
      }
    }
  }
}

Write-Output ("dim=$Dim world=$World chunks=$chunks sections=$sections")
foreach ($k in ($byId.Keys | Sort-Object)) {
  $ys = ($byId[$k] | Sort-Object) -join ','
  Write-Output ("  {0}  sectionY={1}" -f $k, $ys)
}
