param([switch]$Quiet)

# Keeps HKCU\Control Panel\NotifyIconSettings in sync with the tray icons that
# Seelen UI reports as "ignored, no registry entry found".
# Windows 10 has no such key, so it is created/maintained manually here.
# Rules mirror Seelen's matcher: a GUID entry matches by GUID, otherwise by
# UID + ExecutablePath (case-insensitive). User pins (IsPromoted) are preserved.

$ErrorActionPreference = 'Stop'

$log = Join-Path $env:LOCALAPPDATA 'com.seelen.seelen-ui\logs\Seelen UI.log'
if (-not (Test-Path -LiteralPath $log)) {
  if (-not $Quiet) { Write-Output 'sync-tray: log not found' }
  exit 0
}

$base = 'HKCU:\Control Panel\NotifyIconSettings'
if (-not (Test-Path -LiteralPath $base)) { New-Item -Path $base -Force | Out-Null }

$fs = [System.IO.File]::Open($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$sr = New-Object System.IO.StreamReader($fs)
$txt = $sr.ReadToEnd()
$sr.Close(); $fs.Close()

$ignoredRx = [regex]'Tray icon (?<id>\S+) \(Some\("(?<path>(?:[^"\\]|\\.)*)"\)\) ignored, no registry entry found'
$guidRx = [regex]'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

function Unescape([string]$p) { return ($p -replace '\\\\', '\') }

$byGuid = @{}
$byPath = @{}
$used = New-Object System.Collections.Generic.List[int]

foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d+$' })) {
  $n = [int]$k.PSChildName
  $used.Add($n)
  $p = Get-ItemProperty -LiteralPath $k.PSPath
  $o = [pscustomobject]@{ Key = $n; Path = [string]$p.ExecutablePath; Guid = [string]$p.IconGuid; Uid = $p.UID }
  if ($o.Guid) { $byGuid[$o.Guid.ToLower()] = $o }
  if ($o.Path) { $byPath[$o.Path.ToLower()] = $o }
}

$created = 0
$updated = 0

function NextKey {
  if ($used.Count -eq 0) { return 1 }
  return [int](($used | Measure-Object -Maximum).Maximum) + 1
}

foreach ($line in ($txt -split "`r?`n")) {
  $m = $ignoredRx.Match($line)
  if (-not $m.Success) { continue }
  $id = $m.Groups['id'].Value
  $path = Unescape $m.Groups['path'].Value
  if (-not $path) { continue }
  $lp = $path.ToLower()

  if ($guidRx.IsMatch($id)) {
    $g = $id.ToLower()
    if ($byGuid.ContainsKey($g)) { continue }

    $o = $null
    if ($byPath.ContainsKey($lp) -and -not $byPath[$lp].Guid) { $o = $byPath[$lp] }

    if ($o) {
      $sk = Join-Path $base ([string]$o.Key)
      New-ItemProperty -LiteralPath $sk -Name IconGuid -PropertyType String -Value $g -Force | Out-Null
      $o.Guid = $g
      $byGuid[$g] = $o
      $updated++
    } else {
      $next = NextKey
      $sk = Join-Path $base ([string]$next)
      New-Item -Path $sk -Force | Out-Null
      New-ItemProperty -LiteralPath $sk -Name ExecutablePath -PropertyType String -Value $path -Force | Out-Null
      New-ItemProperty -LiteralPath $sk -Name IconGuid -PropertyType String -Value $g -Force | Out-Null
      New-ItemProperty -LiteralPath $sk -Name IsPromoted -PropertyType DWord -Value 0 -Force | Out-Null
      $used.Add($next)
      $o = [pscustomobject]@{ Key = $next; Path = $path; Guid = $g; Uid = $null }
      $byGuid[$g] = $o
      $byPath[$lp] = $o
      $created++
    }
    continue
  }

  $uid = 0
  try { $uid = [int]($id.Split('_')[-1]) } catch { continue }

  if ($byPath.ContainsKey($lp)) {
    $o = $byPath[$lp]
    if ($o.Guid) { continue }
    if ($o.Uid -ne $uid) {
      $sk = Join-Path $base ([string]$o.Key)
      New-ItemProperty -LiteralPath $sk -Name UID -PropertyType DWord -Value $uid -Force | Out-Null
      $o.Uid = $uid
      $updated++
    }
    continue
  }

  $next = NextKey
  $sk = Join-Path $base ([string]$next)
  New-Item -Path $sk -Force | Out-Null
  New-ItemProperty -LiteralPath $sk -Name ExecutablePath -PropertyType String -Value $path -Force | Out-Null
  New-ItemProperty -LiteralPath $sk -Name UID -PropertyType DWord -Value $uid -Force | Out-Null
  New-ItemProperty -LiteralPath $sk -Name IsPromoted -PropertyType DWord -Value 0 -Force | Out-Null
  $used.Add($next)
  $byPath[$lp] = [pscustomobject]@{ Key = $next; Path = $path; Guid = ''; Uid = $uid }
  $created++
}

if (($created + $updated) -gt 0) {
  $bytes = New-Object System.Collections.Generic.List[byte]
  foreach ($n in @($used | Sort-Object)) { $bytes.AddRange([BitConverter]::GetBytes([uint64]$n)) }
  New-ItemProperty -LiteralPath $base -Name UIOrderList -PropertyType Binary -Value ([byte[]]$bytes.ToArray()) -Force | Out-Null
}

if (-not $Quiet) {
  Write-Output ("sync-tray: created={0} updated={1} total={2}" -f $created, $updated, $used.Count)
}
exit 0
