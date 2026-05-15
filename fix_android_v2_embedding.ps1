# Infame Android v2 embedding repair script
# Run from project root: D:\MUSIC APP\musix
# It backs up suspicious Android files, restores a v2 manifest, and removes old generated registrant sources.

$ErrorActionPreference = "Stop"

$root = Get-Location
$backup = Join-Path $root "recovery_android_v2_embedding_fix"
New-Item -ItemType Directory -Force -Path $backup | Out-Null

Write-Host "Project root: $root"
Write-Host "Backup folder: $backup"

$manifest = Join-Path $root "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifest) {
  Copy-Item $manifest (Join-Path $backup "AndroidManifest_before_fix.xml") -Force
}

# This source file should not live in android/app/src/main in a modern Flutter app.
# Flutter generates plugin registrants during build. A checked-in old registrant can trigger v1 embedding checks.
$registrant = Join-Path $root "android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java"
if (Test-Path $registrant) {
  Copy-Item $registrant (Join-Path $backup "GeneratedPluginRegistrant_before_delete.java") -Force
  Remove-Item $registrant -Force
  Write-Host "Deleted checked-in GeneratedPluginRegistrant.java"
}

# If my previous patch accidentally left a root AndroidManifest.xml beside pubspec.yaml,
# remove it. Flutter should use android/app/src/main/AndroidManifest.xml.
$rootManifest = Join-Path $root "AndroidManifest.xml"
if (Test-Path $rootManifest) {
  Copy-Item $rootManifest (Join-Path $backup "Root_AndroidManifest_before_delete.xml") -Force
  Remove-Item $rootManifest -Force
  Write-Host "Deleted accidental root AndroidManifest.xml"
}

# Restore modern v2 manifest with media permissions.
$sourceManifest = Join-Path $PSScriptRoot "android\app\src\main\AndroidManifest.xml"
Copy-Item $sourceManifest $manifest -Force
Write-Host "Restored AndroidManifest.xml with flutterEmbedding=2"

Write-Host ""
Write-Host "Searching for old v1 embedding references..."
$matches = @()
$paths = @(
  "android\app\src\main\AndroidManifest.xml",
  "android\app\src\main\kotlin",
  "android\app\src\main\java"
)

foreach ($p in $paths) {
  $full = Join-Path $root $p
  if (Test-Path $full) {
    $matches += Select-String -Path $full -Pattern "io\.flutter\.app|FlutterApplication|flutterEmbedding`".*`"1|GeneratedPluginRegistrant\.registerWith|ShimPluginRegistry|ShimRegistrar" -Recurse -ErrorAction SilentlyContinue
  }
}

if ($matches.Count -gt 0) {
  Write-Host "WARNING: v1-looking references remain:"
  $matches | ForEach-Object { Write-Host $_.Path ":" $_.LineNumber ":" $_.Line }
} else {
  Write-Host "No obvious v1 embedding references found."
}

Write-Host ""
Write-Host "Now run:"
Write-Host "flutter clean"
Write-Host "flutter pub get"
Write-Host "flutter build apk --debug"
