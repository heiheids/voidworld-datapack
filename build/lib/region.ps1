# 区域文件（.mca）读取：只负责把每个区块解压成 NBT 字节数组。
# 依赖 lib\nbt.ps1

function Expand-ChunkPayload([byte[]]$Data, [int]$Comp) {
  # 26.3 的区块压缩标记可能为 1(gzip) / 2(zlib) / 3(未压缩) / 4(LZ4)。
  # .NET 的 DeflateStream 只吃裸 deflate，ZLibStream 吃 zlib（含头部与校验）。
  # 这里按优先级逐个尝试，成功的第一个即为结果。
  $cands = New-Object System.Collections.Generic.List[object]
  if ($Comp -eq 3) { return $Data }
  if ($Comp -eq 2) {
    $cands.Add(@{ S = 'zlib'; D = $Data })
    if ($Data.Length -gt 2) { $cands.Add(@{ S = 'deflate2'; D = $Data[2..($Data.Length - 1)] }) }
    $cands.Add(@{ S = 'deflate'; D = $Data })
  } elseif ($Comp -eq 1) {
    $cands.Add(@{ S = 'gzip'; D = $Data })
  } else {
    return $null
  }
  foreach ($c in $cands) {
    try {
      $ms = New-Object System.IO.MemoryStream(, [byte[]]$c.D)
      $sr = $null
      switch ($c.S) {
        'zlib' { $sr = New-Object System.IO.Compression.ZLibStream($ms, [System.IO.Compression.CompressionMode]::Decompress) }
        'gzip' { $sr = New-Object System.IO.Compression.GZipStream($ms, [System.IO.Compression.CompressionMode]::Decompress) }
        default { $sr = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress) }
      }
      $mo = New-Object System.IO.MemoryStream
      $sr.CopyTo($mo); $sr.Dispose()
      $out = $mo.ToArray()
      if ($out.Length -gt 0) { return $out }
    } catch { continue }
  }
  return $null
}

function Get-RegionChunkBytes([string]$Path) {
  Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $out = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt 1024; $i++) {
    $off = ([int]$bytes[$i * 4] -shl 16) -bor ([int]$bytes[$i * 4 + 1] -shl 8) -bor ([int]$bytes[$i * 4 + 2])
    if ($off -le 0) { continue }
    $st = $off * 4096
    if ($st + 5 -ge $bytes.Length) { continue }
    $len = ([int]$bytes[$st] -shl 24) -bor ([int]$bytes[$st + 1] -shl 16) -bor ([int]$bytes[$st + 2] -shl 8) -bor ([int]$bytes[$st + 3])
    $comp = [int]$bytes[$st + 4]
    if ($len -le 1) { continue }
    $data = New-Object byte[] ($len - 1)
    [Array]::Copy($bytes, $st + 5, $data, 0, $len - 1)
    $data = Expand-ChunkPayload $data $comp
    if ($null -eq $data) { continue }
    $out.Add([pscustomobject]@{ X = ($i % 32); Z = [int][Math]::Floor($i / 32); Bytes = $data })
  }
  return $out
}

# 每个 section 的 Y 与其调色板方块 id 列表
function Get-SectionPalettes($Root) {
  $res = New-Object System.Collections.Generic.List[object]
  if ($null -eq $Root -or -not ($Root -is [hashtable])) { return $res }
  if (-not $Root.ContainsKey('sections')) { return $res }
  $sections = $Root['sections']
  if ($null -eq $sections) { return $res }
  foreach ($sec in $sections) {
    if (-not ($sec -is [hashtable])) { continue }
    $y = 0
    if ($sec.ContainsKey('Y')) { $y = [int]$sec['Y'] }
    $ids = New-Object System.Collections.Generic.List[string]
    if ($sec.ContainsKey('block_states')) {
      $bs = $sec['block_states']
      if ($bs -is [hashtable] -and $bs.ContainsKey('palette')) {
        foreach ($p in $bs['palette']) {
          # 26.3: palette 元素是纯字符串；旧版: {Name:"..."} 复合体
          if ($p -is [string]) { $ids.Add($p) }
          elseif ($p -is [hashtable] -and $p.ContainsKey('Name')) { $ids.Add([string]$p['Name']) }
        }
      }
    }
    if ($ids.Count -gt 0) { $res.Add([pscustomobject]@{ Y = $y; Ids = $ids }) }
  }
  return $res
}
