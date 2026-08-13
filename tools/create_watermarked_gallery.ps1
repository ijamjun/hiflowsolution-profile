Add-Type -AssemblyName System.Drawing

$root = (Resolve-Path -LiteralPath ".").Path
$logoPath = Join-Path $root "Polygon 7 - Copy.png"
$outDir = Join-Path $root "assets\gallery"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$items = @(
  @{
    SourcePattern = "IMG_20181020_085101.jpg"
    Output = "thermal-inspection.jpg"
  },
  @{
    SourcePattern = "IMG_20181020_130124.jpg"
    Output = "electrical-testing.jpg"
  },
  @{
    SourcePattern = "IMG_20170702_093641.jpg"
    Output = "cctv-field-maintenance.jpg"
  },
  @{
    SourcePattern = "*0012.jpg"
    Output = "cctv-monitoring-test.jpg"
  },
  @{
    SourcePattern = "*0045.jpg"
    Output = "control-cabinet-service.jpg"
  }
)

function Get-CoverRectangle {
  param(
    [int]$SourceWidth,
    [int]$SourceHeight,
    [int]$TargetWidth,
    [int]$TargetHeight
  )

  $sourceRatio = $SourceWidth / $SourceHeight
  $targetRatio = $TargetWidth / $TargetHeight

  if ($sourceRatio -gt $targetRatio) {
    $height = $TargetHeight
    $width = [int]([double]$TargetHeight * $sourceRatio)
    $x = -[int](($width - $TargetWidth) / 2)
    $y = 0
  } else {
    $width = $TargetWidth
    $height = [int]([double]$TargetWidth / $sourceRatio)
    $x = 0
    $y = -[int](($height - $TargetHeight) / 2)
  }

  return [System.Drawing.Rectangle]::new($x, $y, $width, $height)
}

$logo = [System.Drawing.Image]::FromFile($logoPath)
$transparentLogo = [System.Drawing.Bitmap]::new($logo.Width, $logo.Height)
for ($x = 0; $x -lt $logo.Width; $x++) {
  for ($y = 0; $y -lt $logo.Height; $y++) {
    $pixel = ([System.Drawing.Bitmap]$logo).GetPixel($x, $y)
    if ($pixel.R -gt 242 -and $pixel.G -gt 242 -and $pixel.B -gt 242) {
      $transparentLogo.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, $pixel))
    } else {
      $transparentLogo.SetPixel($x, $y, $pixel)
    }
  }
}
$targetWidth = 1200
$targetHeight = 800

foreach ($item in $items) {
  $sourceFile = Get-ChildItem -LiteralPath (Join-Path $root "Pic") -Recurse -File |
    Where-Object { $_.Name -like $item.SourcePattern } |
    Select-Object -First 1
  if ($null -eq $sourceFile) {
    throw "Source image not found: $($item.SourcePattern)"
  }
  $sourcePath = $sourceFile.FullName
  $outputPath = Join-Path $outDir $item.Output

  $source = [System.Drawing.Image]::FromFile($sourcePath)
  $canvas = [System.Drawing.Bitmap]::new($targetWidth, $targetHeight)
  $graphics = [System.Drawing.Graphics]::FromImage($canvas)
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

  $graphics.DrawImage($source, (Get-CoverRectangle $source.Width $source.Height $targetWidth $targetHeight))

  $state = $graphics.Save()
  $graphics.TranslateTransform($targetWidth / 2, $targetHeight / 2)
  $graphics.RotateTransform(-18)

  $wmWidth = [int]($targetWidth * 0.58)
  $wmHeight = [int]($targetHeight * 0.30)
  $wmX = -[int]($wmWidth / 2)
  $wmY = -[int]($wmHeight / 2)

  $bgBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(70, 18, 32, 49))
  $graphics.FillRectangle($bgBrush, $wmX, $wmY, $wmWidth, $wmHeight)

  $logoSize = [int]($wmHeight * 0.72)
  $logoX = $wmX + 54
  $logoY = $wmY + [int](($wmHeight - $logoSize) / 2)
  $logoColorMatrix = [System.Drawing.Imaging.ColorMatrix]::new()
  $logoColorMatrix.Matrix00 = 1
  $logoColorMatrix.Matrix11 = 1
  $logoColorMatrix.Matrix22 = 1
  $logoColorMatrix.Matrix33 = 0.38
  $logoColorMatrix.Matrix44 = 1
  $logoAttrs = [System.Drawing.Imaging.ImageAttributes]::new()
  $logoAttrs.SetColorMatrix($logoColorMatrix)
  $graphics.DrawImage(
    $transparentLogo,
    [System.Drawing.Rectangle]::new($logoX, $logoY, $logoSize, $logoSize),
    0,
    0,
    $transparentLogo.Width,
    $transparentLogo.Height,
    [System.Drawing.GraphicsUnit]::Pixel,
    $logoAttrs
  )
  $logoAttrs.Dispose()

  $font = [System.Drawing.Font]::new("Arial", 92, [System.Drawing.FontStyle]::Bold)
  $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(120, 255, 255, 255))
  $graphics.DrawString("Hiflow", $font, $brush, $logoX + $logoSize + 42, $wmY + 46)
  $graphics.Restore($state)

  $canvas.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)

  $brush.Dispose()
  $font.Dispose()
  $bgBrush.Dispose()
  $graphics.Dispose()
  $canvas.Dispose()
  $source.Dispose()
}

$transparentLogo.Dispose()
$logo.Dispose()
