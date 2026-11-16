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
  (Join-Path $csPlacedDir 'center_spike.json'),
  (Join-Path (Join-Path (Join-Path $dataDir $csNs) 'function') 'center_crystal_cleanup.mcfunction'),
  (Join-Path (Join-Path (Join-Path (Join-Path $dataDir 'minecraft') 'tags\function') '') 'tick.json')
)
if (-not $csEnabled) {
  foreach ($f in $csFiles) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
  return
}
$csHeight = 62
if ($csCfg -and $null -ne $csCfg.height) { $csHeight = [int]$csCfg.height }
$csGuarded = $false
if ($csCfg -and $null -ne $csCfg.guarded) { $csGuarded = [bool]$csCfg.guarded }
$csRadius = 0
if ($csCfg -and $null -ne $csCfg.radius) { $csRadius = [int]$csCfg.radius }
Write-JsonFile (Join-Path $csFeatDir 'center_spike.json') ([pscustomobject]@{
  type   = 'minecraft:end_spike'
  spikes = @([pscustomobject]@{
    centerX = 0
    centerZ = 0
    radius  = $csRadius
    height  = $csHeight
    guarded = $csGuarded
  })
})
Write-JsonFile (Join-Path $csPlacedDir 'center_spike.json') ([pscustomobject]@{
  feature   = ($csNs + ':center_spike')
  placement = @([pscustomobject]@{ type = 'minecraft:count'; count = 1 })
})
# 中心柱顶端会生成末影水晶（EndSpikeFeature 在 guarded=false 时创建 END_CRYSTAL），
# 它会给末影龙回血且视觉上多余。用 tick 函数清除中心附近的水晶；
# 半径 8 只覆盖中心，不影响半径约 42 处的 10 个原版柱水晶。
$csFuncDir = Join-Path (Join-Path $dataDir $csNs) 'function'
$csTagsRoot = Join-Path (Join-Path $dataDir 'minecraft') 'tags'
$csTagDir = Join-Path $csTagsRoot 'function'
New-Item -ItemType Directory -Path $csFuncDir -Force | Out-Null
New-Item -ItemType Directory -Path $csTagDir -Force | Out-Null
$csMc = "execute in minecraft:the_end positioned 0 62 0 run kill @e[type=minecraft:end_crystal,distance=..8]"
[System.IO.File]::WriteAllText((Join-Path $csFuncDir 'center_crystal_cleanup.mcfunction'), $csMc, (New-Object System.Text.UTF8Encoding($false)))
Write-JsonFile (Join-Path $csTagDir 'tick.json') ([pscustomobject]@{ values = @(($csNs + ':center_crystal_cleanup')) })