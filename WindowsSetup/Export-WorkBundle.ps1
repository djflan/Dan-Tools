#Requires -Version 7.2
<#
.SYNOPSIS
    Builds the PRIVATE work bundle consumed by bootstrap.ps1 -WorkBundle. Run it on the old (macOS) machine.

.DESCRIPTION
    Collects, from the live machine:
      - work repos (origin URLs, folder layout) for the given groups under -GitRoot
      - git identity, the includeIf work identity, and credential.* settings (no secrets)
      - Copilot CLI instructions + MCP config, personal Claude skills
      - Windows App (Microsoft Remote Desktop) saved PCs as .rdp files (no passwords)
    Output is a folder plus a zip. It contains internal hostnames and emails: keep it off public
    repos and move it over a work channel (work OneDrive / Teams), not personal storage.

.EXAMPLE
    ./Export-WorkBundle.ps1                      # groups default to the folders your includeIf rules cover
    ./Export-WorkBundle.ps1 -Groups GroupA,GroupB -OutputPath ~/Desktop/WindowsSetup-WorkBundle
#>
[CmdletBinding()]
param(
    [string]$GitRoot = (Join-Path $HOME 'Git'),
    # Folder names under -GitRoot to export. Default: folders targeted by includeIf "gitdir:" rules.
    [string[]]$Groups,
    [string]$OutputPath = (Join-Path $HOME 'Desktop/WindowsSetup-WorkBundle'),
    # Copilot instruction files to leave out (e.g. ones that describe macOS-only tools).
    [string[]]$ExcludeInstruction = @('sqlp.instructions.md'),
    [switch]$SkipRdp
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# `pwsh -File` passes "a,b" as a single string.
$Groups = @($Groups | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$ExcludeInstruction = @($ExcludeInstruction | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
function Get-GitGlobal([string]$Key) { $v = git config --global --get $Key 2>$null; if ($LASTEXITCODE) { $null } else { $v } }

# Repos: work folders come from includeIf "gitdir:<GitRoot>/<Group>/" rules unless -Groups is given.
$includes = @(git config --global --get-regexp '^includeif\.gitdir' 2>$null | ForEach-Object {
    if ($_ -match '^includeif\.gitdir(?:/i)?:(?<dir>\S+)\.path (?<path>.+)$') {
        $dir = $Matches.dir -replace '^~', $HOME
        [pscustomobject]@{ Group = Split-Path ($dir.TrimEnd('/')) -Leaf; Dir = $dir; Path = $Matches.path }
    }
})
if (-not $Groups) { $Groups = @($includes.Group | Select-Object -Unique) }
if (-not $Groups) { throw 'No -Groups given and no includeIf gitdir rules found.' }

function ConvertTo-HttpsUrl([string]$Url) {
    if ($Url -match '^git@github\.com:(?<repo>.+)$') { return "https://github.com/$($Matches.repo)" }
    $Url -replace '^https://[^@/]+@', 'https://'
}

$repos = foreach ($group in $Groups) {
    $groupDir = Join-Path $GitRoot $group
    if (-not (Test-Path $groupDir)) { Write-Warning "Skipping missing group folder $groupDir"; continue }
    # A .git *file* marks a linked worktree of another clone; only export real clones.
    $isClone = { param($path) Test-Path (Join-Path $path '.git') -PathType Container }
    $candidates = if (& $isClone $groupDir) { @(Get-Item $groupDir) } else { @(Get-ChildItem $groupDir -Directory | Where-Object { & $isClone $_.FullName }) }
    foreach ($dir in $candidates) {
        $url = git -C $dir.FullName remote get-url origin 2>$null
        if (-not $url) { Write-Warning "No origin for $($dir.FullName)"; continue }
        [ordered]@{
            group = $group
            path  = [IO.Path]::GetRelativePath($GitRoot, $dir.FullName) -replace '\\', '/'
            url   = ConvertTo-HttpsUrl $url
        }
    }
}

# Git: identity, work include, credential.* (minus the platform-specific helper path).
$workInclude = $null
$workIncludes = @($includes | Where-Object Group -in $Groups)
if ($workIncludes) {
    $includePath = $workIncludes[0].Path -replace '^~', $HOME
    $workEmail = git config --file $includePath --get user.email 2>$null
    $workInclude = [ordered]@{ file = Split-Path $includePath -Leaf; email = $workEmail; groups = @($workIncludes.Group | Select-Object -Unique) }
}
$credentialConfig = @(git config --global --get-regexp '^credential\.' 2>$null | ForEach-Object {
    $key, $value = $_ -split ' ', 2
    if ($key -ne 'credential.helper' -and $value) { [ordered]@{ key = $key; value = $value } }
})

$manifest = [ordered]@{
    exportedAt = (Get-Date).ToString('o')
    exportedFrom = [Environment]::MachineName
    git = [ordered]@{
        name        = Get-GitGlobal 'user.name'
        email       = Get-GitGlobal 'user.email'
        workInclude = $workInclude
        config      = $credentialConfig
    }
    repos = @($repos)
}

if (Test-Path $OutputPath) { Remove-Item $OutputPath -Recurse -Force }
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$manifest | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutputPath 'work-manifest.json') -Encoding utf8NoBOM

# AI config: instructions, MCP config (only if it holds no headers/env secrets), personal Claude skills.
$copilotHome = Join-Path $HOME '.copilot'
$instructionSource = Join-Path $copilotHome 'instructions'
$exportedInstructions = @()
if (Test-Path $instructionSource) {
    $target = Join-Path $OutputPath 'ai/copilot/instructions'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($file in Get-ChildItem $instructionSource -File -Filter '*.md') {
        if ($file.Name -in $ExcludeInstruction) { continue }
        Copy-Item $file.FullName $target
        $exportedInstructions += $file.Name
    }
}
$mcpConfig = Join-Path $copilotHome 'mcp-config.json'
if (Test-Path $mcpConfig) {
    $mcpText = Get-Content $mcpConfig -Raw
    $servers = ($mcpText | ConvertFrom-Json -AsHashtable).mcpServers
    $hasSecrets = $servers.Values | Where-Object { $_.Contains('headers') -or $_.Contains('env') }
    if ($hasSecrets) { Write-Warning 'mcp-config.json has headers/env entries; not exported.' }
    else { Copy-Item $mcpConfig (Join-Path $OutputPath 'ai/copilot/mcp-config.json') }
}
$skillsSource = Join-Path $HOME '.claude/skills'
$exportedSkills = @()
if (Test-Path $skillsSource) {
    # "synced" is managed by Claude itself; dot-folders are trash/state.
    foreach ($skill in Get-ChildItem $skillsSource -Directory | Where-Object { $_.Name -ne 'synced' -and -not $_.Name.StartsWith('.') }) {
        $target = Join-Path $OutputPath "ai/claude/skills/$($skill.Name)"
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Copy-Item (Join-Path $skill.FullName '*') $target -Recurse
        $exportedSkills += $skill.Name
    }
}

# RDP: Windows App (formerly Microsoft Remote Desktop) bookmarks -> clean .rdp files for mstsc.
$rdpCount = 0
$rdcDir = Join-Path $HOME 'Library/Containers/com.microsoft.rdc.macos/Data/Library/Application Support/com.microsoft.rdc.macos'
$rdcDb = Join-Path $rdcDir 'com.microsoft.rdc.application-data.sqlite'
if (-not $SkipRdp -and (Test-Path $rdcDb)) {
    # Copy the DB with its WAL so recent changes are included and the live file is never locked.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "rdc-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tmp | Out-Null
    Get-ChildItem $rdcDir -Filter 'com.microsoft.rdc.application-data.sqlite*' | Copy-Item -Destination $tmp
    $query = @'
select b.ZFRIENDLYNAME as name, b.ZHOSTNAME as host, c.ZUSERNAME as username, g.ZHOSTNAME as gateway,
       f.ZTITLE as folder, b.ZADMINMODE as admin, b.ZSCREENTYPEALLMONITORS as allMonitors
from ZBOOKMARKENTITY b
left join ZCREDENTIALENTITY c on c.Z_PK = b.ZCREDENTIAL
left join ZGATEWAYENTITY g on g.Z_PK = b.ZGATEWAY
left join ZBOOKMARKFOLDERENTITY f on f.Z_PK = b.ZBOOKMARKFOLDER
'@
    $json = sqlite3 -json (Join-Path $tmp 'com.microsoft.rdc.application-data.sqlite') $query
    Remove-Item $tmp -Recurse -Force
    $bookmarks = if ($json) { @($json | Out-String | ConvertFrom-Json) } else { @() }
    foreach ($bm in $bookmarks) {
        if (-not $bm.host) { continue }
        $display = if ($bm.name) { $bm.name } else { $bm.host }
        $folder = if ($bm.folder) { $bm.folder } else { 'Other' }
        $lines = @(
            "full address:s:$($bm.host)"
            'screen mode id:i:2'
            "use multimon:i:$([int][bool]$bm.allMonitors)"
            'dynamic resolution:i:1'
            'smart sizing:i:1'
            'session bpp:i:32'
            'redirectclipboard:i:1'
            'redirectprinters:i:0'
            'audiomode:i:0'
            'autoreconnection enabled:i:1'
            'authentication level:i:2'
            'prompt for credentials:i:0'
            'enablecredsspsupport:i:1'
            "administrative session:i:$([int][bool]$bm.admin)"
        )
        if ($bm.username) { $lines += "username:s:$($bm.username)" }
        if ($bm.gateway) { $lines += "gatewayhostname:s:$($bm.gateway)", 'gatewayusagemethod:i:1', 'gatewayprofileusagemethod:i:1' }
        $safeName = ($display -replace '[\\/:*?"<>|]', '_').Trim()
        $target = Join-Path $OutputPath "rdp/$folder"
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        # mstsc reads UTF-16 LE .rdp files most reliably.
        Set-Content -Path (Join-Path $target "$safeName.rdp") -Value ($lines -join "`r`n") -Encoding Unicode
        $rdpCount++
    }
}

$zipPath = "$OutputPath.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $OutputPath '*') -DestinationPath $zipPath

Write-Host "Work bundle: $zipPath" -ForegroundColor Green
Write-Host "  repos:        $(@($repos).Count) in $($Groups -join ', ')"
Write-Host "  work include: $(if ($workInclude) { "$($workInclude.file) ($($workInclude.groups -join ', '))" } else { 'none' })"
Write-Host "  git config:   $($credentialConfig.Count) credential.* entries"
Write-Host "  copilot:      $($exportedInstructions.Count) instructions ($($exportedInstructions -join ', '))"
Write-Host "  claude:       $($exportedSkills.Count) skills ($($exportedSkills -join ', '))"
Write-Host "  rdp:          $rdpCount connections"
Write-Host 'Keep this private: move it via work OneDrive/Teams, never commit it.' -ForegroundColor Yellow
