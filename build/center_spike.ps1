# 末地中心柱：用固定坐标的 end_spike 抬高中心列的高度图。
# 原版祭坛位置 = getHeightmapPos(MOTION_BLOCKING, origin)，虚空里会落到世界底部；
# 在 (0,0) 放一根柱子即可让高度图返回目标高度。

$csNs = $ns
$csCfg = $cfg.features.center_spike
$csEnabled = $true
if ($csCfg) { $csEnabled = [bool]$csCfg.enabled }
$csFeatDir = IdDir $csNs 'feature'
$csPlacedDir = IdDir $csNs 'placed_feature'
Ensure-Dir $csFeatDir
Ensure-Dir $csPlacedDir
$csFiles = @(
  (Join-Path $csFeatDir 'center_spike.json'),
  (Join-Path $csPlacedDir 'center_spike.json')
)
if (-not $csEnabled) {
  foreach ($f in $csFiles) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
  return
}
$csHeight = 62
if ($csCfg -and $null -ne $csCfg.height) { $csHeight = [int]$csCfg.height }
$csRadius = 0
if ($csCfg -and $null -ne $csCfg.radius) { $csRadius = [int]$csCfg.radius }
Write-JsonFile (Join-Path $csFeatDir 'center_spike.json') ([pscustomobject]@{
  type   = 'minecraft:end_spike'
  spikes = @([pscustomobject]@{
    centerX = 0
    centerZ = 0
    radius  = $csRadius
    height  = $csHeight
    guarded = $false
  })
})
Write-JsonFile (Join-Path $csPlacedDir 'center_spike.json') ([pscustomobject]@{
  feature   = ($csNs + ':center_spike')
  placement = @([pscustomobject]@{ type = 'minecraft:count'; count = 1 })
})
