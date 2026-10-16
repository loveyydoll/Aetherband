# Build the Aetherband Rust audio core and .NET desktop application.
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$desktopProject = Join-Path $repoRoot "apps\desktop\RouletteStudio.Desktop\RouletteStudio.Desktop.csproj"

$CargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $CargoCommand) {
    throw "Rust/Cargo was not found on PATH. Install Rust from https://rustup.rs/, then reopen PowerShell."
}

$DotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $DotnetCommand) {
    throw ".NET SDK was not found on PATH. Install the .NET 10 SDK from https://dotnet.microsoft.com/download/dotnet/10.0, then reopen PowerShell."
}

if (-not (Test-Path $desktopProject)) {
    throw "Desktop project not found: $desktopProject"
}

Push-Location $repoRoot
try {
    Write-Host "==> [1/2] Building Rust audio core and C ABI..." -ForegroundColor Cyan
    & $CargoCommand.Source build -p daw_core_ffi
    if ($LASTEXITCODE -ne 0) {
        throw "Rust build failed with exit code $LASTEXITCODE."
    }

    Write-Host "==> [2/2] Building Aetherband desktop app..." -ForegroundColor Cyan
    & $DotnetCommand.Source build $desktopProject --configuration Debug
    if ($LASTEXITCODE -ne 0) {
        throw ".NET build failed with exit code $LASTEXITCODE."
    }

    Write-Host "==> Build completed successfully." -ForegroundColor Green
}
finally {
    Pop-Location
}
