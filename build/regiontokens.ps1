param([string]$World = 'voidtest', [string]$Dim = 'overworld', [string]$RegionX = '0', [string]$RegionZ = '0', [switch]$Tokens)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$base = Join-Path (Split-Path -Parent $PSScriptRoot) 'test'
$reg = Join-Path $base ($World + '\dimensions\minecraft\' + $Dim + '\region\r.' + $RegionX + '.' + $RegionZ + '.mca')
if (-not (Test-Path -LiteralPath $reg)) { Write-Output ('missing ' + $reg); exit 1 }
$fsIn = [System.IO.File]::Open($reg, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$bytes = New-Object byte[] $fsIn.Length; $fsIn.Read($bytes, 0, $bytes.Length) | Out-Null; $fsIn.Dispose()
$toks = @{}; $saved = 0; $totalLen = 0
for ($cz = 0; $cz -lt 32; $cz++) {
  for ($cx = 0; $cx -lt 32; $cx++) {
    $i = ($cx + ($cz * 32)) * 4
    $off = ((([int]$bytes[$i]) -shl 16) -bor (([int]$bytes[$i + 1]) -shl 8) -bor ([int]$bytes[$i + 2]))
    if ($off -le 0) { continue }
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
    $saved++; $totalLen += $data.Length
    $txt = [System.Text.Encoding]::GetEncoding(28591).GetString($data)
    foreach ($m in [regex]::Matches($txt, 'minecraft:[a-z0-9_/\.\-]+')) { $toks[$m.Value] = $true }
    foreach ($m in [regex]::Matches($txt, '#[a-z_]+:[a-z_]+')) { $toks['[tag]' + $m.Value] = $true }
  }
}
Write-Output ('r.' + $RegionX + '.' + $RegionZ + ' dim=' + $Dim + ' chunks=' + $saved + ' avg_chunk_bytes=' + [Math]::Round($totalLen / [Math]::Max(1, $saved)))
$list = $toks.Keys | Sort-Object
if ($Tokens) { Write-Output ('tokens(' + $list.Count + '): ' + ($list -join ' ')) }
else { Write-Output ('tokens(' + $list.Count + '): ' + (($list | Select-Object -First 40) -join ' ')) }
