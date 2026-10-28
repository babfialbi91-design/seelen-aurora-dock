param(
  # auto = let Windows auto-hide the taskbar (reversible, hover brings it back)
  # hide = keep it hidden for this session (ShowWindow), still auto-hides after a reboot
  [ValidateSet('auto', 'hide')]
  [string]$Mode = 'auto',

  # Restore everything captured by the last run.
  [switch]$Undo,

  # Do not restart Seelen UI (useful when only the taskbar state changes).
  [switch]$NoRestart,

  # Print what would happen without touching anything.
  [switch]$DryRun
)

# ---------------------------------------------------------------------------
# Aurora Dock - shell mode
#
# Seelen 2.8 has no taskbar module of its own, so "merging" the dock and the
# top bar with the Windows taskbar means removing the taskbar from the picture
# and letting the two Seelen widgets own the screen edges:
#
#   top edge    -> @seelen/fancy-toolbar  (position Top,    margin 8)
#   bottom edge -> @seelen/weg            (position Bottom, margin 8)
#
# This script only does reversible things:
#   * ABM_SETSTATE(ABS_AUTOHIDE) so the taskbar behaves like a dock that is
#     parked off screen instead of a strip that eats 48px of every window.
#   * (optional -Mode hide) ShowWindow(SW_HIDE) for the current session.
#   * writes the Seelen WEG / toolbar placement if they drifted.
#   * snapshots the previous state to %LOCALAPPDATA%\aurora-dock\shell-state.json
#
# Undo:
#   powershell -ExecutionPolicy Bypass -File scripts\shell-mode.ps1 -Undo
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$SeelenSettings = Join-Path $env:APPDATA 'com.seelen.seelen-ui\settings.json'
$StateDir = Join-Path $env:LOCALAPPDATA 'aurora-dock'
$StateFile = Join-Path $StateDir 'shell-state.json'
$StuckRects = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Aurora {
  public static class Shell {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct APPBARDATA {
      public int cbSize;
      public IntPtr hWnd;
      public uint uCallbackMessage;
      public uint uEdge;
      public RECT rc;
      public IntPtr lParam;
    }

    [DllImport("shell32.dll")]
    public static extern UIntPtr SHAppBarMessage(uint message, ref APPBARDATA data);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string cls, string win);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int cmd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    const uint ABM_SETSTATE = 0x0000000A;
    const uint ABS_AUTOHIDE = 0x0001;
    const uint ABS_ALWAYSONTOP = 0x0002;

    public static void SetAutoHide(bool on) {
      APPBARDATA d = new APPBARDATA();
      d.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
      d.lParam = (IntPtr)(on ? (ABS_AUTOHIDE | ABS_ALWAYSONTOP) : ABS_ALWAYSONTOP);
      SHAppBarMessage(ABM_SETSTATE, ref d);
    }

    public static string Rect(string cls) {
      IntPtr h = FindWindow(cls, null);
      if (h == IntPtr.Zero) return "missing";
      RECT r;
      if (!GetWindowRect(h, out r)) return "unknown";
      return r.Left + "," + r.Top + "," + r.Right + "," + r.Bottom;
    }

    public static void Hide(string cls, bool hide) {
      IntPtr h = FindWindow(cls, null);
      if (h != IntPtr.Zero) ShowWindow(h, hide ? 0 : 5);
    }
  }
}
'@

function Get-TaskbarSetting {
  try {
    $bytes = (Get-ItemProperty -LiteralPath $StuckRects -Name Settings -ErrorAction Stop).Settings
    return [Convert]::ToBase64String($bytes)
  } catch {
    return $null
  }
}

function Set-TaskbarSetting([string]$b64) {
  if (-not $b64) { return }
  $bytes = [Convert]::FromBase64String($b64)
  Set-ItemProperty -LiteralPath $StuckRects -Name Settings -Value $bytes -Type Binary
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
  # Seelen relaunches itself from its startup entry within ~45s.
  Start-Sleep -Seconds 2
  return $true
}

$seelen = Read-Json $SeelenSettings
if (-not $seelen) { throw "Seelen settings not found: $SeelenSettings" }

