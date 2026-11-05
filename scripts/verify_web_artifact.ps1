[CmdletBinding()]
param([string]$WebRoot)

if ([string]::IsNullOrWhiteSpace($WebRoot)) {
  $repoRoot = Split-Path -Parent $PSScriptRoot
  $WebRoot = Join-Path $repoRoot 'build\web'
}

$requiredFiles = @(
  'favicon.png',
  'robots.txt',
  'sitemap.xml',
  'assets\fonts\MaterialIcons-Regular.otf',
  'assets\packages\cupertino_icons\assets\CupertinoIcons.ttf'
)

$missing = @(
  foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $WebRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path).Length -eq 0) {
      $relativePath
    }
  }
)

if ($missing.Count -gt 0) {
  throw "Incomplete Flutter web artifact. Missing: $($missing -join ', ')"
}

Write-Host "Web artifact verified: $WebRoot"
