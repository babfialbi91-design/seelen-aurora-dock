# Generates the cinematic monochrome wallpaper set with GDI+ (no external deps).
# Usage: powershell -File scripts/make-wallpapers-v2.ps1 [-Width 3840] [-Height 2160]
param(
  [int]$Width = 3840,
  [int]$Height = 2160,
  [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "wallpapers")
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$W = $Width
$H = $Height
$s = 0.5
$CW = [int]($W * $s)
$CH = [int]($H * $s)

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "previews") | Out-Null

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class Wp {
  public static void Grain(Bitmap bmp, int amount, int seed) {
    var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
    var data = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    int stride = data.Stride, w = bmp.Width, h = bmp.Height;
    var buf = new byte[stride * h];
    Marshal.Copy(data.Scan0, buf, 0, buf.Length);
    var rnd = new Random(seed);
    for (int y = 0; y < h; y++) {
      int row = y * stride;
      for (int x = 0; x < w; x++) {
        int i = row + x * 4;
        int n = rnd.Next(-amount, amount + 1);
        int b = buf[i] + n, g = buf[i + 1] + n, r = buf[i + 2] + n;
        buf[i] = (byte)(b < 0 ? 0 : b > 255 ? 255 : b);
        buf[i + 1] = (byte)(g < 0 ? 0 : g > 255 ? 255 : g);
        buf[i + 2] = (byte)(r < 0 ? 0 : r > 255 ? 255 : r);
      }
    }
    Marshal.Copy(buf, 0, data.Scan0, buf.Length);
    bmp.UnlockBits(data);
  }

  // Soft bloom: blur a layer by downscaling and scaling back up.
  public static Bitmap Blur(Bitmap src, int down, int up) {
    var small = new Bitmap(Math.Max(1, src.Width / down), Math.Max(1, src.Height / down));
    using (var g = Graphics.FromImage(small)) {
      g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
      g.DrawImage(src, 0, 0, small.Width, small.Height);
    }
    var big = new Bitmap(up, Math.Max(1, (int)((double)src.Height / src.Width * up)));
    using (var g = Graphics.FromImage(big)) {
      g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
      g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
      g.DrawImage(small, 0, 0, big.Width, big.Height);
    }
    small.Dispose();
    return big;
  }
}
"@

function C([int]$a, [int]$v) { [System.Drawing.Color]::FromArgb($a, $v, $v, $v) }
function Cc([int]$a, [int]$r, [int]$g, [int]$b) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

function New-Canvas([int]$top, [int]$bottom) {
  $bmp = New-Object System.Drawing.Bitmap $CW, $CH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $r = New-Object System.Drawing.Rectangle 0, 0, $CW, $CH
  $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush $r, (C 255 $top), (C 255 $bottom), ([single]90)
  $g.FillRectangle($br, $r)
  $br.Dispose()
  return @($bmp, $g)
}

function Add-Glow($g, [double]$cx, [double]$cy, [double]$r, [int]$alpha) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddEllipse([single]($cx - $r), [single]($cy - $r), [single]($r * 2), [single]($r * 2))
  $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $p
  $pgb.CenterPoint = New-Object System.Drawing.PointF([single]$cx, [single]$cy)
  $pgb.CenterColor = (C $alpha 255)
  $pgb.SurroundColors = @((C 0 255))
  $g.FillPath($pgb, $p)
  $pgb.Dispose(); $p.Dispose()
}

function Add-Vignette($g, [int]$strength = 165) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddEllipse([single](-$CW * 0.42), [single](-$CH * 0.85), [single]($CW * 1.84), [single]($CH * 2.7))
  $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $p
  $pgb.CenterColor = (C 0 0)
  $pgb.SurroundColors = @((C $strength 0))
  $g.FillPath($pgb, $p)
  $pgb.Dispose(); $p.Dispose()
}

$script:rnd = New-Object System.Random 20261022

