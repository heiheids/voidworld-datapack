# 末地中心祭坛：7x7 末地石基座 + 黑曜石/基岩/龙蛋祭坛
# 由 generate.ps1 在打包前调用，复用其 NBT 写入函数与作用域变量（$cfg/$ns/$dataDir/$dfv）。

$altarNs = $ns
$altarTemplateDir = Join-Path (Join-Path $dataDir (Join-Path $altarNs 'structure')) 'altar'
Ensure-Dir $altarTemplateDir

function New-AltarNbt([string[]]$palette, [object[]]$blocks, [int[]]$size, [int]$dataVersion) {
  $ms = New-Object System.IO.MemoryStream
  NBT-Tag $ms 10 ''
  NBT-IntList $ms 'size' $size
  NBT-Tag $ms 9 'entities'; NBT-W $ms ([byte]0); NBT-W $ms (BE4 0)
  NBT-Tag $ms 9 'blocks'; NBT-W $ms ([byte]10); NBT-W $ms (BE4 $blocks.Count)
  foreach ($b in $blocks) { NBT-IntList $ms 'pos' $b.p; NBT-I $ms 'state' $b.st; NBT-End $ms }
  NBT-Tag $ms 9 'palette'; NBT-W $ms ([byte]10); NBT-W $ms (BE4 $palette.Count)
  foreach ($p in $palette) { NBT-S $ms 'id' $p; NBT-End $ms }
  NBT-I $ms 'DataVersion' $dataVersion
  NBT-End $ms
  return $ms.ToArray()
}

$palette = @('minecraft:air', 'minecraft:end_stone', 'minecraft:obsidian', 'minecraft:bedrock', 'minecraft:dragon_egg')
$blocks = New-Object System.Collections.Generic.List[object]
for ($x = 0; $x -lt 7; $x++) {
  for ($z = 0; $z -lt 7; $z++) { $blocks.Add([pscustomobject]@{ p = @($x, 0, $z); st = 1 }) }
}
for ($x = 2; $x -le 4; $x++) {
  for ($z = 2; $z -le 4; $z++) { $blocks.Add([pscustomobject]@{ p = @($x, 1, $z); st = 2 }) }
}
foreach ($c in @(@(2, 2, 2), @(4, 2, 2), @(2, 2, 4), @(4, 2, 4))) {
  $blocks.Add([pscustomobject]@{ p = $c; st = 3 })
}
$blocks.Add([pscustomobject]@{ p = @(3, 2, 3); st = 4 })

$raw = New-AltarNbt $palette $blocks.ToArray() @(7, 5, 7) $dfv
$ms2 = New-Object System.IO.MemoryStream
$gz = New-Object System.IO.Compression.GZipStream($ms2, [System.IO.Compression.CompressionLevel]::Optimal)
$gz.Write($raw, 0, $raw.Length); $gz.Dispose()
[System.IO.File]::WriteAllBytes((Join-Path $altarTemplateDir 'altar.nbt'), $ms2.ToArray())

$altarPoolDir = Join-Path (IdDir $altarNs 'template_pool') 'altar'
Ensure-Dir $altarPoolDir
Write-JsonFile (Join-Path $altarPoolDir 'start.json') ([pscustomobject]@{
  elements = @([pscustomobject]@{ weight = 1; element = [pscustomobject]@{
    element_type = 'minecraft:legacy_single_pool_element'
    location     = ($altarNs + ':altar/altar')
    projection   = 'rigid'
    processors   = 'minecraft:empty' } })
  fallback = ($altarNs + ':altar/start')
})

$altarStDir = IdDir $altarNs 'structure'
Ensure-Dir $altarStDir
Write-JsonFile (Join-Path $altarStDir 'end_altar.json') ([pscustomobject]@{
  type                     = 'minecraft:jigsaw'
  biomes                   = @('minecraft:the_end')
  step                     = 'surface_structures'
  start_pool               = ($altarNs + ':altar/start')
  size                     = 1
  start_height             = [pscustomobject]@{ absolute = 60 }
  max_distance_from_center = 1
  use_expansion_hack       = $false
  terrain_adaptation       = 'none'
  spawn_overrides          = [pscustomobject]@{}
})

$altarSetDir = IdDir $altarNs 'structure_set'
Ensure-Dir $altarSetDir
Write-JsonFile (Join-Path $altarSetDir 'end_altar.json') ([pscustomobject]@{
      placement  = [pscustomobject]@{
    type             = 'minecraft:concentric_rings'
    count            = 1
    distance         = 0
    spread           = 1
    salt             = 0
    preferred_biomes = '#vw:end_altar'
  }
  structures = @([pscustomobject]@{ structure = ($altarNs + ':end_altar'); weight = 1 })
})

$altarTagDir = Join-Path (Join-Path (Join-Path $dataDir $altarNs) 'tags\worldgen') 'biome'
Ensure-Dir $altarTagDir
Write-JsonFile (Join-Path $altarTagDir 'end_altar.json') ([pscustomobject]@{ values = @(
  'minecraft:the_end',
  'minecraft:end_highlands',
  'minecraft:end_midlands',
  'minecraft:small_end_islands',
  'minecraft:end_barrens'
) })
