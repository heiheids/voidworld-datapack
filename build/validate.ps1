Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
. (Join-Path $PSScriptRoot 'lib\nbt.ps1')

$beh = Join-Path (Split-Path -Parent $PSScriptRoot) 'behavior'

# 1) JSON 语法
$jsonOk = 0; $jsonErr = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $beh -Recurse -Filter '*.json' | ForEach-Object {
  try { $null = (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json); $jsonOk++ }
  catch { $jsonErr.Add($_.Name + ' :: ' + $_.Exception.Message) }
}

# 2) NBT 模板结构（复用 build\lib\nbt.ps1 的大端解析器）
function Expand-IfGzip([byte[]]$Raw) {
  if ($Raw.Length -gt 2 -and $Raw[0] -eq 0x1F -and $Raw[1] -eq 0x8B) {
    $gz = New-Object System.IO.Compression.GZipStream((New-Object System.IO.MemoryStream(, $Raw)), [System.IO.Compression.CompressionMode]::Decompress)
    $mo = New-Object System.IO.MemoryStream
    $gz.CopyTo($mo); $gz.Dispose()
    return $mo.ToArray()
  }
  return $Raw
}

$nbtOk = 0; $nbtErr = New-Object System.Collections.Generic.List[string]
$nbtInfo = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath $beh -Recurse -Filter '*.nbt' | ForEach-Object {
  try {
    $raw = Expand-IfGzip ([System.IO.File]::ReadAllBytes($_.FullName))
    if ($null -eq $raw -or $raw.Length -lt 3) { throw 'too small' }
    $root = Read-NbtRoot $raw
    if (-not $root.ContainsKey('size')) { throw 'no size' }
    if (-not $root.ContainsKey('palette')) { throw 'no palette' }
    $size = ($root['size'] -join 'x')
    $pal = @($root['palette'])
    $blocks = 0
    if ($root.ContainsKey('blocks')) { $blocks = @($root['blocks']).Count }
    $nbtOk++
    if ($nbtOk -le 3) { $nbtInfo.Add($_.Name + ' size=' + $size + ' palette=' + $pal.Count + ' blocks=' + $blocks) }
  } catch { $nbtErr.Add($_.Name + ' :: ' + $_.Exception.Message) }
}

Write-Output ('json_ok=' + $jsonOk + ' json_err=' + $jsonErr.Count + ' nbt_ok=' + $nbtOk + ' nbt_err=' + $nbtErr.Count)
if ($nbtInfo.Count -gt 0) { Write-Output ('nbt_sample: ' + ($nbtInfo -join ' | ')) }
$jsonErr | Select-Object -First 5
$nbtErr | Select-Object -First 5
