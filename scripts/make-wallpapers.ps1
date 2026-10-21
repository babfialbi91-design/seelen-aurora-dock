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

# Soft radial bloom built from stacked translucent ellipses.
function Add-Bloom($g, [double]$cx, [double]$cy, [double]$r, [int]$targetAlpha, [int]$steps = 26) {
  $per = [Math]::Max(1, [int]($targetAlpha / $steps))
  for ($i = $steps; $i -ge 1; $i--) {
    $rr = $r * $i / $steps
    $b = New-Object System.Drawing.SolidBrush (Color $per 255 255 255)
    $g.FillEllipse($b, [single]($cx - $rr), [single]($cy - $rr), [single]($rr * 2), [single]($rr * 2))
    $b.Dispose()
  }
}

function Add-Vignette($g, [int]$strength = 200) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddEllipse([single](-$W * 0.35), [single](-$H * 0.75), [single]($W * 1.7), [single]($H * 2.5))
  $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
  $pgb.CenterColor = (Color 0 0 0 0)
  $pgb.SurroundColors = @((Color $strength 0 0 0))
  $g.FillPath($pgb, $path)
  $pgb.Dispose()
  $path.Dispose()
}

function Add-Noise($g, [int]$alpha = 10, [int]$tile = 256) {
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

function Save-Png($bmp, [string]$name) {
  $file = Join-Path $OutDir "$name.png"
  $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
  $preview = New-Object System.Drawing.Bitmap 1600, 900
  $pg = [System.Drawing.Graphics]::FromImage($preview)
  $pg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $pg.DrawImage($bmp, 0, 0, 1600, 900)
  $pg.Dispose()
  $preview.Save((Join-Path $OutDir "previews\$name.jpg"), [System.Drawing.Imaging.ImageFormat]::Jpeg)
  $preview.Dispose()
  "$name.png"
}

# 1. Aurora veil: one big cold bloom over black, thin vertical light band.
$c = New-Canvas 12 4
$bmp = $c[0]; $g = $c[1]
Add-Bloom $g ($W * 0.72) ($H * 0.08) ($W * 0.55) 26
Add-Bloom $g ($W * 0.22) ($H * 1.02) ($W * 0.45) 14
$band = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
  (New-Object System.Drawing.Rectangle ([int]($W * 0.46)), 0, ([int]($W * 0.08)), $H),
  (Color 0 255 255 255), (Color 16 255 255 255), [single]0
)
$g.FillRectangle($band, ([int]($W * 0.46)), 0, ([int]($W * 0.08)), $H)
$band.Dispose()
Add-Noise $g 9
Add-Vignette $g 180
Save-Png $bmp "01-aurora-veil"
$g.Dispose(); $bmp.Dispose()

# 2. Ink rings: concentric hairlines drifting off the left edge.
$c = New-Canvas 14 6
$bmp = $c[0]; $g = $c[1]
Add-Bloom $g ($W * 0.3) ($H * 0.55) ($W * 0.4) 10
$cx = $W * 0.16; $cy = $H * 0.5
for ($i = 1; $i -le 46; $i++) {
  $r = $W * 0.045 * $i
  $a = [int]([Math]::Max(2, 16 - $i * 0.28))
  $pen = New-Object System.Drawing.Pen (Color $a 255 255 255), ([single](1.2 + $i * 0.02))
  $g.DrawEllipse($pen, [single]($cx - $r), [single]($cy - $r * 0.86), [single]($r * 2), [single]($r * 1.72))
  $pen.Dispose()
}
Add-Noise $g 10
Add-Vignette $g 210
Save-Png $bmp "02-ink-rings"
$g.Dispose(); $bmp.Dispose()

# 3. Silk folds: wide diagonal translucent bands.
$c = New-Canvas 10 5
$bmp = $c[0]; $g = $c[1]
$g.TranslateTransform([single]($W / 2), [single]($H / 2))
$g.RotateTransform(-24)
$span = [int]($W * 1.6)
for ($i = 0; $i -lt 7; $i++) {
  $x = - $span / 2 + $i * ($span / 7)
  $alpha = 6 + ($i % 3) * 3
  $rect = New-Object System.Drawing.Rectangle ([int]$x), ([int](-$H)), ([int]($span / 7)), ([int]($H * 2))
  $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect, (Color 0 255 255 255), (Color $alpha 255 255 255), [single]0
  )
  $g.FillRectangle($lg, $rect)
  $lg.Dispose()
}
$g.ResetTransform()
Add-Bloom $g ($W * 0.8) ($H * 0.18) ($W * 0.4) 12
Add-Noise $g 11
Add-Vignette $g 200
Save-Png $bmp "03-silk-folds"
$g.Dispose(); $bmp.Dispose()

# 4. Star grid: fading dot lattice with a single warm-less glow.
$c = New-Canvas 9 3
$bmp = $c[0]; $g = $c[1]
Add-Bloom $g ($W * 0.5) ($H * 0.42) ($W * 0.36) 12
$step = 64
for ($y = 0; $y -lt $H; $y += $step) {
  for ($x = 0; $x -lt $W; $x += $step) {
    $dx = ($x - $W * 0.5) / ($W * 0.5)
    $dy = ($y - $H * 0.42) / ($H * 0.6)
    $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
    $a = [int]([Math]::Max(0, 34 - $d * 30))
    if ($a -le 0) { continue }
    $b = New-Object System.Drawing.SolidBrush (Color $a 255 255 255)
    $g.FillEllipse($b, $x, $y, 2.4, 2.4)
    $b.Dispose()
  }
}
Add-Noise $g 8
Add-Vignette $g 215
Save-Png $bmp "04-star-grid"
$g.Dispose(); $bmp.Dispose()
