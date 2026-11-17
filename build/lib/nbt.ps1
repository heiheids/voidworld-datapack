# 最小 NBT 读取器（大端），只解析结构、不解码区块方块数据。
# 用法: . build\lib\nbt.ps1 ; $root = Read-NbtRoot $bytes

function New-NbtBuf([byte[]]$Bytes) { return @{ B = $Bytes; P = 0 } }

function Read-NbtU8($r) { $v = $r.B[$r.P]; $r.P++; return $v }
function Read-NbtI8($r) {
  $v = [int]$r.B[$r.P]; $r.P++
  if ($v -ge 128) { $v -= 256 }
  return $v
}
function Read-NbtI16($r) {
  $v = [int]$r.B[$r.P] * 256 + [int]$r.B[$r.P + 1]; $r.P += 2
  if ($v -ge 32768) { $v -= 65536 }
  return $v
}
function Read-NbtI32($r) {
  $v = 0
  for ($i = 0; $i -lt 4; $i++) { $v = ($v * 256) + [int]$r.B[$r.P + $i] }
  $r.P += 4
  if ($v -ge 2147483648) { $v -= 4294967296 }
  return $v
}
function Read-NbtStr($r) {
  $n = Read-NbtI16 $r
  if ($n -le 0) { return '' }
  $s = [System.Text.Encoding]::UTF8.GetString($r.B, $r.P, $n)
  $r.P += $n
  return $s
}

function Read-NbtPayload($r, [int]$Type) {
  switch ($Type) {
    1 { return Read-NbtI8 $r }
    2 { return (Read-NbtI16 $r) }
    3 { return (Read-NbtI32 $r) }
    4 { $null = (Read-NbtI32 $r); $null = (Read-NbtI32 $r); return 0 }
    5 { $null = Read-NbtI32 $r; return 0.0 }
    6 { $null = Read-NbtI32 $r; $null = Read-NbtI32 $r; return 0.0 }
    7 { $n = Read-NbtI32 $r; $r.P += $n; return $n }
    8 { return (Read-NbtStr $r) }
    9 {
      $et = Read-NbtU8 $r; $n = Read-NbtI32 $r
      $list = New-Object System.Collections.Generic.List[object]
      for ($i = 0; $i -lt $n; $i++) { $list.Add((Read-NbtPayload $r $et)) }
      return $list.ToArray()
    }
    10 { return (Read-NbtCompound $r) }
    11 {
      $n = Read-NbtI32 $r
      $arr = New-Object 'System.Int32[]' $n
      for ($i = 0; $i -lt $n; $i++) { $arr[$i] = (Read-NbtI32 $r) }
      return $arr
    }
       12 {
      $n = Read-NbtI32 $r
      $arr = New-Object 'System.Int64[]' $n
      for ($i = 0; $i -lt $n; $i++) {
        $v = [int64]0
        for ($k = 0; $k -lt 8; $k++) { $v = ($v -shl 8) -bor [int64]$r.B[$r.P + $k] }
        $r.P += 8
        $arr[$i] = $v
      }
      return $arr
    }
    default { throw ("unknown NBT tag type " + $Type) }
  }
}

function Read-NbtCompound($r) {
  $h = @{}
  while ($true) {
    $t = Read-NbtU8 $r
    if ($t -eq 0) { break }
    $name = Read-NbtStr $r
    $h[$name] = Read-NbtPayload $r $t
  }
  return $h
}

function Read-NbtRoot([byte[]]$Bytes) {
  $r = New-NbtBuf $Bytes
  $t = Read-NbtU8 $r
  if ($t -ne 10) { throw ("root is not a compound: " + $t) }
  $null = Read-NbtStr $r
  return (Read-NbtCompound $r)
}
