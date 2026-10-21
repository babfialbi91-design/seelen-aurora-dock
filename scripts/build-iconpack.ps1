# Builds an icon pack from the apps pinned on the dock.
# Icons are taken from the app's AUMID (so web apps / PWAs installed from a
# browser keep their own artwork instead of the browser's) and stored in full
# colour at 256px. The theme desaturates them with CSS, which is what lets a
# hovered dock item light its colours back up.
param(
  [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "iconpack"),
  [switch]$Install
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$statePath = Join-Path $env:APPDATA "com.seelen.seelen-ui\data\seelen-weg\state.yml"
if (-not (Test-Path $statePath)) { throw "dock state not found: $statePath" }

Add-Type -ReferencedAssemblies System.Drawing,PresentationCore,WindowsBase,System.Xaml -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

[StructLayout(LayoutKind.Sequential)] public struct SIZE { public int cx; public int cy; }
[Flags] public enum SIIGBF { RESIZETOFIT=0, BIGGERSIZEOK=1, MEMORYONLY=2, ICONONLY=4, THUMBNAILONLY=8, INCACHEONLY=0x10, CROPTOSQUARE=0x20, WIDETHUMBNAILS=0x40, ICONBACKGROUND=0x80, SCALEUP=0x100 }

[ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellItemImageFactory { void GetImage(SIZE size, SIIGBF flags, out IntPtr phbm); }

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct SHFILEINFO {
  public IntPtr hIcon;
  public int iIcon;
  public uint dwAttributes;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szDisplayName;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string szTypeName;
}

[ComImport, Guid("46EB5926-582E-4017-9FDF-E8998DAA0950"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IImageList {
  [PreserveSig] int Add(IntPtr hbmImage, IntPtr hbmMask, out int pi);
  [PreserveSig] int ReplaceIcon(int i, IntPtr hicon, out int pi);
  [PreserveSig] int SetOverlayImage(int iImage, int iOverlay);
  [PreserveSig] int Replace(int i, IntPtr hbmImage, IntPtr hbmMask);
  [PreserveSig] int AddMasked(IntPtr hbmImage, int crMask, out int pi);
  [PreserveSig] int Draw(IntPtr pimldp);
  [PreserveSig] int Remove(int i);
  [PreserveSig] int GetIcon(int i, int flags, out IntPtr picon);
}

public static class Icons {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
  static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

  [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
  static extern IntPtr SHGetFileInfo(string path, uint attr, ref SHFILEINFO psfi, uint cb, uint flags);

  [DllImport("shell32.dll")]
  static extern int SHGetImageList(int iImageList, ref Guid riid, out IImageList ppv);

  [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);

  // Icon declared by the app identity itself (works for PWAs / Store apps).
  public static System.Drawing.Bitmap FromAumid(string umid) {
    var iid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");
    object o;
    try {
      SHCreateItemFromParsingName("shell:AppsFolder\\" + umid, IntPtr.Zero, ref iid, out o);
    } catch { return null; }
    var factory = o as IShellItemImageFactory;
    if (factory == null) return null;
    IntPtr hbm;
    try {
      factory.GetImage(new SIZE { cx = 256, cy = 256 },
        SIIGBF.BIGGERSIZEOK | SIIGBF.ICONONLY | SIIGBF.SCALEUP, out hbm);
    } catch { return null; }
    if (hbm == IntPtr.Zero) return null;
    try {
      var src = Imaging.CreateBitmapSourceFromHBitmap(hbm, IntPtr.Zero, Int32Rect.Empty,
        BitmapSizeOptions.FromEmptyOptions());
      src.Freeze();
      var enc = new PngBitmapEncoder();
      enc.Frames.Add(BitmapFrame.Create(src));
      using (var ms = new System.IO.MemoryStream()) {
        enc.Save(ms);
        ms.Position = 0;
        using (var tmp = new System.Drawing.Bitmap(ms)) return new System.Drawing.Bitmap(tmp);
      }
    } finally { DeleteObject(hbm); }
  }

  public static System.Drawing.Bitmap FromPath(string path) {
    var info = new SHFILEINFO();
    SHGetFileInfo(path, 0, ref info, (uint)Marshal.SizeOf(typeof(SHFILEINFO)), 0x100);
    if (info.iIcon != 0) {
      var iid = new Guid("46EB5926-582E-4017-9FDF-E8998DAA0950");
      IImageList list;
      if (SHGetImageList(0x4, ref iid, out list) == 0 && list != null) {
        IntPtr h;
        if (list.GetIcon(info.iIcon, 0x1, out h) == 0 && h != IntPtr.Zero) {
          using (var ico = System.Drawing.Icon.FromHandle(h)) return ico.ToBitmap();
        }
      }
    }
    var fallback = System.Drawing.Icon.ExtractAssociatedIcon(path);
    if (fallback == null) return null;
    using (fallback) return fallback.ToBitmap();
  }
}
"@

function Convert-Square([System.Drawing.Bitmap]$src) {
  $side = 256
  $out = New-Object System.Drawing.Bitmap $side, $side, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($out)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)

  $scale = [Math]::Min($side / $src.Width, $side / $src.Height)
  $w = [int][Math]::Round($src.Width * $scale)
  $h = [int][Math]::Round($src.Height * $scale)
  $g.DrawImage($src, [int](($side - $w) / 2), [int](($side - $h) / 2), $w, $h)
  $g.Dispose()
  return $out
}

$iconDir = Join-Path $OutDir "icons"
New-Item -ItemType Directory -Force -Path $iconDir | Out-Null

$lines = Get-Content $statePath
$entries = @()
$current = $null
foreach ($line in $lines) {
  if ($line -match '^- type: AppOrFile') { $current = @{}; continue }
  if ($line -match '^- type: ') { $current = $null; continue }
  if ($null -eq $current) { continue }
  if ($line -match '^  displayName: (.*)$') { $current.displayName = $Matches[1].Trim() }
  elseif ($line -match '^  umid: (.*)$') {
    $v = $Matches[1].Trim()
    if ($v -ne "null") { $current.umid = $v }
  }
  elseif ($line -match '^  path: (.*)$') {
    $current.path = $Matches[1].Trim()
    if (-not $current.ContainsKey("displayName")) { $current.displayName = "" }
    $entries += , $current
    $current = $null
  }
}

$index = 0
$written = @()
foreach ($e in $entries) {
  $path = $e.path
  $exists = Test-Path -LiteralPath $path
  if (-not $exists) {
    $leaf = Split-Path $path -Leaf
    $grand = Split-Path (Split-Path $path -Parent) -Parent
    $hit = $null
    if ($grand -and (Test-Path -LiteralPath $grand)) {
      $hit = Get-ChildItem -LiteralPath $grand -Recurse -Depth 2 -Filter $leaf -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($hit) { $path = $hit.FullName; $exists = $true }
  }

  $src = $null
  if ($e.umid) { $src = [Icons]::FromAumid($e.umid) }
  if (-not $src -and $exists) { $src = [Icons]::FromPath($path) }
  if (-not $src) {
    Write-Warning "skip (no icon): $($e.displayName) [$($e.umid)] $path"
    continue
  }

  $square = Convert-Square $src
  $src.Dispose()
  $name = "icons/{0:x8}.png" -f (++$index)
  $square.Save((Join-Path $OutDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $square.Dispose()

  $mtime = "2000-01-01T00:00:00.000000Z"
  if ($exists) { $mtime = (Get-Item -LiteralPath $path).LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.ffffffZ") }
  $written += [pscustomobject]@{
    path    = $path
    umid    = $e.umid
    name    = $e.displayName
    icon    = $name
    mtime   = $mtime
    bytes   = (Get-Item -LiteralPath (Join-Path $OutDir $name)).Length
  }
}

$yaml = New-Object System.Text.StringBuilder
[void]$yaml.AppendLine("id: '@user/aurora-mono'")
[void]$yaml.AppendLine("metadata:")
[void]$yaml.AppendLine("  displayName: {}")
[void]$yaml.AppendLine("  description: {}")
[void]$yaml.AppendLine("  portrait: null")
[void]$yaml.AppendLine("  banner: null")
[void]$yaml.AppendLine("  screenshots: []")
[void]$yaml.AppendLine("  tags: []")
[void]$yaml.AppendLine("  appTargetVersion: null")
[void]$yaml.AppendLine("  premium: false")
[void]$yaml.AppendLine("  extras: {}")
[void]$yaml.AppendLine("  path: null")
[void]$yaml.AppendLine("  filename: null")
[void]$yaml.AppendLine("  bundled: false")
[void]$yaml.AppendLine("  remote: null")
[void]$yaml.AppendLine("missing: null")
[void]$yaml.AppendLine("entries:")
foreach ($w in $written) {
  [void]$yaml.AppendLine("- type: unique")
  if ($w.umid) { [void]$yaml.AppendLine("  umid: $($w.umid)") } else { [void]$yaml.AppendLine("  umid: null") }
  [void]$yaml.AppendLine("  path: $($w.path)")
  [void]$yaml.AppendLine("  icon:")
  [void]$yaml.AppendLine("    base: $($w.icon)")
  [void]$yaml.AppendLine("  sourceMtime: $($w.mtime)")
}
[void]$yaml.AppendLine("remoteEntries: []")
[void]$yaml.AppendLine("downloaded: false")
[System.IO.File]::WriteAllText((Join-Path $OutDir "metadata.yml"), $yaml.ToString(), (New-Object System.Text.UTF8Encoding($false)))

$written | Select-Object name, umid, icon, bytes | Format-Table -AutoSize

if ($Install) {
  $dest = Join-Path $env:APPDATA "com.seelen.seelen-ui\iconpacks\__aurora_mono"
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item (Join-Path $OutDir "metadata.yml") $dest
  Copy-Item $iconDir (Join-Path $dest "icons") -Recurse
  "installed to $dest"
}


