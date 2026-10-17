# Build and launch the Aetherband Flutter desktop application on Windows.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$flutterProject = Join-Path $repoRoot "apps\desktop\pubspec.yaml"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "Flutter was not found on PATH. Install Flutter from https://docs.flutter.dev/get-started/install." }
if (-not (Test-Path $flutterProject)) { throw "Flutter project not found: $flutterProject" }
& (Join-Path $PSScriptRoot "build.ps1")
if ($LASTEXITCODE -ne 0) { throw "Build script failed; application will not be launched." }
Push-Location (Split-Path $flutterProject -Parent)
try { flutter run -d windows } finally { Pop-Location }
