# Generates the cinematic monochrome wallpaper set with GDI+ (no external deps).
# Backgrounds are painted per-pixel in C# so soft light never bands, then the
# vector shapes are composed on top at full resolution.
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
$CW = $W
$CH = $H

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "previews") | Out-Null

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class Wp {
  static double Smooth(double a, double b, double x) {
    double t = (x - a) / (b - a);
    if (t < 0) t = 0; if (t > 1) t = 1;
    return t * t * (3 - 2 * t);
  }

  public static Bitmap Background(int w, int h, int top, int bottom,
      double l1x, double l1y, double l1r, double l1s,
      double l2x, double l2y, double l2r, double l2s,
      double l3x, double l3y, double l3r, double l3s,
      double vig) {
    var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
    int stride = data.Stride;
    var buf = new byte[stride * h];
    var rnd = new Random(11);
    for (int y = 0; y < h; y++) {
      double ty = y / (double)h;
      double basev = bottom + (top - bottom) * Smooth(0, 1, ty);
      double dmy = (y - h * 0.5) / (h * 0.5);
      int row = y * stride;
      for (int x = 0; x < w; x++) {
        double v = basev;
        double dx = (x - l1x * w) / (l1r * w);
        double dy = (y - l1y * h) / (l1r * w);
        v += l1s * Math.Exp(-(dx * dx + dy * dy) * 2.0);
        dx = (x - l2x * w) / (l2r * w);
        dy = (y - l2y * h) / (l2r * w);
        v += l2s * Math.Exp(-(dx * dx + dy * dy) * 2.0);
        dx = (x - l3x * w) / (l3r * w);
        dy = (y - l3y * h) / (l3r * w);
        v += l3s * Math.Exp(-(dx * dx + dy * dy) * 2.0);
        double dmx = (x - w * 0.5) / (w * 0.5);
        double dm = Math.Sqrt(dmx * dmx + dmy * dmy);
        v *= 1.0 - vig * Smooth(0.45, 1.30, dm);
        v += (rnd.NextDouble() - 0.5) * 1.4;
        int iv = (int)(v < 0 ? 0 : v > 255 ? 255 : v);
        int i = row + x * 4;
        buf[i] = (byte)iv; buf[i + 1] = (byte)iv; buf[i + 2] = (byte)iv; buf[i + 3] = 255;
      }
    }
    Marshal.Copy(buf, 0, data.Scan0, buf.Length);
    bmp.UnlockBits(data);
    return bmp;
  }

  public static void Glow(Bitmap bmp, double cx, double cy, double r, double strength) {
    int w = bmp.Width, h = bmp.Height;
    int x0 = Math.Max(0, (int)(cx - r * 2.6)), x1 = Math.Min(w - 1, (int)(cx + r * 2.6));
    int y0 = Math.Max(0, (int)(cy - r * 2.6)), y1 = Math.Min(h - 1, (int)(cy + r * 2.6));
    if (x1 <= x0 || y1 <= y0) return;
    var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    int stride = data.Stride;
    var buf = new byte[stride * h];
    Marshal.Copy(data.Scan0, buf, 0, buf.Length);
    var rnd = new Random(5);
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        double dx = (x - cx) / r;
        double dy = (y - cy) / r;
        double d = Math.Exp(-(dx * dx + dy * dy) * 1.7) * strength;
        if (d < 0.4) continue;
        int i = y * stride + x * 4;

        int dv = (int)(d + (rnd.NextDouble() - 0.5) * 1.2);
        int b = buf[i] + dv, g = buf[i + 1] + dv, rr = buf[i + 2] + dv;
        buf[i] = (byte)(b > 255 ? 255 : b);
        buf[i + 1] = (byte)(g > 255 ? 255 : g);
        buf[i + 2] = (byte)(rr > 255 ? 255 : rr);
      }
    }
    Marshal.Copy(buf, 0, data.Scan0, buf.Length);
    bmp.UnlockBits(data);
  }

  public static void Grain(Bitmap bmp, int amount, int seed) {
    var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
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

  public static Bitmap Blur(Bitmap src, int down) {
    var small = new Bitmap(Math.Max(1, src.Width / down), Math.Max(1, src.Height / down), PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(small)) {
      g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBilinear;
      g.DrawImage(src, 0, 0, small.Width, small.Height);
    }
    var big = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
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

function New-Bg([int]$top, [int]$bottom, [double[]]$l1, [double[]]$l2, [double[]]$l3, [double]$vig = 0.5) {
  return [Wp]::Background($CW, $CH, $top, $bottom,
    $l1[0], $l1[1], $l1[2], $l1[3],
    $l2[0], $l2[1], $l2[2], $l2[3],
    $l3[0], $l3[1], $l3[2], $l3[3], $vig)
}

function New-G($bmp) {
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
  return $g
}

function New-Pen([int]$alpha, [double]$w) {
  $p = New-Object System.Drawing.Pen (C $alpha 255), ([single]$w)
  $p.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  $p.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $p.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  return $p
}

function Add-Dust($g, [int]$count, [double]$maxR = 1.5, [int]$maxAlpha = 110) {
  $rnd = New-Object System.Random 4242
  for ($i = 0; $i -lt $count; $i++) {
    $x = $rnd.NextDouble() * $CW
    $y = $rnd.NextDouble() * $CH
    $r = 0.4 + $rnd.NextDouble() * $maxR
    $a = [int](16 + $rnd.NextDouble() * $maxAlpha)
    $br = New-Object System.Drawing.SolidBrush (C $a 255)
    $g.FillEllipse($br, [single]($x - $r), [single]($y - $r), [single]($r * 2), [single]($r * 2))
    $br.Dispose()
  }
}

function Round-Path([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddArc([single]$x, [single]$y, [single]($r * 2), [single]($r * 2), 180, 90)
  $p.AddArc([single]($x + $w - $r * 2), [single]$y, [single]($r * 2), [single]($r * 2), 270, 90)
  $p.AddArc([single]($x + $w - $r * 2), [single]($y + $h - $r * 2), [single]($r * 2), [single]($r * 2), 0, 90)
  $p.AddArc([single]$x, [single]($y + $h - $r * 2), [single]($r * 2), [single]($r * 2), 90, 90)
  $p.CloseFigure()
  return $p
}

function Save-Wallpaper([System.Drawing.Bitmap]$bmp, [string]$name, [int]$grain = 4) {
  if ($grain -gt 0) { [Wp]::Grain($bmp, $grain, 991) }
  $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
  $ps = New-Object System.Drawing.Imaging.EncoderParameters 1
  $ps.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]94)
  $bmp.Save((Join-Path $OutDir "$name.jpg"), $enc, $ps)

  $pw = 1600
  $ph = [int]($H * $pw / $W)
  $prev = New-Object System.Drawing.Bitmap $pw, $ph
  $pg = New-G $prev
  $pg.DrawImage($bmp, 0, 0, $pw, $ph)
  $pg.Dispose()
  $prev.Save((Join-Path $OutDir "previews\$name.jpg"), $enc, $ps)
  $prev.Dispose(); $ps.Dispose()
  Write-Output "$name.jpg"
}

# --------------------------------------------------------------------------
# 05 eclipse — dark sphere, razor rim light, deep space
# --------------------------------------------------------------------------
$b = New-Bg 22 5 @(0.28, 0.12, 0.62, 16) @(0.86, 0.92, 0.45, 6) @(0, 0, 1, 0) 0.34
$g = New-G $b
Add-Dust $g 300 1.1 90

$cx = $CW * 0.62; $cy = $CH * 0.56; $rad = $CW * 0.285
[Wp]::Glow($b, $cx - $rad * 0.85, $cy - $rad * 0.85, $rad * 0.55, 14)

$sphere = New-Object System.Drawing.Drawing2D.GraphicsPath
$sphere.AddEllipse([single]($cx - $rad), [single]($cy - $rad), [single]($rad * 2), [single]($rad * 2))
$pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush $sphere
$pgb.CenterPoint = New-Object System.Drawing.PointF([single]($cx - $rad * 0.4), [single]($cy - $rad * 0.45))
$pgb.CenterColor = (C 255 20)
$pgb.SurroundColors = @((C 255 3))
$g.FillPath($pgb, $sphere)
$pgb.Dispose(); $sphere.Dispose()

for ($i = 0; $i -lt 7; $i++) {
  $pen = New-Pen (215 - $i * 26) (3.4 - $i * 0.35)
  $g.DrawArc($pen, [single]($cx - $rad), [single]($cy - $rad), [single]($rad * 2), [single]($rad * 2), 178, 150)
  $pen.Dispose()
}
$g.Dispose()
[Wp]::Glow($b, $cx - $rad * 0.62, $cy - $rad * 0.78, $rad * 0.26, 26)
[Wp]::Glow($b, $cx - $rad * 0.62, $cy - $rad * 0.78, $rad * 0.55, 10)
$g = New-G $b
$fo = New-Pen 14 1.2
$g.DrawEllipse($fo, [single]($cx - $rad * 1.42), [single]($cy - $rad * 1.42), [single]($rad * 2.84), [single]($rad * 2.84))
$fo.Dispose()
$g.Dispose()
Save-Wallpaper $b "05-eclipse" 4 | Out-Null
$b.Dispose()

# --------------------------------------------------------------------------
# 06 monolith — pale slab floating, thin edge light
# --------------------------------------------------------------------------
$b = New-Bg 26 6 @(0.20, 0.14, 0.58, 18) @(0.80, 0.95, 0.40, 5) @(0, 0, 1, 0) 0.32
$g = New-G $b
Add-Dust $g 160 1.3 70

$x0 = $CW * 0.555; $y0 = $CH * 0.185; $x1 = $CW * 0.735; $y1 = $CH * 0.825
$rr = $CW * 0.005
$slab = Round-Path $x0 $y0 ($x1 - $x0) ($y1 - $y0) $rr
$rect = New-Object System.Drawing.RectangleF ([single]$x0), ([single]$y0), ([single]($x1 - $x0)), ([single]($y1 - $y0))
$lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, (C 255 78), (C 255 16), ([single]74)
$g.FillPath($lg, $slab)
$lg.Dispose()


$edge = New-Pen 245 3.4
$g.DrawLine($edge, [single]$x0, [single]$y0, [single]$x0, [single]$y1)
$edge.Dispose()
$edge2 = New-Pen 80 2.0
$g.DrawLine($edge2, [single]$x0, [single]$y0, [single]$x1, [single]$y0)
$edge2.Dispose()
$edge3 = New-Pen 34 2.0
$g.DrawLine($edge3, [single]$x1, [single]$y0, [single]$x1, [single]$y1)
$edge3.Dispose()
$g.Dispose()

[Wp]::Glow($b, $x0 - $CW * 0.01, ($y0 + $y1) / 2, ($y1 - $y0) * 0.55, 10)`r`n[Wp]::Glow($b, $x0, ($y0 + $y1) / 2, ($y1 - $y0) * 0.30, 12)
[Wp]::Glow($b, $x0, ($y0 + $y1) / 2, ($y1 - $y0) * 0.35, 10)
[Wp]::Glow($b, ($x0 + $x1) / 2, $y1 + $CH * 0.01, $CW * 0.09, 6)
Save-Wallpaper $b "06-monolith" 4 | Out-Null
$b.Dispose()

# --------------------------------------------------------------------------
# 07 silk — blurred satin bands with a lit fold
# --------------------------------------------------------------------------
$b = New-Bg 15 3 @(0.72, 0.18, 0.5, 14) @(0.2, 0.9, 0.5, 5) @(0, 0, 1, 0) 0.55

function Add-Band($bmp, [double]$yBase, [double]$amp, [double]$phase, [int]$peak, [double]$thick, [int]$blur) {
  $layer = New-Object System.Drawing.Bitmap $CW, $CH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $lg2 = New-G $layer
  $pts = @()
  for ($i = 0; $i -le 48; $i++) {
    $t = $i / 48.0
    $x = $t * $CW
    $y = $yBase * $CH + [Math]::Sin($phase + $t * 5.4) * $amp * $CH + $t * $CH * 0.06
    $pts += New-Object System.Drawing.PointF ([single]$x), ([single]$y)
  }
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddCurve([System.Drawing.PointF[]]$pts, 0.5)
  $lower = @()
  for ($i = $pts.Count - 1; $i -ge 0; $i--) { $lower += New-Object System.Drawing.PointF $pts[$i].X, ([single]($pts[$i].Y + $thick * $CH)) }
  $path.AddCurve([System.Drawing.PointF[]]$lower, 0.5)
  $path.CloseFigure()

  $bounds = $path.GetBounds()
  $bb = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bounds, (C $peak 96), (C $peak 6), ([single]90)
  $lg2.FillPath($bb, $path)
  $bb.Dispose()
  $lg2.Dispose()

  $soft = [Wp]::Blur($layer, 10)
  $layer.Dispose()
  $gg = New-G $bmp
  $gg.DrawImage($soft, 0, 0, $CW, $CH)
  $gg.Dispose()
  $soft.Dispose()

  $gg = New-G $bmp
  $pen = New-Pen ([int]($peak * 0.55)) 1.6
  $gg.DrawCurve($pen, [System.Drawing.PointF[]]$pts, 0.5)
  $pen.Dispose()
  $gg.Dispose()
  $path.Dispose()
}

Add-Band $b 0.30 0.06 0.4 150 0.20 12
Add-Band $b 0.46 0.075 2.0 130 0.16 12
Add-Band $b 0.62 0.055 3.4 115 0.22 12
Add-Band $b 0.78 0.065 4.9 95 0.14 12
$g = New-G $b
Add-Dust $g 140 1.1 60
$g.Dispose()
Save-Wallpaper $b "07-silk" 4 | Out-Null
$b.Dispose()

# --------------------------------------------------------------------------
# 08 contour — topographic rings under a blade of light
# --------------------------------------------------------------------------
$b = New-Bg 24 6 @(0.34, 0.62, 0.5, 11) @(0.9, 0.1, 0.45, 6) @(0, 0, 1, 0) 0.33
$g = New-G $b

$ccx = $CW * 0.34; $ccy = $CH * 0.64
for ($i = 1; $i -le 18; $i++) {
  $r = $i * $CW * 0.028
  $a = [int](38 - $i * 1.6)
  if ($a -lt 7) { $a = 7 }
  $pen = New-Pen $a (1.5 - $i * 0.02)
  $g.DrawEllipse($pen, [single]($ccx - $r), [single]($ccy - $r * 0.80), [single]($r * 2), [single]($r * 1.60))
  $pen.Dispose()
}
$g.Dispose()

$wedge = New-Object System.Drawing.Bitmap $CW, $CH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$wg = New-G $wedge
$poly = New-Object System.Drawing.Drawing2D.GraphicsPath
$poly.AddPolygon([System.Drawing.PointF[]]@(
  (New-Object System.Drawing.PointF 0, ([single]($CH * -0.05))),
  (New-Object System.Drawing.PointF ([single]$CW), ([single]($CH * 0.38))),
  (New-Object System.Drawing.PointF ([single]$CW), ([single]($CH * 0.66))),
  (New-Object System.Drawing.PointF 0, ([single]($CH * 0.23)))
))
$wg.FillPath((New-Object System.Drawing.SolidBrush (C 12 255)), $poly)
$wg.Dispose(); $poly.Dispose()
$softW = [Wp]::Blur($wedge, 24)
$wedge.Dispose()
$g = New-G $b
$g.DrawImage($softW, 0, 0)
$g.Dispose(); $softW.Dispose()

$g = New-G $b
$line = New-Pen 70 1.1
$g.DrawLine($line, [single]0, [single]($CH * 0.09), [single]$CW, [single]($CH * 0.52))
$line.Dispose()
Add-Dust $g 180 1.2 70
$g.Dispose()
Save-Wallpaper $b "08-contour" 4 | Out-Null
$b.Dispose()

# --------------------------------------------------------------------------
# 09 prism — stacked glass plates
# --------------------------------------------------------------------------
$b = New-Bg 26 6 @(0.55, 0.46, 0.42, 16) @(0.55, 0.5, 0.16, 12) @(0, 0, 1, 0) 0.32
[Wp]::Glow($b, $CW * 0.55, $CH * 0.50, $CW * 0.30, 16)
$g = New-G $b

$plates = @(
  @{ a = 42; sz = 0.325; dx = -0.035; dy = 0.03; fill = 12; edge = 165 },
  @{ a = 16; sz = 0.275; dx = 0.035; dy = -0.02; fill = 9; edge = 195 },
  @{ a = 0; sz = 0.225; dx = -0.012; dy = 0.0; fill = 6; edge = 225 }
)
foreach ($p in $plates) {
  $side = $CW * $p.sz
  $cx2 = $CW * (0.55 + $p.dx); $cy2 = $CH * (0.50 + $p.dy)
  $state = $g.Save()
  $g.TranslateTransform([single]$cx2, [single]$cy2)
  $g.RotateTransform([single]$p.a)
  $path = Round-Path (-$side / 2) (-$side / 2) $side $side ($side * 0.16)
  $fb = New-Object System.Drawing.SolidBrush (C $p.fill 255)
  $g.FillPath($fb, $path)
  $fb.Dispose()
  $pen = New-Pen $p.edge 2.0
  $g.DrawPath($pen, $path)
  $pen.Dispose()

  $path.Dispose()
  $g.Restore($state)
}
$g.Dispose()

[Wp]::Glow($b, $CW * 0.55, $CH * 0.50, $CW * 0.18, 10)
$g = New-G $b
Add-Dust $g 150 1.2 70
$g.Dispose()
Save-Wallpaper $b "09-prism" 4 | Out-Null
$b.Dispose()

# --------------------------------------------------------------------------
# 10 beacon — volumetric shaft of light
# --------------------------------------------------------------------------
$b = New-Bg 18 4 @(0.36, 0.5, 0.3, 8) @(0, 0, 1, 0) @(0, 0, 1, 0) 0.30

$beam = New-Object System.Drawing.Bitmap $CW, $CH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bg2 = New-G $beam
$state = $bg2.Save()
$bg2.TranslateTransform([single]($CW * 0.36), [single]($CH * 0.52))
$bg2.RotateTransform(-15)
$beamW = $CW * 0.075; $beamH = $CH * 1.7
$br = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.RectangleF ([single](-$beamW / 2)), ([single](-$beamH / 2)), ([single]$beamW), ([single]$beamH)), (Cc 0 255 255 255), (Cc 0 255 255 255), ([single]0)
$blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
$blend.Colors = @((Cc 0 255 255 255), (Cc 55 255 255 255), (Cc 0 255 255 255))
$blend.Positions = @([single]0, [single]0.5, [single]1)
$br.InterpolationColors = $blend
$bg2.FillRectangle($br, [single](-$beamW / 2), [single](-$beamH / 2), [single]$beamW, [single]$beamH)
$br.Dispose()
$bg2.Restore($state)
$bg2.Dispose()
$softB = [Wp]::Blur($beam, 18)
$beam.Dispose()

$g = New-G $b
$g.DrawImage($softB, 0, 0)
$g.Dispose(); $softB.Dispose()

[Wp]::Glow($b, $CW * 0.36, $CH * 0.50, $CW * 0.22, 16)
[Wp]::Glow($b, $CW * 0.36, $CH * 0.50, $CW * 0.07, 24)

$g = New-G $b
$core = New-Pen 120 1.4
$g.DrawLine($core, [single]($CW * 0.365), [single]($CH * 0.04), [single]($CW * 0.497), [single]($CH * 0.96))
$core.Dispose()
Add-Dust $g 300 1.5 110
$g.Dispose()
Save-Wallpaper $b "10-beacon" 4 | Out-Null
$b.Dispose()

Write-Output "done -> $OutDir"




