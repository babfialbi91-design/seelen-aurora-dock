# Builds a monochrome icon pack from the apps pinned on the dock.
# Icons are extracted at 256px (SHIL_JUMBO), desaturated, and written to
# iconpack/ in the repo, then mirrored into Seelen's iconpacks folder.
param(
  [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "iconpack"),
  [switch]$Install
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$statePath = Join-Path $env:APPDATA "com.seelen.seelen-ui\data\seelen-weg\state.yml"
if (-not (Test-Path $statePath)) { throw "dock state not found: $statePath" }

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

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

public static class ShellIcons {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
  static extern IntPtr SHGetFileInfo(string path, uint attr, ref SHFILEINFO psfi, uint cb, uint flags);

  [DllImport("shell32.dll")]
  static extern int SHGetImageList(int iImageList, ref Guid riid, out IImageList ppv);

  public static System.Drawing.Icon GetJumbo(string path) {
    var info = new SHFILEINFO();
    SHGetFileInfo(path, 0, ref info, (uint)Marshal.SizeOf(typeof(SHFILEINFO)), 0x100);
    if (info.iIcon == 0) return null;
    var iid = new Guid("46EB5926-582E-4017-9FDF-E8998DAA0950");
    IImageList list;
    if (SHGetImageList(0x4, ref iid, out list) != 0 || list == null) return null;
    IntPtr h;
    if (list.GetIcon(info.iIcon, 0x1, out h) != 0 || h == IntPtr.Zero) return null;
    return System.Drawing.Icon.FromHandle(h);
  }
}
"@

function Get-IconBitmap([string]$path) {
  $ico = [ShellIcons]::GetJumbo($path)
  if ($ico) {
    $bmp = $ico.ToBitmap()
    $ico.Dispose()
    return $bmp
  }
  $fallback = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
  if (-not $fallback) { return $null }
  $bmp = $fallback.ToBitmap()
  $fallback.Dispose()
  return $bmp
}

function Convert-Mono([System.Drawing.Bitmap]$src) {
  $side = 256
  $out = New-Object System.Drawing.Bitmap $side, $side, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($out)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($src, 0, 0, $side, $side)
  $g.Dispose()

  for ($y = 0; $y -lt $side; $y++) {
    for ($x = 0; $x -lt $side; $x++) {
      $c = $out.GetPixel($x, $y)
      if ($c.A -eq 0) { continue }
      $l = 0.2126 * $c.R + 0.7152 * $c.G + 0.0722 * $c.B
      $l = ($l - 128) * 1.08 + 128
      if ($l -lt 0) { $l = 0 } elseif ($l -gt 255) { $l = 255 }
      $v = [int][Math]::Round($l)
      $out.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($c.A, $v, $v, $v))
    }
  }
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
  if (-not (Test-Path -LiteralPath $path)) {
    $leaf = Split-Path $path -Leaf
    $grand = Split-Path (Split-Path $path -Parent) -Parent
    $hit = $null
    if ($grand -and (Test-Path -LiteralPath $grand)) {
      $hit = Get-ChildItem -LiteralPath $grand -Recurse -Depth 2 -Filter $leaf -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($hit) { $path = $hit.FullName }
    else {
      Write-Warning "skip (missing): $($e.path)"
      continue
    }
  }
  $src = Get-IconBitmap $path
  if (-not $src) { Write-Warning "skip (no icon): $path"; continue }
  $mono = Convert-Mono $src
  $src.Dispose()
  $name = "icons/{0:x8}.png" -f (++$index)
  $mono.Save((Join-Path $OutDir $name), [System.Drawing.Imaging.ImageFormat]::Png)
  $mono.Dispose()
  $mtime = (Get-Item -LiteralPath $path).LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ss.ffffffZ")
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
