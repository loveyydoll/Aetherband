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

    $desktopProject = Join-Path $repoRoot "apps/desktop/RouletteStudio.Desktop/RouletteStudio.Desktop.csproj"
    if (Test-Path $desktopProject) {
        Write-Host "== .NET: restore and build desktop app =="
        dotnet restore $desktopProject
        if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed." }
        dotnet build $desktopProject --no-restore --configuration Debug
        if ($LASTEXITCODE -ne 0) { throw "dotnet build failed." }
    } else {
        Write-Warning "Desktop .csproj was not found; .NET build skipped."
    }

    $testProjects = Get-ChildItem -Path $repoRoot -Recurse -Filter "*Tests.csproj" |
        Where-Object { $_.FullName -notmatch "[\\/](bin|obj)[\\/]" }
    foreach ($testProject in $testProjects) {
        Write-Host "== .NET tests: $($testProject.FullName) =="
        dotnet test $testProject.FullName --configuration Debug
        if ($LASTEXITCODE -ne 0) { throw "dotnet test failed: $($testProject.FullName)" }
    }
    if (-not $testProjects) { Write-Host "No *Tests.csproj projects found; .NET test step skipped." }

    Write-Host "Verification commands completed successfully."
}
finally {
    Pop-Location
}