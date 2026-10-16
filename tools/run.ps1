# Run script for Aetherband
$ErrorActionPreference = "Stop"

& "$PSScriptRoot\build.ps1"

Write-Host "==> Launching Aetherband.Desktop..." -ForegroundColor Green
& "C:\Program Files\dotnet\dotnet.exe" run --project "$PSScriptRoot\..\apps\desktop\Aetherband.Desktop\Aetherband.Desktop.csproj" --no-build
