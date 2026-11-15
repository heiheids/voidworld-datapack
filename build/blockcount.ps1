param(
  [string]$World = 'voidtest',
  [string]$Dim = 'overworld',
  [string]$ConfigFile = 'config.json'
)
# 逐 Y 精确统计方块数量：解码 block_states.data 的打包长整型。
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\nbt.ps1')
. (Join-Path $PSScriptRoot 'lib\region.ps1')
$cfg = Get-Content (Join-Path $PSScriptRoot $ConfigFile) -Raw -Encoding UTF8 | ConvertFrom-Json

$regDir = Join-Path $root (Join-Path 'test' (Join-Path $World ('dimensions\minecraft\' + $Dim + '\region')))
if (-not (Test-Path -LiteralPath $regDir)) { Write-Output ('missing ' + $regDir); exit 1 }

# 结果: id -> @{ total; ys = @{y=count} }
$stat = @{}
$chunks = 0
foreach ($mca in (Get-ChildItem -LiteralPath $regDir -Filter '*.mca' -File)) {
  foreach ($ch in (Get-RegionChunkBytes $mca.FullName)) {
    $nbtRoot = $null
    try { $nbtRoot = Read-NbtRoot $ch.Bytes } catch { continue }
    $chunks++
    if (-not $nbtRoot.ContainsKey('sections')) { continue }
    foreach ($sec in $nbtRoot['sections']) {
      if (-not ($sec -is [hashtable])) { continue }
      if (-not $sec.ContainsKey('block_states')) { continue }
      $bs = $sec['block_states']
      if (-not ($bs -is [hashtable]) -or -not $bs.ContainsKey('palette')) { continue }
      $ids = @(); foreach ($p in $bs['palette']) { if ($p -is [string]) { $ids += $p } elseif ($p -is [hashtable] -and $p.ContainsKey('Name')) { $ids += [string]$p['Name'] } }
      if ($ids.Count -eq 0) { continue }
      $secY = 0; if ($sec.ContainsKey('Y')) { $secY = [int]$sec['Y'] }
      $bits = 4
      while (([Math]::Pow(2, $bits)) -lt $ids.Count) { $bits++ }
      $perLong = [Math]::Floor(64 / $bits)
      $mask = ([int64]1 -shl $bits) - 1
      $data = $null; if ($bs.ContainsKey('data')) { $data = $bs['data'] }
      if ($null -eq $data -or $ids.Count -eq 1) {
        # 单一调色板：整段都是该方块
        $id = $ids[0]
        if (-not $stat.ContainsKey($id)) { $stat[$id] = @{ total = 0; ys = @{} } }
        $stat[$id].total += 4096
        for ($y = 0; $y -lt 16; $y++) { $gy = $secY * 16 + $y; if (-not $stat[$id].ys.ContainsKey($gy)) { $stat[$id].ys[$gy] = 0 }; $stat[$id].ys[$gy] += 256 }
        continue
      }
      for ($i = 0; $i -lt 4096; $i++) {
        $li = [int][Math]::Floor($i / $perLong)
        if ($li -ge $data.Length) { break }
        $off = ($i % $perLong) * $bits
        $v = ([int64]$data[$li] -shr $off) -band $mask
        if ($v -ge $ids.Count) { continue }
        $id = $ids[[int]$v]
        if (-not $stat.ContainsKey($id)) { $stat[$id] = @{ total = 0; ys = @{} } }
        $stat[$id].total++
        $gy = $secY * 16 + [int][Math]::Floor($i / 256)
        if (-not $stat[$id].ys.ContainsKey($gy)) { $stat[$id].ys[$gy] = 0 }
        $stat[$id].ys[$gy]++
      }
    }
  }
}

Write-Output ("dim=$Dim world=$World chunks=$chunks")
foreach ($id in ($stat.Keys | Sort-Object)) {
  $e = $stat[$id]
  $ys = ($e.ys.Keys | Sort-Object)
  $desc = ($ys | ForEach-Object { "$_=$($e.ys[$_])" }) -join ' '
  Write-Output ("  {0} total={1}" -f $id, $e.total)
  Write-Output ("      {0}" -f $desc)
}
