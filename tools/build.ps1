# Build script for RouletteStudio
$ErrorActionPreference = "Stop"

Write-Host "==> [1/2] Building Rust Audio Core & C-ABI..." -ForegroundColor Cyan
& "$env:USERPROFILE\.cargo\bin\cargo.exe" build -p daw_core_ffi

Write-Host "==> [2/2] Building .NET 10 Desktop Application..." -ForegroundColor Cyan
& "C:\Program Files\dotnet\dotnet.exe" build "$PSScriptRoot\..\apps\desktop\RouletteStudio.Desktop\RouletteStudio.Desktop.csproj"

Write-Host "==> Build Completed Successfully!" -ForegroundColor Green