function Add-Dust($g, [int]$count, [double]$maxR = 1.6, [int]$maxAlpha = 120, [double]$bias = 0.55) {
  for ($i = 0; $i -lt $count; $i++) {
    $x = $script:rnd.NextDouble() * $CW
    $y = $script:rnd.NextDouble() * $CH * $bias
    $r = 0.35 + $script:rnd.NextDouble() * $maxR
    $a = [int](20 + $script:rnd.NextDouble() * $maxAlpha)
    $brush = New-Object System.Drawing.SolidBrush (C $a 255)
    $g.FillEllipse($brush, [single]($x - $r), [single]($y - $r), [single]($r * 2), [single]($r * 2))
    $brush.Dispose()
  }
}

function New-Pen([int]$alpha, [double]$w) {
  $p = New-Object System.Drawing.Pen (C $alpha 255), ([single]$w)
  $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  return $p
}

# --- output helpers ---------------------------------------------------------
function Save-Wallpaper([System.Drawing.Bitmap]$layer, [string]$name, [int]$grain = 5) {
  $full = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $g = [System.Drawing.Graphics]::FromImage($full)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.DrawImage($layer, 0, 0, $W, $H)
  $g.Dispose()
  if ($grain -gt 0) { [Wp]::Grain($full, $grain, 991) }

  $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
  $ps = New-Object System.Drawing.Imaging.EncoderParameters 1
  $ps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]94)
  $path = Join-Path $OutDir "$name.jpg"
  $full.Save($path, $enc, $ps)

  $pw = 1600
  $ph = [int]($H * $pw / $W)
  $prev = New-Object System.Drawing.Bitmap $pw, $ph
  $pg = [System.Drawing.Graphics]::FromImage($prev)
  $pg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $pg.DrawImage($full, 0, 0, $pw, $ph)
  $pg.Dispose()
  $prev.Save((Join-Path $OutDir "previews\$name.jpg"), $enc, $ps)
  $prev.Dispose(); $full.Dispose(); $ps.Dispose()
  Write-Output "$name.jpg"
}

# --------------------------------------------------------------------------
# 05 eclipse â€” a dark sphere with a razor-thin rim light
# --------------------------------------------------------------------------
$cv = New-Canvas 13 5
$b = $cv[0]; $g = $cv[1]
Add-Glow $g ($CW * 0.30) ($CH * 0.12) ($CW * 0.55) 20
Add-Dust $g 260 1.2 110 0.9

$cx = $CW * 0.63; $cy = $CH * 0.55; $rad = $CW * 0.30
$sphere = New-Object System.Drawing.Drawing2D.GraphicsPath
$sphere.AddEllipse([single]($cx - $rad), [single]($cy - $rad), [single]($rad * 2), [single]($rad * 2))
$pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $sphere
$pgb.CenterPoint = New-Object System.Drawing.PointF([single]($cx - $rad * 0.35), [single]($cy - $rad * 0.4))
$pgb.CenterColor = (C 255 26)
$pgb.SurroundColors = @((C 255 4))
$g.FillPath($pgb, $sphere)
$pgb.Dispose()

$ring = New-Object System.Drawing.Drawing2D.GraphicsPath
$ring.AddEllipse([single]($cx - $rad * 1.02), [single]($cy - $rad * 1.02), [single]($rad * 2.04), [single]($rad * 2.04))
$pgb2 = New-Object System.Drawing.Drawing2D.PathGradientBrush $ring
$pgb2.CenterPoint = New-Object System.Drawing.PointF([single]($cx - $rad * 0.5), [single]($cy - $rad * 0.55))
$pgb2.CenterColor = (C 0 255)
$pgb2.SurroundColors = @((Cc 0 0 0 0))
$g.FillPath($pgb2, $ring)
$pgb2.Dispose(); $ring.Dispose()

for ($i = 0; $i -lt 5; $i++) {
  $pen = New-Pen (150 - $i * 28) (2.6 - $i * 0.4)
  $g.DrawArc($pen, [single]($cx - $rad), [single]($cy - $rad), [single]($rad * 2), [single]($rad * 2), 150, 160)
  $pen.Dispose()
}
$halo = New-Pen 26 8
$g.DrawArc($halo, [single]($cx - $rad), [single]($cy - $rad), [single]($rad * 2), [single]($rad * 2), 150, 160)
$halo.Dispose()

