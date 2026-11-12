<#
.SYNOPSIS
    Sets up a Windows work laptop: packages, shell, terminal, git, dev tools, VS Code, repos, AI config, RDP.

.DESCRIPTION
    Runs on Windows PowerShell 5.1 or PowerShell 7. Under 5.1 it first installs PowerShell 7
    (winget when elevated, otherwise a per-user zip) and relaunches itself in pwsh.
    Every phase is idempotent; re-run any time. See README.md.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -WorkBundle "$HOME\Downloads\WindowsSetup-WorkBundle.zip"

.EXAMPLE
    .\bootstrap.ps1 -WorkBundle .\WindowsSetup-WorkBundle.zip -WhatIf

.EXAMPLE
    .\bootstrap.ps1 -Only Packages,System      # elevated, after IT grants admin
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Phases: Prereqs, Packages, Fonts, Shell, Terminal, Git, DevTools, VSCode, Repos, AI, RDP, System
    [string[]]$Only,
    [string[]]$Skip,
    # Private work bundle (zip or folder) produced by Export-WorkBundle.ps1.
    [string]$WorkBundle,
    [string]$RepoRoot = 'C:\Git',
    # Package names from packages.psd1 to leave out, e.g. 'Docker Desktop'.
    [string[]]$ExcludePackage
)
$ErrorActionPreference = 'Stop'

if ($env:OS -eq 'Windows_NT') {
    # Files from a downloaded zip carry Mark-of-the-Web; unblock so the module and profile can load.
    Get-ChildItem -Path (Split-Path $PSScriptRoot) -Recurse -File | Unblock-File -WhatIf:$false
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    # Windows PowerShell 5.1: keep this block 5.1-compatible.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    function Find-Pwsh {
        $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        foreach ($candidate in @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:LOCALAPPDATA\Programs\PowerShell 7\pwsh.exe")) {
            if (Test-Path $candidate) { return $candidate }
        }
        return $null
    }

    $pwsh = Find-Pwsh
    if (-not $pwsh) {
        if ($WhatIfPreference) {
            Write-Host 'DRY RUN: PowerShell 7 is required to continue; it would be installed now. Install it and re-run with -WhatIf.' -ForegroundColor Cyan
            exit 0
        }
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($isAdmin -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Host 'Installing PowerShell 7 with winget...'
            winget install --id Microsoft.PowerShell --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
            $pwsh = Find-Pwsh
        }
        if (-not $pwsh) {
            Write-Host 'Installing PowerShell 7 per-user from GitHub...'
            $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
            $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -Headers @{ 'User-Agent' = 'Dan-Tools-WindowsSetup' } -UseBasicParsing
            $asset = $release.assets | Where-Object { $_.name -match "^PowerShell-[\d.]+-win-$arch\.zip$" } | Select-Object -First 1
            if (-not $asset) { throw 'Could not find the PowerShell 7 zip in the latest release.' }
            # Same folder the Packages phase uses for its zip fallback, so it is detected there later.
            $dest = Join-Path $env:LOCALAPPDATA 'Programs\PowerShell 7'
            $zip = Join-Path $env:TEMP $asset.name
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $dest -Force
            Remove-Item $zip
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            if (($userPath -split ';') -notcontains $dest) {
                [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';'), $dest) -join ';').TrimStart(';'), 'User')
            }
            $pwsh = Join-Path $dest 'pwsh.exe'
        }
    }

    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($entry in $PSBoundParameters.GetEnumerator()) {
        if ($entry.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($entry.Value.IsPresent) { $argList += "-$($entry.Key)" }
        } elseif ($entry.Value -is [array]) {
            # -File passes arguments as plain strings; Invoke-WindowsSetup splits comma lists back out.
            $argList += "-$($entry.Key)"; $argList += ($entry.Value -join ',')
        } else {
            $argList += "-$($entry.Key)"; $argList += [string]$entry.Value
        }
    }
    Write-Host "Relaunching in PowerShell 7: $pwsh"
    & $pwsh @argList
    exit $LASTEXITCODE
}

Import-Module (Join-Path $PSScriptRoot 'Setup.psm1') -Force
# The module does its own dry run; a live -WhatIf would also block read-only prep (bundle unzip, logs).
$dryRun = [bool]$WhatIfPreference
$WhatIfPreference = $false
Invoke-WindowsSetup -Only $Only -Skip $Skip -WorkBundle $WorkBundle -RepoRoot $RepoRoot -ExcludePackage $ExcludePackage -DryRun:$dryRun
