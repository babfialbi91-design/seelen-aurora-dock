param(
  # low  = blur off, decorative motion near-still (best for battery / iGPU)
  # high = the theme defaults (blur 22, effects 100, motion 100)
  [ValidateSet('low', 'high')]
  [string]$Profile = 'low',

  [switch]$Undo,
  [switch]$NoRestart,
  [switch]$DryRun
)

# ---------------------------------------------------------------------------
# Aurora Dock - performance profile
#
# The theme exposes its cost as CSS variables, stored per theme in Seelen's
# settings.json (byTheme["@asfkep/aurora-dock"]):
#
#   --ads-fx       scales every backdrop-filter blur   (100 -> 0)
#   --ads-blur     the base blur radius                (22 -> 0)
#   --ads-motion   scales every decorative animation    (100 -> 15)
#   --ads-glow     white glow / shadow intensity        (58 -> 24)
#   --ads-speed    shine cadence in seconds             (14 -> 40)
#   --ads-opacity  black glass opacity                  (62 -> 86)
#
# "low" keeps the shapes, icons and the magnify wave, but stops paying for a
# full-screen blur under every panel on every frame.
#
# Undo (also removes values that did not exist before the first run):
#   powershell -ExecutionPolicy Bypass -File scripts\low-profile.ps1 -Undo
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$ThemeId = '@asfkep/aurora-dock'
$SettingsPath = Join-Path $env:APPDATA 'com.seelen.seelen-ui\settings.json'
$StateDir = Join-Path $env:LOCALAPPDATA 'aurora-dock'
$StateFile = Join-Path $StateDir 'perf-profile.json'
$SeelenAppId = 'Seelen.SeelenUI_p6yyn03m1894e!App'

$presets = @{
  low  = [ordered]@{
    '--ads-fx'      = '0'
    '--ads-blur'    = '0'
    '--ads-motion'  = '15'
    '--ads-glow'    = '24'
    '--ads-speed'   = '40'
    '--ads-opacity' = '86'
  }
  high = [ordered]@{
    '--ads-fx'      = '100'
    '--ads-blur'    = '22'
    '--ads-motion'  = '100'
    '--ads-glow'    = '58'
    '--ads-speed'   = '14'
    '--ads-opacity' = '62'
  }
}

function Read-Json([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
  return $raw | ConvertFrom-Json
}

function Write-Json([string]$path, $obj) {
  $json = $obj | ConvertTo-Json -Depth 12
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($path, $json, $enc)
}

function Stop-Seelen {
  $proc = Get-Process -Name 'seelen-ui' -ErrorAction SilentlyContinue
  if (-not $proc) { return $false }
  $proc | Stop-Process -Force
  Start-Sleep -Seconds 2
  return $true
}

function Start-Seelen {
  if (Get-Process -Name 'seelen-ui' -ErrorAction SilentlyContinue) { return }
  Start-Process -FilePath 'explorer.exe' -ArgumentList ("shell:AppsFolder\" + $SeelenAppId)
  # Give the app time to read settings.json before we report success.
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    if (Get-Process -Name 'seelen-ui' -ErrorAction SilentlyContinue) { break }
  }
}

if (-not (Test-Path -LiteralPath $SettingsPath)) { throw "Seelen settings not found: $SettingsPath" }
$settings = Read-Json $SettingsPath
$theme = $settings.byTheme.$ThemeId

if ($Undo) {
  if (-not (Test-Path -LiteralPath $StateFile)) {
    Write-Host 'No snapshot found - nothing to undo.' -ForegroundColor Yellow
    exit 1
  }
  $snap = Read-Json $StateFile
  $restored = 0
  $removed = 0

  if (-not $DryRun) { Stop-Seelen | Out-Null }

  if ($snap.values) {
    foreach ($p in $snap.values.PSObject.Properties) {
      Write-Host ("  restore {0} = {1}" -f $p.Name, $p.Value)
      $theme | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
      $restored++
    }
  }
  if ($snap.absent) {
    foreach ($k in @($snap.absent)) {
      if ($null -ne $theme.$k) {
        Write-Host ("  remove  {0}" -f $k)
        $theme.PSObject.Properties.Remove($k)
        $removed++
      }
    }
  }

  if (-not $DryRun) {
    Write-Json $SettingsPath $settings
    Remove-Item -LiteralPath $StateFile -Force
    if (-not $NoRestart) { Start-Seelen }
  }

  Write-Host ''
  Write-Host ("Previous effect values restored ({0} set, {1} removed)." -f $restored, $removed) -ForegroundColor Green
  exit 0
}

if ($null -eq $theme) { throw "Theme settings for $ThemeId not found. Enable Aurora Dock once first." }

if (-not (Test-Path -LiteralPath $StateFile)) {
  $before = [ordered]@{}
  $absent = @()
  foreach ($k in $presets[$Profile].Keys) {
    if ($null -ne $theme.$k) { $before[$k] = $theme.$k } else { $absent += $k }
  }
  if (-not $DryRun) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    Write-Json $StateFile ([ordered]@{
      createdAt = (Get-Date).ToString('o')
      profile   = $Profile
      values    = $before
      absent    = $absent
    })
  }
}

foreach ($k in $presets[$Profile].Keys) {
  $v = $presets[$Profile][$k]
  Write-Host ("  {0}: {1} -> {2}" -f $k, $theme.$k, $v)
  $theme | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force
}

if (-not $DryRun) {
  # Stop first: Seelen rewrites settings.json on exit and would clobber us.
  Stop-Seelen | Out-Null
  Write-Json $SettingsPath $settings
  if (-not $NoRestart) { Start-Seelen }
}

Write-Host ''
Write-Host ("Performance profile: {0}" -f $Profile) -ForegroundColor Green
if ($Profile -eq 'low') {
  Write-Host '  blur off, decorative motion ~15%, shine every 40s'
} else {
  Write-Host '  theme defaults restored'
}
Write-Host 'Undo: powershell -ExecutionPolicy Bypass -File scripts\low-profile.ps1 -Undo'
