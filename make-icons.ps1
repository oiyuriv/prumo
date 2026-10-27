# Gera os ícones PNG do Prumo: fundo preto, luz roxa, fio e prumo facetado em roxo (o mesmo desenho do topo do app).
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot 'icons'
New-Item -ItemType Directory -Force $out | Out-Null

function P([double]$x, [double]$y) { New-Object System.Drawing.PointF ([single]$x), ([single]$y) }

function New-Icon([int]$s, [string]$path) {
  $bmp = New-Object System.Drawing.Bitmap $s, $s
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.Clear([System.Drawing.Color]::FromArgb(255, 0, 0, 0))

  # papel milimetrado bem apagado
  $thin = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(16, 255, 255, 255)), ([single][Math]::Max(1, $s / 512))
  for ($k = 1; $k -lt 8; $k++) { $v = [single]($k * $s / 8); $g.DrawLine($thin, $v, 0, $v, $s); $g.DrawLine($thin, 0, $v, $s, $v) }

  # luz roxa embaixo à esquerda
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.AddEllipse([single](-0.55 * $s), [single](0.3 * $s), [single](1.4 * $s), [single](1.3 * $s))
  $br = New-Object System.Drawing.Drawing2D.PathGradientBrush $gp
  $br.CenterColor = [System.Drawing.Color]::FromArgb(150, 122, 72, 240)
  $br.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
  $g.FillPath($br, $gp)

  # o desenho é o mesmo do SVG do app (caixa 20 x 24), centralizado
  $u = 0.031 * $s
  $ox = $s / 2 - 10 * $u
  $oy = $s / 2 - 12.6 * $u
  $X = { param($x) $ox + $x * $u }
  $Y = { param($y) $oy + $y * $u }

  # fio
  $line = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(230, 236, 228, 255)), ([single](0.016 * $s))
  $g.DrawLine($line, [single](& $X 10), [single](0.05 * $s), [single](& $X 10), [single](& $Y 5.6))

  # tampa
  $cap = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 203, 180, 255))
  $g.FillRectangle($cap, [single](& $X 8.3), [single](& $Y 5.6), [single](3.4 * $u), [single](1.6 * $u))

  # corpo: faceta da direita mais escura, da esquerda mais clara
  $right = [System.Drawing.PointF[]]@((P (& $X 10) (& $Y 7.6)), (P (& $X 13.8) (& $Y 7.6)), (P (& $X 13.8) (& $Y 12.2)), (P (& $X 10) (& $Y 23.6)))
  $left = [System.Drawing.PointF[]]@((P (& $X 10) (& $Y 7.6)), (P (& $X 6.2) (& $Y 7.6)), (P (& $X 6.2) (& $Y 12.2)), (P (& $X 10) (& $Y 23.6)))
  $top = [single](& $Y 7.6); $bot = [single](& $Y 23.6)
  $dark = New-Object System.Drawing.Drawing2D.LinearGradientBrush (P 0 $top), (P 0 $bot), ([System.Drawing.Color]::FromArgb(255, 140, 92, 250)), ([System.Drawing.Color]::FromArgb(255, 74, 36, 168))
  $light = New-Object System.Drawing.Drawing2D.LinearGradientBrush (P 0 $top), (P 0 $bot), ([System.Drawing.Color]::FromArgb(255, 214, 196, 255)), ([System.Drawing.Color]::FromArgb(255, 150, 104, 255))
  $g.FillPolygon($dark, $right)
  $g.FillPolygon($light, $left)

  # aresta do ombro
  $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 255, 255, 255)), ([single][Math]::Max(1, 0.006 * $s))
  $g.DrawLine($edge, [single](& $X 6.2), [single](& $Y 12.2), [single](& $X 13.8), [single](& $Y 12.2))

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}

New-Icon 180 (Join-Path $out 'icon-180.png')
New-Icon 192 (Join-Path $out 'icon-192.png')
New-Icon 512 (Join-Path $out 'icon-512.png')
Write-Host 'Ícones gerados em' $out
