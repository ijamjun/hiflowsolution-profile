param(
  [Parameter(Mandatory = $true)]
  [string]$InputPdf,

  [Parameter(Mandatory = $true)]
  [string]$OutputTxt
)

Add-Type -AssemblyName System.IO.Compression

function Convert-PdfEscapedString {
  param([string]$Value)

  $builder = [System.Text.StringBuilder]::new()
  for ($i = 0; $i -lt $Value.Length; $i++) {
    $ch = $Value[$i]
    if ($ch -ne '\') {
      [void]$builder.Append($ch)
      continue
    }

    if ($i + 1 -ge $Value.Length) { break }
    $i++
    $next = $Value[$i]
    switch ($next) {
      'n' { [void]$builder.Append("`n"); break }
      'r' { [void]$builder.Append("`r"); break }
      't' { [void]$builder.Append("`t"); break }
      'b' { [void]$builder.Append("`b"); break }
      'f' { [void]$builder.Append("`f"); break }
      '(' { [void]$builder.Append('('); break }
      ')' { [void]$builder.Append(')'); break }
      '\' { [void]$builder.Append('\'); break }
      default {
        if ($next -match '[0-7]' -and $i + 2 -lt $Value.Length) {
          $octal = [string]$next
          for ($j = 0; $j -lt 2 -and $i + 1 -lt $Value.Length -and $Value[$i + 1] -match '[0-7]'; $j++) {
            $i++
            $octal += [string]$Value[$i]
          }
          [void]$builder.Append([char][Convert]::ToInt32($octal, 8))
        } else {
          [void]$builder.Append($next)
        }
      }
    }
  }

  return $builder.ToString()
}

function Convert-HexPdfString {
  param([string]$Hex)

  $clean = ($Hex -replace '\s+', '')
  if ($clean.Length -lt 2) { return '' }
  if ($clean.Length % 2 -ne 0) { $clean += '0' }

  $bytes = [byte[]]::new($clean.Length / 2)
  for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16)
  }

  if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
    return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
  }

  return [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
}

function Expand-FlateData {
  param([byte[]]$Data)

  $inputStream = [System.IO.MemoryStream]::new($Data)
  try {
    $deflate = [System.IO.Compression.DeflateStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
    $output = [System.IO.MemoryStream]::new()
    $deflate.CopyTo($output)
    $deflate.Dispose()
    return ,$output.ToArray()
  } catch {
    return ,$Data
  } finally {
    $inputStream.Dispose()
  }
}

function Get-TextFromContent {
  param([string]$Content)

  $parts = [System.Collections.Generic.List[string]]::new()

  foreach ($match in [regex]::Matches($Content, '\((?:\\.|[^\\)])*\)\s*Tj', 'Singleline')) {
    $inner = $match.Value -replace '^\(', '' -replace '\)\s*Tj$', ''
    $text = Convert-PdfEscapedString $inner
    if ($text.Trim().Length -gt 0) { $parts.Add($text) }
  }

  foreach ($match in [regex]::Matches($Content, '<([0-9A-Fa-f\s]+)>\s*Tj', 'Singleline')) {
    $text = Convert-HexPdfString $match.Groups[1].Value
    if ($text.Trim().Length -gt 0) { $parts.Add($text) }
  }

  foreach ($match in [regex]::Matches($Content, '\[(.*?)\]\s*TJ', 'Singleline')) {
    $arrayContent = $match.Groups[1].Value
    $lineParts = [System.Collections.Generic.List[string]]::new()
    foreach ($stringMatch in [regex]::Matches($arrayContent, '\((?:\\.|[^\\)])*\)|<([0-9A-Fa-f\s]+)>', 'Singleline')) {
      if ($stringMatch.Value.StartsWith('(')) {
        $inner = $stringMatch.Value.Substring(1, $stringMatch.Value.Length - 2)
        $lineParts.Add((Convert-PdfEscapedString $inner))
      } else {
        $lineParts.Add((Convert-HexPdfString $stringMatch.Groups[1].Value))
      }
    }
    $line = ($lineParts -join '')
    if ($line.Trim().Length -gt 0) { $parts.Add($line) }
  }

  return $parts
}

$pdfPath = (Resolve-Path -LiteralPath $InputPdf).Path
$bytes = [System.IO.File]::ReadAllBytes($pdfPath)
$latin = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
$allText = [System.Collections.Generic.List[string]]::new()

foreach ($match in [regex]::Matches($latin, '<<(.*?)>>\s*stream\r?\n(.*?)\r?\nendstream', 'Singleline')) {
  $dict = $match.Groups[1].Value
  $streamText = $match.Groups[2].Value
  $streamBytes = [System.Text.Encoding]::GetEncoding(28591).GetBytes($streamText)

  if ($dict -match '/FlateDecode') {
    $streamBytes = Expand-FlateData $streamBytes
  }

  if ($null -eq $streamBytes) {
    continue
  }

  $decoded = [System.Text.Encoding]::GetEncoding(28591).GetString($streamBytes)
  foreach ($text in (Get-TextFromContent $decoded)) {
    $allText.Add($text)
  }
}

if ($allText.Count -eq 0) {
  foreach ($text in (Get-TextFromContent $latin)) {
    $allText.Add($text)
  }
}

$normalized = ($allText -join "`r`n") -replace '[^\S\r\n]+', ' '
$normalized = [regex]::Replace($normalized, "(\r?\n){3,}", "`r`n`r`n")
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $OutputTxt), $normalized.Trim(), [System.Text.Encoding]::UTF8)
