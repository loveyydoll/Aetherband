# Build and launch the Aetherband desktop application.
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$desktopProject = Join-Path $repoRoot "apps\desktop\RouletteStudio.Desktop\RouletteStudio.Desktop.csproj"
$dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue

if (-not $dotnetCommand) {
    throw ".NET SDK was not found on PATH. Install the .NET 10 SDK from https://dotnet.microsoft.com/download/dotnet/10.0, then reopen PowerShell."
}

if (-not (Test-Path $desktopProject)) {
    throw "Desktop project not found: $desktopProject"
}

& (Join-Path $PSScriptRoot "build.ps1")

Push-Location $repoRoot
try {
    Write-Host "==> Launching Aetherband desktop application..." -ForegroundColor Green
    & $dotnetCommand.Source run --project $desktopProject --no-build --configuration Debug
    if ($LASTEXITCODE -ne 0) {
        throw "Aetherband exited with code $LASTEXITCODE. Review the error output above."
    }
}
finally {
    Pop-Location
}
