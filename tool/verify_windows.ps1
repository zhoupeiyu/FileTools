param(
  [string]$InputPdf = "",
  [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

Push-Location (Join-Path $PSScriptRoot "..")
try {
  flutter pub get
  flutter analyze
  flutter test
  flutter build windows

  $appDir = Join-Path "build\windows\x64\runner\$Configuration" ""
  $gs = Join-Path $appDir "ghostscript\bin\gswin64c.exe"
  if (-not (Test-Path $gs)) {
    throw "Bundled Ghostscript not found: $gs"
  }

  if ([string]::IsNullOrWhiteSpace($InputPdf)) {
    $InputPdf = Join-Path $env:TEMP "pdf_compression_verify_input.pdf"
    $encoding = [System.Text.Encoding]::ASCII
    $objects = @(
      "1 0 obj`n<< /Type /Catalog /Pages 2 0 R >>`nendobj`n",
      "2 0 obj`n<< /Type /Pages /Kids [3 0 R] /Count 1 >>`nendobj`n",
      "3 0 obj`n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>`nendobj`n",
      "4 0 obj`n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>`nendobj`n",
      "5 0 obj`n<< /Length 44 >>`nstream`nBT /F1 18 Tf 40 80 Td (PDF Compression) Tj ET`nendstream`nendobj`n"
    )
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append("%PDF-1.4`n")
    $offsets = New-Object System.Collections.Generic.List[int]
    foreach ($object in $objects) {
      $offsets.Add($encoding.GetByteCount($builder.ToString()))
      [void]$builder.Append($object)
    }
    $xrefOffset = $encoding.GetByteCount($builder.ToString())
    [void]$builder.Append("xref`n0 $($objects.Count + 1)`n")
    [void]$builder.Append("0000000000 65535 f `n")
    foreach ($offset in $offsets) {
      [void]$builder.Append(("{0:D10} 00000 n `n" -f $offset))
    }
    [void]$builder.Append("trailer`n<< /Size $($objects.Count + 1) /Root 1 0 R >>`nstartxref`n$xrefOffset`n%%EOF`n")
    [System.IO.File]::WriteAllBytes($InputPdf, $encoding.GetBytes($builder.ToString()))
  }

  $outputPdf = Join-Path $env:TEMP "pdf_compression_verify_output.pdf"
  if (Test-Path $outputPdf) {
    Remove-Item $outputPdf -Force
  }

  $root = Join-Path $appDir "ghostscript"
  $env:GS_LIB = @(
    (Join-Path $root "lib"),
    (Join-Path $root "Resource\Init"),
    (Join-Path $root "Resource\Font"),
    (Join-Path $root "iccprofiles")
  ) -join ";"

  & $gs `
    -sDEVICE=pdfwrite `
    -dCompatibilityLevel=1.4 `
    -dPDFSETTINGS=/ebook `
    -dNOPAUSE `
    -dQUIET `
    -dBATCH `
    "-sOutputFile=$outputPdf" `
    $InputPdf

  if (-not (Test-Path $outputPdf)) {
    throw "Compressed PDF was not created."
  }

  $outputBytes = [System.IO.File]::ReadAllBytes($outputPdf)
  $headerText = [System.Text.Encoding]::ASCII.GetString($outputBytes, 0, 4)
  if ($headerText -ne "%PDF") {
    throw "Compressed output is not a PDF: $outputPdf"
  }

  Write-Host "Windows verification passed."
  Write-Host "Input:  $InputPdf"
  Write-Host "Output: $outputPdf"
}
finally {
  Pop-Location
}
