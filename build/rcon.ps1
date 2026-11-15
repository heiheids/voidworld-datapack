param([string]$Pass = 'testpw', [string]$Port = '25575', [string]$CmdFile = 'cmds.txt')
$ErrorActionPreference = 'Stop'
$c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', [int]$Port)
$s = $c.GetStream(); $s.ReadTimeout = 20000; $s.WriteTimeout = 10000
function Send-Pkt([int]$id, [int]$type, [string]$body) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  # 载荷 = id(4) + type(4) + 正文 + 两个 NUL 结尾
  $len = 4 + 4 + $bytes.Length + 2
  $ms = New-Object System.IO.MemoryStream
  foreach ($v in @($len, $id, $type)) { $bb = [System.BitConverter]::GetBytes([int]$v); [Array]::Reverse($bb); $s.Write([byte[]]$bb, 0, 4) }
  $s.Write($bytes, 0, $bytes.Length)
  $s.WriteByte(0); $s.WriteByte(0)
  $s.Flush()
}
function Read-Pkt() {
  $hb = New-Object byte[] 4; $off = 0
  while ($off -lt 4) { $n = $s.Read($hb, $off, 4 - $off); if ($n -le 0) { return $null }; $off += $n }
  [Array]::Reverse($hb); $len = [System.BitConverter]::ToInt32($hb, 0)
  $pb = New-Object byte[] $len; $off = 0
  while ($off -lt $len) { $n = $s.Read($pb, $off, $len - $off); if ($n -le 0) { break }; $off += $n }
  return [System.Text.Encoding]::UTF8.GetString($pb, 8, $pb.Length - 10)
}
Send-Pkt 1 3 $Pass
$auth = Read-Pkt
Write-Output ('AUTH resp: [' + $auth + ']')
$id = 10
foreach ($line in (Get-Content -LiteralPath $CmdFile -Encoding UTF8)) {
  if (-not $line.Trim()) { continue }
  Send-Pkt $id 2 $line
  Write-Output ('>>> ' + $line)
  Write-Output ('    ' + ((Read-Pkt) -replace "`n", "`n    "))
  $id++
}
$c.Close()