$outer = New-Pen 16 1.2
$g.DrawEllipse($outer, [single]($cx - $rad * 1.35), [single]($cy - $rad * 1.35), [single]($rad * 2.7), [single]($rad * 2.7))
$outer.Dispose()

Add-Vignette $g 180
Save-Wallpaper $b "05-eclipse" 4 | Out-Null
$g.Dispose(); $b.Dispose()

# --------------------------------------------------------------------------
# 06 monolith â€” one pale slab floating in the dark
# --------------------------------------------------------------------------
$cv = New-Canvas 14 5
$b = $cv[0]; $g = $cv[1]
Add-Glow $g ($CW * 0.22) ($CH * 0.16) ($CW * 0.62) 24
Add-Glow $g ($CW * 0.72) ($CH * 0.92) ($CW * 0.42) 12

$x0 = $CW * 0.545; $y0 = $CH * 0.20; $x1 = $CW * 0.745; $y1 = $CH * 0.845; $rr = $CW * 0.006
$rect = New-Object System.Drawing.RectangleF ([single]$x0), ([single]$y0), ([single]($x1 - $x0)), ([single]($y1 - $y0))
$slab = New-Object System.Drawing.Drawing2D.GraphicsPath
$slab.AddArc([single]$x0, [single]$y0, [single]($rr * 2), [single]($rr * 2), 180, 90)
$slab.AddArc([single]($x1 - $rr * 2), [single]$y0, [single]($rr * 2), [single]($rr * 2), 270, 90)
$slab.AddArc([single]($x1 - $rr * 2), [single]($y1 - $rr * 2), [single]($rr * 2), [single]($rr * 2), 0, 90)
$slab.AddArc([single]$x0, [single]($y1 - $rr * 2), [single]($rr * 2), [single]($rr * 2), 90, 90)
$slab.CloseFigure()
$lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, (C 255 44), (C 255 9), ([single]70)
$g.FillPath($lg, $slab)
$lg.Dispose()

$edge = New-Pen 210 3.0
$g.DrawLine($edge, [single]$x0, [single]$y0, [single]$x0, [single]$y1)
$edge.Dispose()
$edge2 = New-Pen 70 2.0
$g.DrawLine($edge2, [single]$x0, [single]$y0, [single]$x1, [single]$y0)
$edge2.Dispose()
$edge3 = New-Pen 40 2.0
$g.DrawLine($edge3, [single]$x1, [single]$y0, [single]$x1, [single]$y1)
$edge3.Dispose()

$glowPen = New-Pen 22 10
$g.DrawLine($glowPen, [single]$x0, [single]$y0, [single]$x0, [single]$y1)
$glowPen.Dispose()

$refl = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF ([single]$x0), ([single]$y1), ([single]($x1 - $x0)), ([single]($CH * 0.12))), (Cc 26 255 255 255), (Cc 0 255 255 255), ([single]90)
$g.FillRectangle($refl, [single]$x0, [single]$y1, [single]($x1 - $x0), [single]($CH * 0.12))
$refl.Dispose()

Add-Dust $g 180 1.4 95 0.95
Add-Vignette $g 175
Save-Wallpaper $b "06-monolith" 4 | Out-Null
$g.Dispose(); $b.Dispose()

# --------------------------------------------------------------------------
# 07 silk â€” satin ribbons folding through the frame
# --------------------------------------------------------------------------
$cv = New-Canvas 15 5
$b = $cv[0]; $g = $cv[1]
Add-Glow $g ($CW * 0.68) ($CH * 0.22) ($CW * 0.5) 18

