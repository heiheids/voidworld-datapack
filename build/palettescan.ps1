param(
  [Parameter(Mandatory = $true)][string]$RegionDir,
  [string[]]$Watch = @('minecraft:ice','minecraft:packed_ice','minecraft:blue_ice','minecraft:snow_block','minecraft:snow'),
  [string[]]$Marker = @('minecraft:smooth_stone_slab','minecraft:stone','minecraft:water'),
  [int]$MaxHit = 25
)
# 只读取每个区段的调色板（不解码 block_states.data），用于快速判断：
#   1) 存档里有没有冰/雪类方块，出现在哪些区块；
#   2) 这些区块是"数据包虚空世界"（含 smooth_stone_slab）还是"原版地形"（含 stone/water）。
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\nbt.ps1')
. (Join-Path $PSScriptRoot 'lib\region.ps1')

if (-not (Test-Path -LiteralPath $RegionDir)) { Write-Output ('region 目录不存在: ' + $RegionDir); exit 1 }

$idCount = @{}
$hitChunks = @{}
$markerChunks = @{}
$chunksTotal = 0

foreach ($mca in (Get-ChildItem -LiteralPath $RegionDir -Filter '*.mca' -File)) {
  $base = [System.IO.Path]::GetFileNameWithoutExtension($mca.Name)
  $parts = $base.Split('.')
  $rx = 0; $rz = 0
  if ($parts.Length -ge 3) { $rx = [int]$parts[1]; $rz = [int]$parts[2] }
  foreach ($ch in (Get-RegionChunkBytes $mca.FullName)) {
    $chunksTotal++
    $gx = $rx * 32 + $ch.X
    $gz = $rz * 32 + $ch.Z
    $nbt = $null
    try { $nbt = Read-NbtRoot $ch.Bytes } catch { continue }
    if (-not $nbt.ContainsKey('sections')) { continue }
    foreach ($sec in $nbt['sections']) {
      if (-not ($sec -is [hashtable]) -or -not $sec.ContainsKey('block_states')) { continue }
      $bs = $sec['block_states']
      if (-not ($bs -is [hashtable]) -or -not $bs.ContainsKey('palette')) { continue }
      foreach ($p in $bs['palette']) {
        $id = $null
        if ($p -is [string]) { $id = $p } elseif ($p -is [hashtable] -and $p.ContainsKey('Name')) { $id = [string]$p['Name'] }
        if (-not $id) { continue }
        if ($idCount.ContainsKey($id)) { $idCount[$id]++ } else { $idCount[$id] = 1 }
        if ($Watch -contains $id) { $k = "$gx,$gz"; if (-not $hitChunks.ContainsKey($k)) { $hitChunks[$k] = @() }; if ($hitChunks[$k] -notcontains $id) { $hitChunks[$k] += $id } }
        if ($Marker -contains $id) { $k = "$gx,$gz"; if (-not $markerChunks.ContainsKey($k)) { $markerChunks[$k] = @() }; if ($markerChunks[$k] -notcontains $id) { $markerChunks[$k] += $id } }
      }
    }
  }
}

Write-Output ("chunks=" + $chunksTotal + " distinct_ids=" + $idCount.Count + " ice_chunks=" + $hitChunks.Count)
Write-Output '--- 冰块命中区块（区块坐标, 方块坐标=chunk*16）:'
$n = 0
foreach ($k in ($hitChunks.Keys | Sort-Object)) {
  $n++; if ($n -gt $MaxHit) { break }
  $xz = $k.Split(','); $cx = [int]$xz[0]; $cz = [int]$xz[1]
  $mk = if ($markerChunks.ContainsKey($k)) { $markerChunks[$k] -join '+' } else { 'none' }
  Write-Output ('  chunk={0},{1} block={2},{3} ids={4} | 标记={5}' -f $cx, $cz, ($cx * 16), ($cz * 16), ($hitChunks[$k] -join ','), $mk)
}
Write-Output '--- 前 12 个方块 id（按区段出现次数）:'
$idCount.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 12 | ForEach-Object { '  {0} = {1}' -f $_.Key, $_.Value }
