$ErrorActionPreference = 'SilentlyContinue'

# Single instance guard.
$mutex = New-Object System.Threading.Mutex($false, 'SeelenTraySyncWatcher')
if (-not $mutex.WaitOne(0)) { exit }

$sync = Join-Path $PSScriptRoot 'sync-tray.ps1'

while ($true) {
  & powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $sync -Quiet
  Start-Sleep -Seconds 120
}
