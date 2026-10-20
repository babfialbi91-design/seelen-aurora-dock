$ErrorActionPreference = 'SilentlyContinue'

# Single instance guard.
$mutex = New-Object System.Threading.Mutex($false, 'SeelenTraySyncWatcher')
if (-not $mutex.WaitOne(0)) { exit }

$sync = Join-Path $PSScriptRoot 'sync-tray.ps1'
$gitSync = Join-Path $PSScriptRoot 'git-sync.ps1'
$tick = 0

while ($true) {
  & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $sync -Quiet

  # Push theme edits to GitHub every 5 cycles (~10 minutes).
  $tick++
  if (($tick % 5) -eq 0) {
    & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $gitSync
  }

  Start-Sleep -Seconds 120
}
