param(
  [string]$World = 'voidtest',
  [string]$Dim = 'the_end',
  [string]$BlockId = 'minecraft:obsidian',
  [int]$Max = 40,
  [string]$ConfigFile = 'config.json'
)
# 转储指定方块的实际坐标，用于判断结构形状（如末地柱子的粗细/高度）。
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\nbt.ps1')
. (Join-Path $PSScriptRoot 'lib\region.ps1')

$regDir = Join-Path $root (Join-Path 'test' (Join-Path $World ('dimensions\minecraft\' + $Dim + '\region')))
if (-not (Test-Path -LiteralPath $regDir)) { Write-Output ('missing ' + $regDir); exit 1 }

$hits = New-Object System.Collections.Generic.List[object]
$byXZ = @{}
foreach ($mca in (Get-ChildItem -LiteralPath $regDir -Filter '*.mca' -File)) {
  foreach ($ch in (Get-RegionChunkBytes $mca.FullName)) {
    $nbtRoot = $null
    try { $nbtRoot = Read-NbtRoot $ch.Bytes } catch { continue }
    if (-not $nbtRoot.ContainsKey('sections')) { continue }
    $baseX = $ch.X * 16; $baseZ = $ch.Z * 16
    foreach ($sec in $nbtRoot['sections']) {
      if (-not ($sec -is [hashtable]) -or -not $sec.ContainsKey('block_states')) { continue }
      $bs = $sec['block_states']
      if (-not ($bs -is [hashtable]) -or -not $bs.ContainsKey('palette')) { continue }
      $ids = @(); foreach ($p in $bs['palette']) { if ($p -is [string]) { $ids += $p } elseif ($p -is [hashtable] -and $p.ContainsKey('Name')) { $ids += [string]$p['Name'] } }
      $idx = [Array]::IndexOf($ids, $BlockId)
      if ($idx -lt 0) { continue }
      $secY = 0; if ($sec.ContainsKey('Y')) { $secY = [int]$sec['Y'] }
      $data = $null; if ($bs.ContainsKey('data')) { $data = $bs['data'] }
      $bits = 4; while (([Math]::Pow(2, $bits)) -lt $ids.Count) { $bits++ }
      $perLong = [Math]::Floor(64 / $bits); $mask = ([int64]1 -shl $bits) - 1
      for ($i = 0; $i -lt 4096; $i++) {
        if ($ids.Count -eq 1) { $v = 0 } else {
          $li = [int][Math]::Floor($i / $perLong)
          if ($null -eq $data -or $li -ge $data.Length) { break }
          $v = ([int64]$data[$li] -shr (($i % $perLong) * $bits)) -band $mask
        }
        if ($v -ne $idx) { continue }
        $lx = $i % 16; $lz = [int][Math]::Floor($i / 16) % 16; $ly = [int][Math]::Floor($i / 256)
        $gx = $baseX + $lx; $gz = $baseZ + $lz; $gy = $secY * 16 + $ly
        $key = "$gx,$gz"
        if (-not $byXZ.ContainsKey($key)) { $byXZ[$key] = New-Object System.Collections.Generic.List[int] }
        $byXZ[$key].Add($gy)
        if ($hits.Count -lt 100000) { $hits.Add([pscustomobject]@{ X = $gx; Y = $gy; Z = $gz }) }
      }
    }
  }
}

Write-Output ("block=$BlockId hits=" + $hits.Count + " columns=" + $byXZ.Count)
$n = 0
foreach ($k in ($byXZ.Keys | Sort-Object)) {
  $n++; if ($n -gt $Max) { break }
  $ys = $byXZ[$k] | Sort-Object
  Write-Output ("  xz={0} ymin={1} ymax={2} count={3}" -f $k, $ys[0], $ys[$ys.Count - 1], $ys.Count)
}
