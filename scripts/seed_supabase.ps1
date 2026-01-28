$ErrorActionPreference = "Stop"

$supabaseUrl = $env:SUPABASE_URL
$serviceKey = $env:SUPABASE_SERVICE_ROLE_KEY

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or [string]::IsNullOrWhiteSpace($serviceKey)) {
  throw "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars."
}

$headers = @{
  "apikey"        = $serviceKey
  "Authorization" = "Bearer $serviceKey"
  "Content-Type"  = "application/json"
  "Prefer"        = "resolution=merge-duplicates"
}

function Invoke-Upsert {
  param(
    [string]$Table,
    [string]$OnConflict,
    [array]$Rows
  )
  if ($Rows.Count -eq 0) { return }
  $url = "$supabaseUrl/rest/v1/$Table?on_conflict=$OnConflict"
  $body = ($Rows | ConvertTo-Json -Depth 6)
  Invoke-RestMethod -Method Post -Uri $url -Headers $headers -Body $body | Out-Null
}

function Chunk {
  param([array]$Items, [int]$Size)
  for ($i = 0; $i -lt $Items.Count; $i += $Size) {
    $end = [Math]::Min($i + $Size - 1, $Items.Count - 1)
    ,$Items[$i..$end]
  }
}

Write-Host "Seeding categories..."
$categoriesPath = Join-Path $PSScriptRoot "..\\data\\categories_fr_ar.json"
$categories = Get-Content -Raw -Path $categoriesPath | ConvertFrom-Json

$parents = @($categories | Where-Object { -not $_.parent_key })
$children = @($categories | Where-Object { $_.parent_key })

$parentRows = $parents | ForEach-Object {
  @{
    slug       = $_.key
    name_fr    = $_.name_fr
    name_ar    = $_.name_ar
    icon       = $_.icon
    sort_order = $_.sort_order
    is_active  = $_.is_active
  }
}

foreach ($chunk in (Chunk -Items $parentRows -Size 200)) {
  Invoke-Upsert -Table "categories" -OnConflict "slug" -Rows $chunk
}

$catMapUrl = "$supabaseUrl/rest/v1/categories?select=id,slug"
$catMap = Invoke-RestMethod -Method Get -Uri $catMapUrl -Headers $headers
$slugToId = @{}
foreach ($row in $catMap) {
  if ($row.slug) { $slugToId[$row.slug] = $row.id }
}

$childRows = $children | ForEach-Object {
  @{
    slug       = $_.key
    name_fr    = $_.name_fr
    name_ar    = $_.name_ar
    icon       = $_.icon
    sort_order = $_.sort_order
    is_active  = $_.is_active
    parent_id  = $slugToId[$_.parent_key]
  }
}

foreach ($chunk in (Chunk -Items $childRows -Size 200)) {
  Invoke-Upsert -Table "categories" -OnConflict "slug" -Rows $chunk
}

Write-Host "Seeding wilayas..."
$wilayasPath = Join-Path $PSScriptRoot "..\\data\\wilayas_dz.csv"
$wilayas = Import-Csv -Path $wilayasPath
$wilayaRows = $wilayas | ForEach-Object {
  @{ code = $_.code; name_fr = $_.name_fr; name_ar = $_.name_ar }
}
foreach ($chunk in (Chunk -Items $wilayaRows -Size 500)) {
  Invoke-Upsert -Table "wilayas" -OnConflict "code" -Rows $chunk
}

Write-Host "Seeding communes..."
$communesPath = Join-Path $PSScriptRoot "..\\data\\communes_dz.csv"
$communes = Import-Csv -Path $communesPath
$communeRows = $communes | ForEach-Object {
  @{ wilaya_code = $_.wilaya_code; name_fr = $_.name_fr; name_ar = $_.name_ar }
}
foreach ($chunk in (Chunk -Items $communeRows -Size 500)) {
  Invoke-Upsert -Table "communes" -OnConflict "wilaya_code,name_fr" -Rows $chunk
}

Write-Host "Seed completed."
