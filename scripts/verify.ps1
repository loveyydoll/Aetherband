$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $repoRoot
try {
    Write-Host "== Rust: formatting =="
    cargo fmt --all -- --check
    if ($LASTEXITCODE -ne 0) { throw "cargo fmt failed. Run 'cargo fmt --all' and review the diff." }

    Write-Host "== Rust: workspace check =="
    cargo check --workspace --all-targets
    if ($LASTEXITCODE -ne 0) { throw "cargo check failed." }

    Write-Host "== Rust: tests =="
    cargo test --workspace --all-targets
    if ($LASTEXITCODE -ne 0) { throw "cargo test failed." }

    $flutterProject = Join-Path $repoRoot "apps/desktop/pubspec.yaml"
    if (Test-Path $flutterProject) {
        Push-Location (Split-Path $flutterProject -Parent)
        try {
            flutter pub get
            if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
            flutter analyze
            if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }
            flutter test
            if ($LASTEXITCODE -ne 0) { throw "flutter test failed." }
        } finally { Pop-Location }
    } else { Write-Warning "Flutter app not found at apps/desktop; Flutter checks skipped." }
    Write-Host "Verification commands completed successfully."
}
finally {
    Pop-Location
}