param([string]$ConfigFile = 'config.json')
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$cfg = Get-Content (Join-Path $PSScriptRoot $ConfigFile) -Raw -Encoding UTF8 | ConvertFrom-Json
$ns = $cfg.namespace
$outRoot = Join-Path $root $cfg.output_dir
$distRoot = Join-Path $root $cfg.dist_dir
$dataDir = Join-Path $outRoot 'data'

function Ensure-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }

function Open-Zip([string]$path) { [System.IO.Compression.ZipFile]::OpenRead($path) }

function Read-EntryText($zip, [string]$name) {
  $e = $zip.GetEntry($name); if ($null -eq $e) { return $null }
  $sr = New-Object System.IO.StreamReader($e.Open()); $t = $sr.ReadToEnd(); $sr.Dispose(); return $t
}

function Read-EntryBytes($zip, [string]$name) {
  $e = $zip.GetEntry($name); if ($null -eq $e) { return $null }
  $ms = New-Object System.IO.MemoryStream; $e.Open().CopyTo($ms); return $ms.ToArray()
}

function Write-JsonFile([string]$path, $obj) {
  Ensure-Dir (Split-Path -Parent $path)
  $json = $obj | ConvertTo-Json -Depth 40 -Compress
  [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Json([string]$text) { return $text | ConvertFrom-Json }

function IdDir([string]$nsName, [string]$category) { return (Join-Path $dataDir (Join-Path $nsName (Join-Path 'worldgen' $category))) }

function BE2([int]$v) { $b = [System.BitConverter]::GetBytes([int16]$v); [Array]::Reverse($b); return [byte[]]$b }
function BE4([int]$v) { $b = [System.BitConverter]::GetBytes($v); [Array]::Reverse($b); return [byte[]]$b }
function NBT-W([System.IO.MemoryStream]$s, [byte[]]$b) { $s.Write($b, 0, $b.Length) }
function NBT-Tag([System.IO.MemoryStream]$s, [byte]$type, [string]$name) {
  $s.WriteByte($type)
  $nb = [System.Text.Encoding]::UTF8.GetBytes($name)
  NBT-W $s (BE2 $nb.Length); NBT-W $s $nb
}
function NBT-I([System.IO.MemoryStream]$s, [string]$name, [int]$v) {
  NBT-Tag $s 3 $name; NBT-W $s (BE4 $v)
}
function NBT-S([System.IO.MemoryStream]$s, [string]$name, [string]$v) {
  NBT-Tag $s 8 $name; $b = [System.Text.Encoding]::UTF8.GetBytes($v)
  NBT-W $s (BE2 $b.Length); NBT-W $s $b
}
function NBT-IntList([System.IO.MemoryStream]$s, [string]$name, [int[]]$vals) {
  NBT-Tag $s 9 $name; NBT-W $s ([byte]3)
  NBT-W $s (BE4 $vals.Length)
  foreach ($v in $vals) { NBT-W $s (BE4 $v) }
}
function NBT-End([System.IO.MemoryStream]$s) { $s.WriteByte(0) }

function New-PadNbt([int]$w, [int]$h, [int]$d, [string]$floorBlock, [int]$dataVersion) {
  $s = New-Object System.IO.MemoryStream
  NBT-Tag $s 10 ''
  NBT-IntList $s 'size' @($w, $h, $d)
  NBT-Tag $s 9 'entities'; NBT-W $s ([byte]0); NBT-W $s (BE4 0)
  $blocks = New-Object System.Collections.Generic.List[object]
  if (-not $floorBlock) { $blocks.Add(@{ p = @(0, 0, 0); st = 0 }) }
  else {
    for ($x = 0; $x -lt $w; $x++) { for ($z = 0; $z -lt $d; $z++) { $blocks.Add(@{ p = @($x, 0, $z); st = 1 }) } }
  }
  NBT-Tag $s 9 'blocks'
  NBT-W $s ([byte]10); NBT-W $s (BE4 $blocks.Count)
  foreach ($b in $blocks) { NBT-IntList $s 'pos' $b.p; NBT-I $s 'state' $b.st; NBT-End $s }
  NBT-Tag $s 9 ([string]$cfg.nbt.palette_key); NBT-W $s ([byte]10)
  $pal = @([string]$cfg.nbt.palette_air); if ($floorBlock) { $pal += $floorBlock }
  NBT-W $s (BE4 $pal.Count)
  foreach ($p in $pal) { NBT-S $s 'id' $p; NBT-End $s }
  NBT-I $s 'DataVersion' $dataVersion
  NBT-End $s
  return $s.ToArray()
}

function New-FloorMaterialRule([double]$FloorTop, [double]$MinY, [string]$Block) {
  # 只有地板层附近才允许放方块；其余高度整列不落方块。
  # 26.3 的条件节点用 then_run（无 else）；vertical_gradient 的高度用
  # above_bottom（相对 min_y）表示，写 absolute 会被忽略导致条件恒真。
  $below = [int]($FloorTop - $MinY)
  return [pscustomobject]@{
    type = 'minecraft:condition'
    if_true = [pscustomobject]@{
      type = 'minecraft:vertical_gradient'
      random_name = 'minecraft:floor'
      true_at_and_below = [pscustomobject]@{ above_bottom = $below }
      false_at_and_above = [pscustomobject]@{ above_bottom = ($below + 1) }
    }
    then_run = [pscustomobject]@{ type = 'minecraft:block'; result_state = $Block }
  }
}

$zip = Open-Zip $cfg.source.jar
$vj = Json (Read-EntryText $zip 'version.json')
$dfv = [int]$vj.world_version
$pf = [int]$vj.pack_version.data_major

# 每次生成前清空 data/ 与 pack.mcmeta，否则改 config 后旧文件会残留，
# 造成「配置关了但覆盖还在」的自相矛盾包（例如 end_spike 的 no_op 迟迟不消失）。
if (Test-Path -LiteralPath $dataDir) { Remove-Item -LiteralPath $dataDir -Recurse -Force }
$metaPath = Join-Path $outRoot 'pack.mcmeta'
if (Test-Path -LiteralPath $metaPath) { Remove-Item -LiteralPath $metaPath -Force }
Ensure-Dir $outRoot; Ensure-Dir $distRoot
Write-JsonFile (Join-Path $outRoot 'pack.mcmeta') ([pscustomobject]@{
  pack = [pscustomobject]@{ pack_format = $pf; min_format = $pf; max_format = $pf; description = $cfg.pack_description }
})

$stats = [pscustomobject]@{ feature_noop = 0; feature_keep = 0; structure_pad = 0; structure_keep = 0; pad_files = 0 }

$fdir = IdDir 'minecraft' 'feature'
Ensure-Dir $fdir
foreach ($en in $zip.Entries) {
  if ($en.FullName -notmatch '^data/minecraft/worldgen/feature/([^/]+)\.json$') { continue }
  $id = $Matches[1]
  if ($cfg.features.keep -contains $id) { $stats.feature_keep++; continue }
  Write-JsonFile (Join-Path $fdir ($id + '.json')) ([pscustomobject]@{ type = 'minecraft:no_op' })
  $stats.feature_noop++
}

$stripAllFeatures = ($cfg.features.PSObject.Properties.Name -contains 'strip_all_features') -and [bool]$cfg.features.strip_all_features
if ($stripAllFeatures -or ($cfg.features.strip_from_biomes -and @($cfg.features.strip_from_biomes).Count -gt 0)) {
  # 从生物群系自己的 features 列表里摘掉指定 placed_feature。
  # 原版就是靠这份列表决定生成什么，删掉即不会再触发，比把 configured feature
  # 换成 no_op 更可靠（实测 no_op 能加载但冰山仍会生成）。
  $strip = @($cfg.features.strip_from_biomes)
  $keepFeat = @($cfg.features.keep)
  $bdir = Join-Path (Join-Path $dataDir 'minecraft') 'worldgen/biome'
  Ensure-Dir $bdir
  $stats | Add-Member -NotePropertyName biome_strip -NotePropertyValue 0 -Force
  foreach ($en in $zip.Entries) {
    if ($en.FullName -notmatch '^data/minecraft/worldgen/biome/([^/]+)\.json$') { continue }
    $bname = $Matches[1]
    $bj = Json (Read-EntryText $zip $en.FullName)
    if ($stripAllFeatures) {
      # 洞穴/峡谷雕刻器会在世界底部灌岩浆（实测 y=-63..-56 全是 lava）。
      $bj.carvers = @()
    }
    $changed = $false
    $newSteps = New-Object System.Collections.ArrayList
    foreach ($step in $bj.features) {
      $orig = @($step)
      if ($stripAllFeatures) {
        # 只保留末地祭坛/柱子，其余全部摘掉：熔岩湖、冰山、矿脉、植被等一并消失。
        $kept = @($orig | Where-Object { $keepFeat -contains ($_ -replace '^[a-z0-9_]+:', '') })
      } else {
        $kept = @($orig | Where-Object { $strip -notcontains $_ })
      }
      if ($kept.Count -ne $orig.Count) { $changed = $true }
      [void]$newSteps.Add($kept)
    }
    if ($changed) {
      $bj.features = $newSteps.ToArray()
      Write-JsonFile (Join-Path $bdir ($bname + '.json')) $bj
      $stats.biome_strip++
    }
  }
}

# 阶段1：从“放置阶段”彻底阻断。configured feature 换成 no_op 仍可能被 placed_feature
# 的 placement 驱动，这里把 placed_feature 本身改成 no_op + 空 placement 列表。
# 需要一个“真实存在”的空特性 ID：minecraft:no_op 只是特性类型，不是已配置特性 ID。
$noopFeatDir = IdDir $ns 'feature'
Ensure-Dir $noopFeatDir
Write-JsonFile (Join-Path $noopFeatDir 'noop.json') ([pscustomobject]@{ type = 'minecraft:no_op' })

$noopPlaced = $true
if ($cfg.features.PSObject.Properties.Name -contains 'noop_placed_features') { $noopPlaced = [bool]$cfg.features.noop_placed_features }
if ($noopPlaced) {
  $pdir = IdDir 'minecraft' 'placed_feature'
  Ensure-Dir $pdir
  $keepPlaced = @()
  if ($cfg.features.PSObject.Properties.Name -contains 'keep_placed') { $keepPlaced = @($cfg.features.keep_placed) }
  $stats | Add-Member -NotePropertyName placed_noop -NotePropertyValue 0 -Force
  foreach ($en in $zip.Entries) {
    if ($en.FullName -notmatch '^data/minecraft/worldgen/placed_feature/([^/]+)\.json$') { continue }
    $placedId = $Matches[1]
    if ($keepPlaced -contains $placedId) { continue }
    # 保留原来的 feature 引用（no_op 只是特性“类型”，不是已配置特性“ID”，
    # 写成 minecraft:no_op 会让 worldgen/feature 注册表解析失败）。
    # 只把 placement 改成 count:0，等于该 placed_feature 永不放置。
    Write-JsonFile (Join-Path $pdir ($placedId + '.json')) ([pscustomobject]@{
      feature   = ($ns + ':noop')
      placement = @([pscustomobject]@{ type = 'minecraft:count'; count = 0 })
    })
    $stats.placed_noop++
  }
}


foreach ($dim in $cfg.dimensions) {
  $nsName = $dim.noise_settings
  $dtTxt = Read-EntryText $zip ('data/minecraft/dimension_type/' + $dim.dimension_type + '.json')
  $minY = [int]((Json $dtTxt).min_y)
  $denDir = Join-Path (IdDir $ns 'density_function') 'floor'; Ensure-Dir $denDir
  $denId = $ns + ':floor/' + $nsName
  if ($null -ne $dim.floor_top) {
    $denObj = [pscustomobject]@{ type = 'minecraft:gradient'; axis = 'y'; from_coordinate = [double]$dim.floor_top; from_value = [double]$dim.solid_density; to_coordinate = [double]($dim.floor_top + 1); to_value = [double](-$dim.solid_density) }
    $sea = $minY
  } else {
    $denObj = [pscustomobject]@{ type = 'minecraft:constant'; value = [double](-$dim.solid_density) }
    $sea = $minY
  }
  Write-JsonFile (Join-Path $denDir ($nsName + '.json')) $denObj
  $mrDir = Join-Path (IdDir $ns 'material_rule') 'surface'; Ensure-Dir $mrDir
  $mrId = $ns + ':surface/' + $nsName
  $blk = if ($null -ne $dim.floor_top) { $dim.floor_block } else { 'minecraft:air' }
  $mrObj = if ($null -ne $dim.floor_top) {
    [pscustomobject]@{ type = 'minecraft:block'; result_state = $blk }
  } else {
    [pscustomobject]@{ type = 'minecraft:block'; result_state = $blk }
  }
  Write-JsonFile (Join-Path $mrDir ($nsName + '.json')) $mrObj
  $nsObj = Json (Read-EntryText $zip ('data/minecraft/worldgen/noise_settings/' + $nsName + '.json'))
  $nsObj.sea_level = $sea
  $nsObj.default_fluid = 'minecraft:air'
  if ($null -ne $dim.floor_top) { $nsObj.default_block = $dim.floor_block }
  $nsObj.material_rule = $mrId
  $nsObj.noise_router.final_density = $denId
  if ($cfg.PSObject.Properties.Name -contains 'force_warm_biomes' -and $cfg.force_warm_biomes -and
      $nsObj.noise_router.PSObject.Properties.Name -contains 'temperature') {
    # 冰山只长在 frozen_ocean / deep_frozen_ocean。把气候噪声钉成暖干常量，
    # multi_noise 就永远选不到寒冷生物群系，冰山从源头消失。
    $clDir = Join-Path (IdDir $ns 'density_function') 'climate'
    Ensure-Dir $clDir
    Write-JsonFile (Join-Path $clDir 'temperature.json') ([pscustomobject]@{ type = 'minecraft:constant'; value = 1.0 })
    Write-JsonFile (Join-Path $clDir 'vegetation.json') ([pscustomobject]@{ type = 'minecraft:constant'; value = 0.0 })
    $nsObj.noise_router.temperature = $ns + ':climate/temperature'
    $nsObj.noise_router.vegetation = $ns + ':climate/vegetation'
  }
  if ($null -ne $dim.floor_top) {
    # 表面规则会按 chunk_surface_level 决定在哪些高度落方块。原版函数在虚空里
    # 仍会算出各种地表高度，导致台阶散落在半空；这里把它钉死在地板层。
    $slDir = Join-Path (IdDir $ns 'density_function') 'surface'; Ensure-Dir $slDir
    $slId = $ns + ':surface/' + $nsName
    Write-JsonFile (Join-Path $slDir ($nsName + '.json')) ([pscustomobject]@{
      type = 'minecraft:constant'
      value = [double]$dim.floor_top
    })
    $nsObj.noise_router.chunk_surface_level = $slId
    # 表面系统真正读取的是 <noise_settings>/preliminary_surface_level 这个原版函数，
    # 在虚空里它仍会算出各种地表高度；一并覆盖成常量地板高度。
    $psDir = Join-Path (Join-Path $dataDir 'minecraft') ('worldgen/density_function/' + $nsName); Ensure-Dir $psDir
    Write-JsonFile (Join-Path $psDir 'preliminary_surface_level.json') ([pscustomobject]@{
      type = 'minecraft:constant'
      value = [double]$dim.floor_top
    })
  }
  if ($cfg.aquifers -and $cfg.aquifers.disable_lava -and $nsObj.aquifers) {
    # 只把 lava 钉成 -1 仍会在世界底部产出岩浆；把决定流体位置的噪声一并钉成常量，
    # 让含水层整体不产流体。
    $neg = [pscustomobject]@{ type = 'minecraft:constant'; value = -1.0 }
    $nsObj.aquifers.lava = $neg
    $nsObj.aquifers.fluid_level_floodedness = $neg
    $nsObj.aquifers.fluid_level_spread = $neg
    $nsObj.aquifers.barrier = $neg
    if ($null -ne $dim.floor_top) {
      $nsObj.aquifers.surface_level = [pscustomobject]@{ type = 'minecraft:constant'; value = [double]$dim.floor_top }
    }
  }
  Write-JsonFile (Join-Path (IdDir 'minecraft' 'noise_settings') ($nsName + '.json')) $nsObj
}

foreach ($pname in $cfg.dimension_type_extra.PSObject.Properties.Name) {
  $extra = $cfg.dimension_type_extra.$pname
  $dtObj = Json (Read-EntryText $zip ('data/minecraft/dimension_type/' + $pname + '.json'))
  foreach ($k in $extra.PSObject.Properties.Name) { $dtObj.$k = $extra.$k }
  Write-JsonFile (Join-Path (Join-Path $dataDir 'minecraft') ('dimension_type/' + $pname + '.json')) $dtObj
}

# 末地黑曜石柱：原版 feature/end_spike.json 的 spikes 为空，柱子靠代码缓存生成，
# 在虚空维度里不会出现。这里按配置自建一份带明确 spike 列表的特征，并挂到生物群系。
if ($cfg.end_spikes -and $cfg.end_spikes.enabled -and $cfg.end_spikes.spikes) {
  $esId = [string]$cfg.end_spikes.feature_id
  $esBiome = [string]$cfg.end_spikes.biome
  Write-JsonFile (Join-Path (IdDir $ns 'feature') ($esId + '.json')) ([pscustomobject]@{
    type = 'minecraft:end_spike'
    spikes = @($cfg.end_spikes.spikes)
  })
  Write-JsonFile (Join-Path (IdDir $ns 'placed_feature') ($esId + '.json')) ([pscustomobject]@{
    feature = ($ns + ':' + $esId)
    placement = @([pscustomobject]@{ type = 'minecraft:biome' })
  })
  $biomeObj = Json (Read-EntryText $zip ('data/minecraft/worldgen/biome/' + $esBiome + '.json'))
  $oldId = 'minecraft:end_spike'
  $newId = $ns + ':' + $esId
  $steps = @()
  foreach ($step in $biomeObj.features) {
    $items = @()
    foreach ($f in @($step)) { $items += $(if ($f -eq $oldId) { $newId } else { $f }) }
    $steps += , $items
  }
  $biomeObj.features = $steps
  Write-JsonFile (Join-Path $dataDir ('minecraft/worldgen/biome/' + $esBiome + '.json')) $biomeObj
}

$stDir = IdDir 'minecraft' 'structure'
$poolDir = Join-Path (IdDir $ns 'template_pool') 'start'
$padDir = Join-Path $dataDir (Join-Path $ns 'structure')
Ensure-Dir $stDir; Ensure-Dir $poolDir; Ensure-Dir (Join-Path $padDir 'pad')

foreach ($en in $zip.Entries) {
  if ($en.FullName -notmatch '^data/minecraft/worldgen/structure/([^/]+)\.json$') { continue }
  $id = $Matches[1]
  $orig = Json (Read-EntryText $zip $en.FullName)
  $opt = $cfg.structure_defaults
  if ($cfg.structures.PSObject.Properties.Name -contains $id) {
    $e = $cfg.structures.$id
    $opt = [pscustomobject]@{
      action = $(if ($e.action) { $e.action } else { $cfg.structure_defaults.action })
      pad = $(if ($e.pad) { $e.pad } else { $cfg.structure_defaults.pad })
      pad_floor = $(if ($null -ne $e.pad_floor) { $e.pad_floor } else { $cfg.structure_defaults.pad_floor })
    }
  }
  if ($opt.action -eq 'keep') { $stats.structure_keep++; continue }
  $padId = $ns + ':pad/' + $id
  $poolId = $ns + ':start/' + $id
  $fb = if ($opt.pad_floor) { $cfg.structure_defaults.pad_floor_block } else { $null }
  $raw = New-PadNbt ([int]$opt.pad[0]) ([int]$opt.pad[1]) ([int]$opt.pad[2]) $fb $dfv
  $ms = New-Object System.IO.MemoryStream
  $gz = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionLevel]::Optimal)
  $gz.Write($raw, 0, $raw.Length); $gz.Dispose()
  [System.IO.File]::WriteAllBytes((Join-Path (Join-Path $padDir 'pad') ($id + '.nbt')), $ms.ToArray())
  $stats.pad_files++
  Write-JsonFile (Join-Path $poolDir ($id + '.json')) ([pscustomobject]@{
    elements = @([pscustomobject]@{ weight = 1; element = [pscustomobject]@{
      element_type = 'minecraft:legacy_single_pool_element'; location = $padId; projection = 'rigid'; processors = 'minecraft:empty' } })
    fallback = $(if ($cfg.structure_defaults.fallback_pool) { [string]$cfg.structure_defaults.fallback_pool } else { $poolId })
  })
  $sd = $cfg.structure_defaults
  $new = [ordered]@{ type = 'minecraft:jigsaw'; biomes = $orig.biomes; step = $orig.step; start_pool = $poolId; size = [int]$sd.max_pieces }
  if ($null -ne $orig.max_distance_from_center) { $new.max_distance_from_center = $orig.max_distance_from_center } else { $new.max_distance_from_center = [int]$sd.max_distance_from_center }
  $new.start_height = $sd.start_height
  if ($sd.project_to_heightmap) { $new.project_start_to_heightmap = $sd.project_to_heightmap }
  $new.use_expansion_hack = [bool]$sd.use_expansion_hack
  $new.terrain_adaptation = $sd.terrain_adaptation
  $new.spawn_overrides = $(if ($null -ne $orig.spawn_overrides) { $orig.spawn_overrides } else { [pscustomobject]@{} })
  Write-JsonFile (Join-Path $stDir ($id + '.json')) $new
  $stats.structure_pad++
}
if (Test-Path (Join-Path $PSScriptRoot 'altar.ps1')) { & (Join-Path $PSScriptRoot 'altar.ps1') }

$zip.Dispose()

$name = $cfg.pack_name + '_v' + $vj.id + '.zip'
$zipPath = Join-Path $distRoot $name
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($outRoot, $zipPath)
Write-Output ('pack_format=' + $pf + ' data_version=' + $dfv + ' ' + ($stats | ConvertTo-Json -Compress) + ' zip=' + $name)
