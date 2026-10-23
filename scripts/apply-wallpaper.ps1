<#
.SYNOPSIS
  Sets one of the bundled wallpapers on every monitor (Windows 10/11).

.EXAMPLE
  powershell -File scripts/apply-wallpaper.ps1 09-prism
  powershell -File scripts/apply-wallpaper.ps1 11-paper -Position Span
#>
param(
  [Parameter(Position = 0)][string]$Name = "09-prism",
  [ValidateSet("Fill", "Fit", "Stretch", "Tile", "Center", "Span")]
  [string]$Position = "Fill"
)

$ErrorActionPreference = "Stop"
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDesktopWallpaper {
  void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
  uint GetMonitorDevicePathCount();
  void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID, out RECT displayRect);
  void SetBackgroundColor(uint color);
  void GetBackgroundColor(out uint color);
  void SetPosition(int position);
  void GetPosition(out int position);
  void SetSlideshow(IntPtr items);
  void GetSlideshow(out IntPtr items);
  void SetSlideshowOptions(int options, uint slideshowTick);
  void GetSlideshowOptions(out int options, out uint slideshowTick);
  void AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorID, int direction);
  void Enable([MarshalAs(UnmanagedType.Bool)] bool enable);
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left, Top, Right, Bottom; }

public static class AuroraWallpaper {
  public static string Apply(string path, int position) {
    var type = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"));
    var desktop = (IDesktopWallpaper)Activator.CreateInstance(type);
    desktop.SetWallpaper(null, path);
    desktop.SetPosition(position);
    string now = desktop.GetWallpaper(null);
    int pos; desktop.GetPosition(out pos);
    uint monitors = desktop.GetMonitorDevicePathCount();
    Marshal.ReleaseComObject(desktop);
    return string.Format("wallpaper={0} | position={1} | monitors={2}", now, pos, monitors);
  }
}
"@

$root = Split-Path $PSScriptRoot -Parent
if (-not $Name.ToLower().EndsWith(".jpg")) { $Name = "$Name.jpg" }
$file = Join-Path (Join-Path $root "wallpapers") $Name
if (-not (Test-Path -LiteralPath $file)) {
  $available = (Get-ChildItem (Join-Path $root "wallpapers") -Filter *.jpg | Select-Object -ExpandProperty BaseName) -join ", "
  throw "Wallpaper not found: $Name`nAvailable: $available"
}

$code = @{ Center = 0; Tile = 1; Stretch = 2; Fit = 3; Fill = 4; Span = 5 }[$Position]
[AuroraWallpaper]::Apply((Resolve-Path -LiteralPath $file).Path, $code)
