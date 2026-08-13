Add-Type -AssemblyName System.Drawing

$root = (Resolve-Path -LiteralPath ".").Path
$sourcePath = Join-Path $root "Polygon 7 - Copy.png"
$outDir = Join-Path $root "assets\brand"
$outPath = Join-Path $outDir "hiflow-logo-transparent.png"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$source = [System.Drawing.Bitmap]::new($sourcePath)
$output = [System.Drawing.Bitmap]::new($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

for ($x = 0; $x -lt $source.Width; $x++) {
  for ($y = 0; $y -lt $source.Height; $y++) {
    $pixel = $source.GetPixel($x, $y)
    if ($pixel.R -gt 238 -and $pixel.G -gt 238 -and $pixel.B -gt 238) {
      $output.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, $pixel.R, $pixel.G, $pixel.B))
    } else {
      $output.SetPixel($x, $y, $pixel)
    }
  }
}

$output.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$output.Dispose()
$source.Dispose()

Write-Output $outPath
