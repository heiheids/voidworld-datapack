param(
  [string]$World = 'lava_seed',
  [string]$Dim = 'the_end',
  [int]$X1 = -8,
  [int]$X2 = 8,
  [int]$Y1 = 40,
  [int]$Y2 = 90,
  [int]$Z1 = -8,
  [int]$Z2 = 8,
  [int]$First = 0
)
# 按坐标范围列出非空气方块（用于确认末地祭坛等定点结构是否存在）。
# 解码方式与 blockcount.ps1 保持一致。
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\nbt.ps1')
. (Join-Path $PSScriptRoot 'lib\region.ps1')

$regDir = Join-Path $root (Join-Path 'test' (Join-Path $World ('dimensions\minecraft\' + $Dim + '\region')))
if (-not (Test-Path -LiteralPath $regDir)) { Write-Output ('missing ' + $regDir); exit 1 }

$hits = New-Object System.Collections.ArrayList
foreach ($mca in (Get-ChildItem -LiteralPath $regDir -Filter '*.mca' -File)) {
  if ($mca.Name -notmatch 'r\.(-?\d+)\.(-?\d+)\.mca$') { continue }
  $rx = [int]$Matches[1]; $rz = [int]$Matches[2]
  foreach ($ch in (Get-RegionChunkBytes $mca.FullName)) {
    $gx = $rx * 32 + [int]$ch.X; $gz = $rz * 32 + [int]$ch.Z
    $bx0 = $gx * 16; $bz0 = $gz * 16
    if (($bx0 + 15) -lt $X1 -or $bx0 -gt $X2) { continue }
    if (($bz0 + 15) -lt $Z1 -or $bz0 -gt $Z2) { continue }
    $nbt = $null
    try { $nbt = Read-NbtRoot $ch.Bytes } catch { continue }
    if (-not $nbt.ContainsKey('sections')) { continue }
    foreach ($sec in $nbt['sections']) {
      if (-not ($sec -is [hashtable])) { continue }
      if (-not $sec.ContainsKey('block_states')) { continue }
      $bs = $sec['block_states']
      if (-not ($bs -is [hashtable]) -or -not $bs.ContainsKey('palette')) { continue }
      $ids = @()
      foreach ($p in $bs['palette']) {
        if ($p -is [string]) { $ids += $p } elseif ($p -is [hashtable] -and $p.ContainsKey('Name')) { $ids += [string]$p['Name'] }
      }
      if ($ids.Count -eq 0) { continue }
      $secY = 0; if ($sec.ContainsKey('Y')) { $secY = [int]$sec['Y'] }
      $gy0 = $secY * 16
      if (($gy0 + 15) -lt $Y1 -or $gy0 -gt $Y2) { continue }
      $bits = 4
      while (([Math]::Pow(2, $bits)) -lt $ids.Count) { $bits++ }
      $perLong = [Math]::Floor(64 / $bits)
      $mask = ([int64]1 -shl $bits) - 1
      $data = $null; if ($bs.ContainsKey('data')) { $data = $bs['data'] }
      for ($i = 0; $i -lt 4096; $i++) {
        if ($ids.Count -eq 1) {
          $id = $ids[0]
        } else {
          $li = [int][Math]::Floor($i / $perLong)
          if ($null -eq $data -or $li -ge $data.Length) { break }
          $v = ([int64]$data[$li] -shr (($i % $perLong) * $bits)) -band $mask
          if ($v -ge $ids.Count) { continue }
          $id = $ids[[int]$v]
        }
        if ($id -eq 'minecraft:air') { continue }
        $lx = $i % 16
        $lz = [int][Math]::Floor($i / 16) % 16
        $ly = [int][Math]::Floor($i / 256)
        $wx = $bx0 + $lx; $wy = $gy0 + $ly; $wz = $bz0 + $lz
        if ($wx -lt $X1 -or $wx -gt $X2) { continue }
        if ($wy -lt $Y1 -or $wy -gt $Y2) { continue }
        if ($wz -lt $Z1 -or $wz -gt $Z2) { continue }
        [void]$hits.Add([pscustomobject]@{ X = $wx; Y = $wy; Z = $wz; Id = $id })
      }
    }
  }
}

Write-Output ('world={0} dim={1} blocks={2} 范围 X[{3}..{4}] Y[{5}..{6}] Z[{7}..{8}]' -f $World, $Dim, $hits.Count, $X1, $X2, $Y1, $Y2, $Z1, $Z2)
Write-Output '--- 按方块种类:'
$hits | Group-Object Id | Sort-Object Count -Descending | ForEach-Object { Write-Output ('  {0} x{1}' -f $_.Name, $_.Count) }
Write-Output '--- 按 Y 层:'
$hits | Group-Object Y | Sort-Object { [int]$_.Name } | ForEach-Object { Write-Output ('  y={0} x{1}' -f $_.Name, $_.Count) }
if ($First -gt 0) {
  Write-Output '--- 前若干方块:'
  $hits | Sort-Object Y, X, Z | Select-Object -First $First | ForEach-Object { Write-Output ('  {0} {1} {2}  {3}' -f $_.X, $_.Y, $_.Z, $_.Id) }
}