function Add-Ribbon($g, [double]$yBase, [double]$amp, [double]$phase, [int]$alpha, [double]$thick) {
  $top = New-Object System.Drawing.Drawing2D.GraphicsPath
  $bot = New-Object System.Drawing.Drawing2D.GraphicsPath
  $pts = @()
  for ($i = 0; $i -le 24; $i++) {
    $t = $i / 24.0
    $x = $t * $CW
    $y = $yBase * $CH + [Math]::Sin($phase + $t * 4.2) * $amp * $CH + $t * $CH * 0.10
    $pts += , @([single]$x, [single]$y)
  }
  $top.AddCurve([System.Drawing.PointF[]]($pts | ForEach-Object { New-Object System.Drawing.PointF $_[0], $_[1] }), 0.5)
  $botPts = @()
  for ($i = $pts.Count - 1; $i -ge 0; $i--) { $botPts += , @([single]$pts[$i][0], [single]($pts[$i][1] + $thick * $CH)) }
  $top.AddCurve([System.Drawing.PointF[]]($botPts | ForEach-Object { New-Object System.Drawing.PointF $_[0], $_[1] }), 0.5)
  $top.CloseFigure()

  $bounds = $top.GetBounds()
  $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bounds, (C $alpha 46), (C $alpha 7), ([single]90)
  $g.FillPath($lg, $top)
  $lg.Dispose()

  $pen = New-Pen ([int]($alpha * 0.55)) 1.4
  $g.DrawCurve($pen, [System.Drawing.PointF[]]($pts | ForEach-Object { New-Object System.Drawing.PointF $_[0], $_[1] }), 0.5)
  $pen.Dispose()
  $top.Dispose()
}

Add-Ribbon $g 0.30 0.055 0.4 150 0.13
Add-Ribbon $g 0.46 0.070 1.7 130 0.10
Add-Ribbon $g 0.60 0.050 3.1 118 0.16
Add-Ribbon $g 0.74 0.062 4.6 100 0.09
Add-Dust $g 120 1.1 70 0.6
Add-Vignette $g 185
Save-Wallpaper $b "07-silk" 4 | Out-Null
$g.Dispose(); $b.Dispose()

# --------------------------------------------------------------------------
# 08 contour â€” topographic rings and a blade of light
# --------------------------------------------------------------------------
$cv = New-Canvas 12 4
$b = $cv[0]; $g = $cv[1]
Add-Glow $g ($CW * 0.38) ($CH * 0.62) ($CW * 0.5) 16

$ccx = $CW * 0.36; $ccy = $CH * 0.66
for ($i = 1; $i -le 16; $i++) {
  $r = $i * $CW * 0.032
  $a = [int](48 - $i * 2.1)
  if ($a -lt 8) { $a = 8 }
  $pen = New-Pen $a (1.6 - $i * 0.03)
  $g.DrawEllipse($pen, [single]($ccx - $r), [single]($ccy - $r * 0.78), [single]($r * 2), [single]($r * 1.56))
  $pen.Dispose()
}

$band = New-Object System.Drawing.Drawing2D.GraphicsPath
$band.AddPolygon([System.Drawing.PointF[]]@(
  (New-Object System.Drawing.PointF 0, ([single]($CH * 0.02))),
  (New-Object System.Drawing.PointF ([single]$CW), ([single]($CH * 0.42))),
  (New-Object System.Drawing.PointF ([single]$CW), ([single]($CH * 0.60))),
  (New-Object System.Drawing.PointF 0, ([single]($CH * 0.20)))
))
$bgb = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF 0, 0, ([single]$CW), ([single]$CH)), (Cc 0 255 255 255), (Cc 0 255 255 255), ([single]115)
$blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
$blend.Colors = @((Cc 0 255 255 255), (Cc 34 255 255 255), (Cc 0 255 255 255))
$blend.Positions = @([single]0, [single]0.5, [single]1)
$bgb.InterpolationColors = $blend
$g.FillPath($bgb, $band)
$bgb.Dispose(); $band.Dispose()

$pen2 = New-Pen 120 1.0
$g.DrawLine($pen2, [single]0, [single]($CH * 0.11), [single]$CW, [single]($CH * 0.51))
$pen2.Dispose()

Add-Dust $g 200 1.3 85 0.85
Add-Vignette $g 175
Save-Wallpaper $b "08-contour" 4 | Out-Null
$g.Dispose(); $b.Dispose()

# --------------------------------------------------------------------------
# 09 prism â€” three glass plates stacked at angles
# --------------------------------------------------------------------------
$cv = New-Canvas 16 4
$b = $cv[0]; $g = $cv[1]
Add-Glow $g ($CW * 0.55) ($CH * 0.48) ($CW * 0.36) 26

