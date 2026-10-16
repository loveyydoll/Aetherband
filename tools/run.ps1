# Run script for RouletteStudio
$ErrorActionPreference = "Stop"

& "$PSScriptRoot\build.ps1"

Write-Host "==> Launching RouletteStudio.Desktop..." -ForegroundColor Green
& "C:\Program Files\dotnet\dotnet.exe" run --project "$PSScriptRoot\..\apps\desktop\RouletteStudio.Desktop\RouletteStudio.Desktop.csproj" --no-build
