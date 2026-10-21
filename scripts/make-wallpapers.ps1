# Generates the monochrome wallpaper pack with GDI+ (no external deps).
# Usage: powershell -File scripts/make-wallpapers.ps1 [-Width 3840] [-Height 2160]
param(
  [int]$Width = 3840,
  [int]$Height = 2160,
  [string]$OutDir = (Join-Path (Split-Path $PSScriptRoot -Parent) "wallpapers")
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$W = $Width
$H = $Height
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir "previews") | Out-Null

$script:rand = New-Object System.Random 20261021

function Color([int]$a, [int]$r, [int]$g, [int]$b) {
  return [System.Drawing.Color]::FromArgb($a, $r, $g, $b)
}

function New-Canvas([int]$top, [int]$bottom) {
  $bmp = New-Object System.Drawing.Bitmap $W, $H
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $rect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    (Color 255 $top $top $top),
    (Color 255 $bottom $bottom $bottom),
    [single]90
  )
  $g.FillRectangle($brush, $rect)
  $brush.Dispose()
  return , @($bmp, $g)
}

# One smooth radial glow (single gradient, no banding).
function Add-Radial($g, [double]$cx, [double]$cy, [double]$r, [int]$alpha) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddEllipse([single]($cx - $r), [single]($cy - $r), [single]($r * 2), [single]($r * 2))
  $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
  $pgb.CenterPoint = New-Object System.Drawing.PointF([single]$cx, [single]$cy)
  $pgb.CenterColor = (Color $alpha 255 255 255)
  $pgb.SurroundColors = @((Color 0 255 255 255))
  $g.FillPath($pgb, $path)
  $pgb.Dispose()
  $path.Dispose()
}

function Add-Vignette($g, [int]$strength = 170) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddEllipse([single](-$W * 0.4), [single](-$H * 0.8), [single]($W * 1.8), [single]($H * 2.6))
  $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
  $pgb.CenterColor = (Color 0 0 0 0)
  $pgb.SurroundColors = @((Color $strength 0 0 0))
  $g.FillPath($pgb, $path)
  $pgb.Dispose()
  $path.Dispose()
}

function Add-Noise($g, [int]$alpha = 7, [int]$tile = 256) {
  $noise = New-Object System.Drawing.Bitmap $tile, $tile
  for ($y = 0; $y -lt $tile; $y++) {
    for ($x = 0; $x -lt $tile; $x++) {
      $v = $script:rand.Next(0, 256)
      $noise.SetPixel($x, $y, (Color $alpha $v $v $v))
    }
  }
  $tb = New-Object System.Drawing.TextureBrush($noise)
  $tb.WrapMode = [System.Drawing.Drawing2D.WrapMode]::Tile
  $g.FillRectangle($tb, 0, 0, $W, $H)
  $tb.Dispose()
  $noise.Dispose()
}

function Save-Shot($bmp, [string]$name) {
  $file = Join-Path $OutDir "$name.jpg"
  $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
  $params = New-Object System.Drawing.Imaging.EncoderParameters 1
  $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 95L
  $bmp.Save($file, $codec, $params)
  $preview = New-Object System.Drawing.Bitmap 1600, 900
  $pg = [System.Drawing.Graphics]::FromImage($preview)
  $pg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $pg.DrawImage($bmp, 0, 0, 1600, 900)
  $pg.Dispose()
  $preview.Save((Join-Path $OutDir "previews\$name.jpg"), [System.Drawing.Imaging.ImageFormat]::Jpeg)
  $preview.Dispose()
  "$name.jpg"
}

# 1. Aurora veil: one cold bloom over black plus a soft vertical light shaft.
$c = New-Canvas 5 8
$bmp = $c[0]; $g = $c[1]
Add-Radial $g ($W * 0.85) ($H * -0.08) ($W * 0.42) 15
Add-Radial $g ($W * 0.3) ($H * 0.46) ($W * 0.26) 6
Add-Radial $g ($W * 0.12) ($H * 1.1) ($W * 0.4) 9
Add-Noise $g 18
Save-Shot $bmp "01-aurora-veil"
$g.Dispose(); $bmp.Dispose()

# 2. Ink rings: concentric hairlines drifting off the left edge.
$c = New-Canvas 8 3
$bmp = $c[0]; $g = $c[1]
Add-Radial $g ($W * 0.28) ($H * 0.52) ($W * 0.42) 10
$cx = $W * 0.14; $cy = $H * 0.5
for ($i = 1; $i -le 44; $i++) {
  $r = $W * 0.05 * $i
  $a = [int]([Math]::Max(1, 13 - $i * 0.25))
  $pen = New-Object System.Drawing.Pen (Color $a 255 255 255), ([single](1.1 + $i * 0.015))
  $g.DrawEllipse($pen, [single]($cx - $r), [single]($cy - $r * 0.86), [single]($r * 2), [single]($r * 1.72))
  $pen.Dispose()
}
Add-Noise $g 13
Save-Shot $bmp "02-ink-rings"
$g.Dispose(); $bmp.Dispose()

# 3. Silk folds: wide diagonal translucent bands.
$c = New-Canvas 6 2
$bmp = $c[0]; $g = $c[1]
$g.TranslateTransform([single]($W / 2), [single]($H / 2))
$g.RotateTransform(-22)
$span = [int]($W * 1.8)
for ($i = 0; $i -lt 8; $i++) {
  $x = - $span / 2 + $i * ($span / 8)
  $alpha = 5 + ($i % 3) * 3
  $rect = New-Object System.Drawing.Rectangle ([int]$x), ([int](-$H)), ([int]($span / 8)), ([int]($H * 2))
  $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect, (Color 0 255 255 255), (Color $alpha 255 255 255), [single]0
  )
  $lg.SetBlendTriangularShape([single]0.5, [single]1.0)
  $g.FillRectangle($lg, $rect)
  $lg.Dispose()
}
$g.ResetTransform()
Add-Radial $g ($W * 0.78) ($H * 0.2) ($W * 0.45) 14
Add-Noise $g 13
Save-Shot $bmp "03-silk-folds"
$g.Dispose(); $bmp.Dispose()

# 4. Star grid: fading dot lattice with a single glow.
$c = New-Canvas 6 2
$bmp = $c[0]; $g = $c[1]
Add-Radial $g ($W * 0.5) ($H * 0.44) ($W * 0.4) 14
$step = 64
for ($y = 0; $y -lt $H; $y += $step) {
  for ($x = 0; $x -lt $W; $x += $step) {
    $dx = ($x - $W * 0.5) / ($W * 0.5)
    $dy = ($y - $H * 0.44) / ($H * 0.62)
    $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
    $a = [int]([Math]::Max(0, 26 - $d * 24))
    if ($a -le 0) { continue }
    $b = New-Object System.Drawing.SolidBrush (Color $a 255 255 255)
    $g.FillEllipse($b, $x, $y, 2.2, 2.2)
    $b.Dispose()
  }
}
Add-Noise $g 13
Save-Shot $bmp "04-star-grid"
$g.Dispose(); $bmp.Dispose()