$plates = @(
  @{ a = 45; sz = 0.30; dx = -0.02; dy = 0.02; fill = 16; edge = 120 },
  @{ a = 18; sz = 0.26; dx = 0.03; dy = -0.01; fill = 11; edge = 150 },
  @{ a = 0; sz = 0.22; dx = -0.01; dy = 0.0; fill = 8; edge = 190 }
)
foreach ($p in $plates) {
  $side = $CW * $p.sz
  $cx2 = $CW * (0.55 + $p.dx); $cy2 = $CH * (0.50 + $p.dy)
  $state = $g.Save()
  $g.TranslateTransform([single]$cx2, [single]$cy2)
  $g.RotateTransform([single]$p.a)
  $rr = $side * 0.15
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc([single](-$side / 2), [single](-$side / 2), [single]$rr, [single]$rr, 180, 90)
  $path.AddArc([single]($side / 2 - $rr), [single](-$side / 2), [single]$rr, [single]$rr, 270, 90)
  $path.AddArc([single]($side / 2 - $rr), [single]($side / 2 - $rr), [single]$rr, [single]$rr, 0, 90)
  $path.AddArc([single](-$side / 2), [single]($side / 2 - $rr), [single]$rr, [single]$rr, 90, 90)
  $path.CloseFigure()
  $fb = New-Object System.Drawing.SolidBrush (C $p.fill 255)
  $g.FillPath($fb, $path)
  $fb.Dispose()
  $pen = New-Pen $p.edge 1.6
  $g.DrawPath($pen, $path)
  $pen.Dispose()
  $path.Dispose()
  $g.Restore($state)
}

for ($i = 0; $i -lt 3; $i++) {
  $pen = New-Pen (90 - $i * 25) (6 + $i * 6)
  $g.DrawEllipse($pen, [single]($CW * 0.55 - $CW * 0.13), [single]($CH * 0.50 - $CW * 0.13), [single]($CW * 0.26), [single]($CW * 0.26))
  $pen.Dispose()
}

Add-Dust $g 160 1.2 80 0.9
Add-Vignette $g 180
Save-Wallpaper $b "09-prism" 4 | Out-Null
$g.Dispose(); $b.Dispose()

# --------------------------------------------------------------------------
# 10 beacon â€” a shaft of light with drifting motes
# --------------------------------------------------------------------------
$cv = New-Canvas 12 4
$b = $cv[0]; $g = $cv[1]

$state = $g.Save()
$g.TranslateTransform([single]($CW * 0.34), [single]($CH * 0.52))
$g.RotateTransform(-14)
$beamW = $CW * 0.085
$beamH = $CH * 1.5
$br = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF ([single](-$beamW / 2)), ([single](-$beamH / 2)), ([single]$beamW), ([single]$beamH)), (Cc 0 255 255 255), (Cc 0 255 255 255), ([single]0)
$blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
$blend.Colors = @((Cc 0 255 255 255), (Cc 72 255 255 255), (Cc 0 255 255 255))
$blend.Positions = @([single]0, [single]0.5, [single]1)
$br.InterpolationColors = $blend
$g.FillRectangle($br, [single](-$beamW / 2), [single](-$beamH / 2), [single]$beamW, [single]$beamH)
$br.Dispose()
$g.Restore($state)

Add-Glow $g ($CW * 0.34) ($CH * 0.52) ($CW * 0.30) 30
Add-Glow $g ($CW * 0.34) ($CH * 0.52) ($CW * 0.10) 60

$pen = New-Pen 200 2.0
$g.DrawLine($pen, [single]($CW * 0.34), [single]($CH * 0.08), [single]($CW * 0.42), [single]($CH * 0.92))
$pen.Dispose()

Add-Dust $g 320 1.5 120 0.95
Add-Vignette $g 170
Save-Wallpaper $b "10-beacon" 4 | Out-Null
$g.Dispose(); $b.Dispose()

Write-Output "done -> $OutDir"


