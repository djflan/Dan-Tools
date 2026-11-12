# Downloads Dan-Tools (incl. WindowsSetup) to %LOCALAPPDATA%\WindowsSetup\Dan-Tools without needing git.
#   irm https://raw.githubusercontent.com/djflan/Dan-Tools/main/WindowsSetup/get.ps1 | iex
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

$base = Join-Path $env:LOCALAPPDATA 'WindowsSetup'
$dest = Join-Path $base 'Dan-Tools'
$zip = Join-Path $env:TEMP 'Dan-Tools-main.zip'

New-Item -ItemType Directory -Path $base -Force | Out-Null
Invoke-WebRequest -Uri 'https://github.com/djflan/Dan-Tools/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $base -Force
Rename-Item (Join-Path $base 'Dan-Tools-main') 'Dan-Tools'
Remove-Item $zip
Get-ChildItem $dest -Recurse -File | Unblock-File

$bootstrap = Join-Path $dest 'WindowsSetup\bootstrap.ps1'
Write-Host "Downloaded to $dest" -ForegroundColor Green
Write-Host 'Next (preview first with -WhatIf):'
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$bootstrap`" -WorkBundle `"$HOME\Downloads\WindowsSetup-WorkBundle.zip`""
