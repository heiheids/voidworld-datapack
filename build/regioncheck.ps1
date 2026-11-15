param([string]$World = 'voidtest', [string]$Dim = 'overworld', [string]$RegionX = '0', [string]$RegionZ = '0', [switch]$Detail)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$base = Join-Path (Split-Path -Parent $PSScriptRoot) 'test'
$reg = Join-Path $base ($World + '\dimensions\minecraft\' + $Dim + '\region\r.' + $RegionX + '.' + $RegionZ + '.mca')
if (-not (Test-Path -LiteralPath $reg)) { Write-Output ('missing ' + $reg); exit 1 }
$fsIn = [System.IO.File]::Open($reg, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$bytes = New-Object byte[] $fsIn.Length; $fsIn.Read($bytes, 0, $bytes.Length) | Out-Null; $fsIn.Dispose()

function Rb($fs, [int]$n) { if ($n -le 0) { return (New-Object byte[] 0) }; $b = New-Object byte[] $n; for ($i = 0; $i -lt $n; $i++) { $x = $fs.ReadByte(); if ($x -lt 0) { throw ('eof at ' + $script:lastPath) }; $b[$i] = [byte]$x }; return $b }
function RI($fs) { return [System.BitConverter]::ToInt32((Rb $fs 4), 0) }
function RS($fs) { $l = [System.BitConverter]::ToUInt16((Rb $fs 2), 0); if ($l -le 0) { return '' }; return [System.Text.Encoding]::UTF8.GetString((Rb $fs $l)) }
$script:acc = @{}
function RN($fs, [byte]$t, [string]$path) {
  $script:lastPath = $path
  switch ($t) {
    0 {}
    1 { $script:acc[$path] = (Rb $fs 1)[0] }
    2 { $script:acc[$path] = [System.BitConverter]::ToUInt16((Rb $fs 2), 0) }
    3 { $script:acc[$path] = RI $fs }
    4 { $script:acc[$path] = [System.BitConverter]::ToInt64((Rb $fs 8), 0) }
    5 { $script:acc[$path] = RI $fs }
    6 { $script:acc[$path] = [System.BitConverter]::ToDouble((Rb $fs 8), 0) }
    7 { $n = RI $fs; Rb $fs $n | Out-Null }
    8 { $script:acc[$path] = RS $fs }
    9 { $et = [byte]$fs.ReadByte(); $n = RI $fs; for ($i = 0; $i -lt $n; $i++) { RN $fs $et ($path + '[]') } }
    10 { while ($true) { $st = [byte]$fs.ReadByte(); if ($st -eq 0) { break }; $nm = RS $fs; RN $fs $st ($path + '/' + $nm) } }
    11 { $n = RI $fs; Rb $fs ($n * 4) | Out-Null; $script:acc[$path] = 'ints=' + $n }
    12 { $n = RI $fs; Rb $fs ($n * 8) | Out-Null; $script:acc[$path] = 'longs=' + $n }
    default { throw ('bad tag ' + $t) }
  }
}
$names = @{}; $structs = @{}; $saved = 0; $first = $true
for ($cz = 0; $cz -lt 32; $cz++) {
  for ($cx = 0; $cx -lt 32; $cx++) {
    $i = ($cx + ($cz * 32)) * 4
    $off = ((([int]$bytes[$i]) -shl 16) -bor (([int]$bytes[$i + 1]) -shl 8) -bor ([int]$bytes[$i + 2]))
    if ($off -le 0) { continue }
    $sz = ((([int]$bytes[$i + 3]) -shl 24) -bor 0)
    $st = $off * 4096
    $len = ((([int]$bytes[$st]) -shl 24) -bor (([int]$bytes[$st + 1]) -shl 16) -bor (([int]$bytes[$st + 2]) -shl 8) -bor ([int]$bytes[$st + 3]))
    $comp = [int]$bytes[$st + 4]
    $data = New-Object byte[] ($len - 1)
    [Array]::Copy([byte[]]$bytes, [int]($st + 5), [byte[]]$data, [int]0, [int]($len - 1))
    if ($comp -eq 2) {
      $rest = New-Object byte[] ($data.Length - 2)
      [Array]::Copy([byte[]]$data, [int]2, [byte[]]$rest, [int]0, [int]($data.Length - 2))
      $def = New-Object System.IO.Compression.DeflateStream((New-Object System.IO.MemoryStream(, $rest)), [System.IO.Compression.CompressionMode]::Decompress)
      $mo = New-Object System.IO.MemoryStream; $def.CopyTo($mo); $def.Dispose(); $data = $mo.ToArray()
    }
    $script:acc = @{}
    $cs = New-Object System.IO.MemoryStream(, $data)
    $rt = [byte]$cs.ReadByte(); RS $cs | Out-Null
    try { RN $cs $rt '' } catch { Write-Output ('parse fail chunk ' + $cx + ',' + $cz + ' :: ' + $_.Exception.Message); continue }
    $saved++
    foreach ($k in $script:acc.Keys) {
      if ($k -match 'palette\[\]/Name$') { $names[[string]$script:acc[$k]] = $true }
      elseif ($k -match 'structures/starts/[^/]+$') { $structs[($k -split '/')[-1]] = $true }
    }
    if ($Detail -and $first) {
      $first = $false
      Write-Output ('--- first saved chunk ' + $cx + ',' + $cz + ' tag paths (filtered) ---')
      foreach ($k in ($script:acc.Keys | Where-Object { $_ -match '^(sections/section|y_sections|data_version|x_pos|z_pos|status)' } | Sort-Object | Select-Object -First 25)) { Write-Output ('  ' + $k + ' = ' + $script:acc[$k]) }
    }
  }
}
Write-Output ('region r.' + $RegionX + '.' + $RegionZ + ' dim=' + $Dim + ' saved_chunks=' + $saved)
Write-Output ('block_palette_names: ' + (($names.Keys | Sort-Object) -join ' | '))
Write-Output ('structures: ' + (($structs.Keys | Sort-Object) -join ' | '))