if ($Undo) {
  if (-not (Test-Path -LiteralPath $StateFile)) {
    Write-Host 'No snapshot found - nothing to undo.' -ForegroundColor Yellow
    exit 1
  }

  $snap = Read-Json $StateFile

  Write-Host 'Restoring the Windows taskbar...'
  if (-not $DryRun) {
    [Aurora.Shell]::SetAutoHide($false)
    [Aurora.Shell]::Hide('Shell_TrayWnd', $false)
    [Aurora.Shell]::Hide('Shell_SecondaryTrayWnd', $false)
    if ($snap.taskbarSettings) { Set-TaskbarSetting $snap.taskbarSettings }
  }

  if ($snap.seelen) {
    Write-Host 'Restoring Seelen widget settings...'
    if (-not $DryRun) {
      foreach ($widget in @('@seelen/weg', '@seelen/fancy-toolbar')) {
        $saved = $snap.seelen.$widget
        if ($null -eq $saved) { continue }
        $current = $seelen.byWidget.$widget
        if ($null -eq $current) {
          $seelen.byWidget | Add-Member -NotePropertyName $widget -NotePropertyValue $saved -Force
        } else {
          $saved.PSObject.Properties | ForEach-Object {
            $current | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value -Force
          }
        }
      }
      Write-Json $SeelenSettings $seelen
    }
  }

  if (-not $DryRun) { Remove-Item -LiteralPath $StateFile -Force }

  if (-not $NoRestart -and -not $DryRun) {
    Write-Host 'Restarting Seelen UI...'
    Stop-Seelen | Out-Null
  }

  Write-Host 'Shell mode off. Taskbar restored.' -ForegroundColor Green
  exit 0
}

# ------------------------------------------------------------------ apply ---

$snapshot = [ordered]@{
  createdAt       = (Get-Date).ToString('o')
  taskbarSettings = (Get-TaskbarSetting)
  taskbarRect     = [Aurora.Shell]::Rect('Shell_TrayWnd')
  seelen          = [ordered]@{
    '@seelen/weg'           = $seelen.byWidget.'@seelen/weg'
    '@seelen/fancy-toolbar' = $seelen.byWidget.'@seelen/fancy-toolbar'
  }
}

if (Test-Path -LiteralPath $StateFile) {
  Write-Host 'A snapshot already exists - keeping the oldest one (undo still works).'
} elseif (-not $DryRun) {
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  Write-Json $StateFile $snapshot
}

$changed = $false

# --- Seelen: dock at the bottom, bar at the top, both on an 8px grid.
$weg = $seelen.byWidget.'@seelen/weg'
$bar = $seelen.byWidget.'@seelen/fancy-toolbar'
if ($null -eq $weg) { throw 'The Aurora Dock theme is not installed (@seelen/weg missing).' }

$want = @{ enabled = $true; position = 'Bottom'; margin = 8; padding = 8; size = 40; mode = 'MinContent' }
foreach ($k in $want.Keys) {
  if ($weg.$k -ne $want[$k]) {
    Write-Host ("  dock.{0}: {1} -> {2}" -f $k, $weg.$k, $want[$k])
    $weg | Add-Member -NotePropertyName $k -NotePropertyValue $want[$k] -Force
    $changed = $true
  }
}

if ($bar) {
  $wantBar = @{ enabled = $true; position = 'Top'; margin = 8; padding = 8 }
  foreach ($k in $wantBar.Keys) {
    if ($bar.$k -ne $wantBar[$k]) {
      Write-Host ("  bar.{0}: {1} -> {2}" -f $k, $bar.$k, $wantBar[$k])
      $bar | Add-Member -NotePropertyName $k -NotePropertyValue $wantBar[$k] -Force
      $changed = $true
    }
  }
}

if ($changed -and -not $DryRun) { Write-Json $SeelenSettings $seelen }

# --- Windows: park the taskbar.
Write-Host ("Taskbar before: {0}" -f [Aurora.Shell]::Rect('Shell_TrayWnd'))

if (-not $DryRun) {
  [Aurora.Shell]::SetAutoHide($true)
  if ($Mode -eq 'hide') {
    [Aurora.Shell]::Hide('Shell_TrayWnd', $true)
    [Aurora.Shell]::Hide('Shell_SecondaryTrayWnd', $true)
  }
  Start-Sleep -Milliseconds 400
}

$setting = Get-TaskbarSetting
Write-Host ("Taskbar after:  {0}" -f [Aurora.Shell]::Rect('Shell_TrayWnd'))
Write-Host ("Auto-hide flag: {0}" -f ($(if ($setting) { 'written' } else { 'unavailable' })))

if ($changed -and -not $NoRestart -and -not $DryRun) {
  Write-Host 'Restarting Seelen UI to apply the layout...'
  Stop-Seelen | Out-Null
}

Write-Host ''
Write-Host 'Shell mode is on.' -ForegroundColor Green
Write-Host '  top edge    -> Aurora top bar'
Write-Host '  bottom edge -> Aurora dock'
if ($Mode -eq 'auto') {
  Write-Host '  Windows taskbar auto-hides; hover the screen edge to bring it back.'
} else {
  Write-Host '  Windows taskbar is hidden for this session (returns after a reboot).'
}
Write-Host ''
Write-Host 'Undo: powershell -ExecutionPolicy Bypass -File scripts\shell-mode.ps1 -Undo'
