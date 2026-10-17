# Build the Aetherband Rust audio engine and Flutter desktop application.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$flutterProject = Join-Path $repoRoot "apps\desktop\pubspec.yaml"
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { throw "Rust/Cargo was not found on PATH. Install Rust from https://rustup.rs/." }
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "Flutter was not found on PATH. Install Flutter from https://docs.flutter.dev/get-started/install." }
if (-not (Test-Path $flutterProject)) { throw "Flutter project not found: $flutterProject" }
Push-Location $repoRoot
try {
    cargo build -p daw_core_ffi
    if ($LASTEXITCODE -ne 0) { throw "Rust C ABI build failed." }
    Push-Location (Split-Path $flutterProject -Parent)
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
        flutter analyze
        if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }
        flutter build windows --debug
        if ($LASTEXITCODE -ne 0) { throw "Flutter Windows build failed." }
    } finally { Pop-Location }
} finally { Pop-Location }
