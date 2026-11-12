#Requires -Version 7.2
# Windows workstation setup. Entry point is bootstrap.ps1; see README.md.
# No Set-StrictMode: catalog/bundle entries are hashtables with optional keys read via dot access.

$script:Phases = @('Prereqs', 'Packages', 'Fonts', 'Shell', 'Terminal', 'Git', 'DevTools', 'VSCode', 'Repos', 'AI', 'RDP', 'System')

$script:Root = $PSScriptRoot
$script:DryRun = $false
$script:IsAdmin = $false
$script:HasWinget = $false
$script:Catalog = $null
$script:Bundle = $null
$script:BundleDir = $null
$script:RepoRoot = 'C:\Git'
$script:Paths = $null
$script:Results = [System.Collections.Generic.List[object]]::new()

# winget exit codes that mean "nothing to do" or "done, reboot pending".
$script:WingetOkCodes = @(0, -1978335189, -1978335135, -1978334967)

#region Helpers

function Add-Result {
    param([string]$Phase, [string]$Item, [string]$Status, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ Phase = $Phase; Item = $Item; Status = $Status; Detail = $Detail })
    $color = switch ($Status) {
        'Present'     { 'DarkGray' }
        'Installed'   { 'Green' }
        'Updated'     { 'Green' }
        'WouldChange' { 'Cyan' }
        'NeedsAdmin'  { 'Yellow' }
        'Manual'      { 'Yellow' }
        'Skipped'     { 'DarkYellow' }
        'Failed'      { 'Red' }
        default       { 'White' }
    }
    $line = '  [{0,-11}] {1}' -f $Status, $Item
    if ($Detail) { $line += " - $Detail" }
    Write-Host $line -ForegroundColor $color
}

# Runs a state-changing action, or only reports it in dry-run mode.
function Invoke-Change {
    param([string]$Phase, [string]$Item, [string]$Detail, [scriptblock]$Action, [string]$DoneStatus = 'Installed')
    if ($script:DryRun) { Add-Result $Phase $Item 'WouldChange' $Detail; return $true }
    try {
        & $Action
        Add-Result $Phase $Item $DoneStatus $Detail
        return $true
    } catch {
        Add-Result $Phase $Item 'Failed' $_.Exception.Message
        return $false
    }
}

function Test-Admin {
    if (-not $IsWindows) { return $false }
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-Command([string]$Name) {
    # The Store "python.exe" app-execution alias is a stub that opens the Store, not a real install.
    Get-Command $Name -CommandType Application -ErrorAction Ignore |
        Where-Object { $_.Source -notmatch '\\Microsoft\\WindowsApps\\python3?\.exe$' } |
        Select-Object -First 1
}

function Get-SetupPaths {
    if ($IsWindows) {
        $local = $env:LOCALAPPDATA
        $documents = [Environment]::GetFolderPath('MyDocuments')
    } else {
        # Dry runs on macOS/Linux resolve Windows locations under a scratch folder.
        $local = Join-Path ([IO.Path]::GetTempPath()) 'WindowsSetup-sim/LocalAppData'
        $documents = Join-Path ([IO.Path]::GetTempPath()) 'WindowsSetup-sim/Documents'
    }
    @{
        LocalAppData = $local
        Programs     = Join-Path $local 'Programs'
        State        = Join-Path $local 'WindowsSetup'
        UserFonts    = Join-Path $local 'Microsoft\Windows\Fonts'
        DotnetUser   = Join-Path $local 'Microsoft\dotnet'
        WtSettings   = Join-Path $local 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
        Documents    = $documents
        Home         = $HOME
    }
}

function Update-SessionPath {
    if (-not $IsWindows) { return }
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';'
    $user = [Environment]::GetEnvironmentVariable('Path', 'User') -split ';'
    $env:Path = (@($machine) + @($user) + @($env:Path -split ';') | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Add-UserPath([string]$Dir) {
    # Edit HKCU\Environment directly so existing %VAR% entries keep their REG_EXPAND_SZ form.
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    try {
        $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $parts = @($raw -split ';' | Where-Object { $_ })
        if ($parts -notcontains $Dir) {
            $key.SetValue('Path', (@($parts) + $Dir) -join ';', [Microsoft.Win32.RegistryValueKind]::ExpandString)
        }
    } finally { $key.Dispose() }
    if (($env:Path -split ';') -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }
}

function Send-EnvironmentChange {
    # SetEnvironmentVariable broadcasts WM_SETTINGCHANGE so Explorer-launched apps see PATH changes.
    if (-not $IsWindows -or $script:DryRun) { return }
    [Environment]::SetEnvironmentVariable('WINDOWS_SETUP_REFRESH', '1', 'User')
    [Environment]::SetEnvironmentVariable('WINDOWS_SETUP_REFRESH', $null, 'User')
}

function Save-Download([string]$Url, [string]$FileName) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) "WindowsSetup-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $out = Join-Path $dir $FileName
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $out -Headers @{ 'User-Agent' = 'Dan-Tools-WindowsSetup' }
    $out
}

function Get-GitHubAssetUrl([string]$Repo, [string]$Pattern) {
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'Dan-Tools-WindowsSetup' }
    $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
    if (-not $asset) { throw "No asset matching '$Pattern' in $Repo $($release.tag_name)" }
    $asset.browser_download_url
}

# Puts the folder holding <Command>.exe/.cmd (searched under $Dir) on the user PATH.
function Add-ProgramToPath([string]$Dir, [string]$Command, [string]$From) {
    $exe = Get-ChildItem $Dir -Recurse -File |
        Where-Object { $_.Name -in "$Command.exe", "$Command.cmd" } |
        Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $exe) { throw "$Command.exe not found in $From" }
    Add-UserPath $exe.DirectoryName
}

# Extracts a zip to %LOCALAPPDATA%\Programs\<Name> and puts <Command> on the user PATH.
function Install-ZipToPrograms([string]$Name, [string]$Url, [string]$Command) {
    $zip = Save-Download $Url "$($Name -replace '[^\w.-]', '_').zip"
    $dest = Join-Path $script:Paths.Programs $Name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    Remove-Item (Split-Path $zip) -Recurse -Force
    Add-ProgramToPath $dest $Command $Url
}

# Unpacks an MSI without installing it (msiexec /a needs no admin) for self-contained apps like AWS CLI.
function Install-MsiExtract([string]$Name, [string]$Url, [string]$Command) {
    $msi = Save-Download $Url "$($Name -replace '[^\w.-]', '_').msi"
    $dest = Join-Path $script:Paths.Programs $Name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    $proc = Start-Process msiexec.exe -ArgumentList '/a', "`"$msi`"", '/qn', "TARGETDIR=`"$dest`"" -Wait -PassThru
    Remove-Item (Split-Path $msi) -Recurse -Force
    if ($proc.ExitCode) { throw "msiexec /a exit $($proc.ExitCode)" }
    Add-ProgramToPath $dest $Command $Url
}

# Copies a managed config file, backing up a differing existing file first. Returns Present/Installed/Updated.
function Copy-ManagedFile {
    param([string]$Phase, [string]$Item, [string]$Source, [string]$Destination)
    if (-not (Test-Path $Source)) { Add-Result $Phase $Item 'Failed' "missing source $Source"; return }
    if (Test-Path $Destination) {
        if ((Get-FileHash $Source).Hash -eq (Get-FileHash $Destination).Hash) { Add-Result $Phase $Item 'Present' $Destination; return }
        $null = Invoke-Change $Phase $Item "update $Destination (backup kept)" -DoneStatus 'Updated' {
            Copy-Item $Destination "$Destination.bak-$(Get-Date -Format yyyyMMddHHmmss)"
            Copy-Item $Source $Destination -Force
        }
    } else {
        $null = Invoke-Change $Phase $Item "create $Destination" {
            New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
            Copy-Item $Source $Destination
        }
    }
}

function Add-MissingToolResult([string]$Phase, [string]$Item, [string]$Tool) {
    # In a dry run the Packages phase hasn't really installed anything yet.
    if ($script:DryRun) { Add-Result $Phase $Item 'Skipped' "$Tool not installed yet (Packages phase installs it)" }
    else { Add-Result $Phase $Item 'Failed' "$Tool not found on PATH (run the Packages phase first)" }
}

function Merge-Hashtable([System.Collections.IDictionary]$Target, [System.Collections.IDictionary]$Source) {
    foreach ($key in $Source.Keys) {
        if ($Source[$key] -is [System.Collections.IDictionary] -and $Target.Contains($key) -and $Target[$key] -is [System.Collections.IDictionary]) {
            Merge-Hashtable $Target[$key] $Source[$key]
        } else {
            $Target[$key] = $Source[$key]
        }
    }
}

function Import-WorkBundle([string]$Path) {
    if (-not (Test-Path $Path)) { throw "Work bundle not found: $Path" }
    $dir = $Path
    if ((Get-Item $Path) -is [IO.FileInfo]) {
        $dir = Join-Path ([IO.Path]::GetTempPath()) "WindowsSetup-bundle-$([guid]::NewGuid().ToString('N'))"
        Expand-Archive -Path $Path -DestinationPath $dir -Force
    }
    $manifest = Get-ChildItem $dir -Recurse -Filter 'work-manifest.json' | Select-Object -First 1
    if (-not $manifest) { throw "work-manifest.json not found in $Path" }
    $script:BundleDir = $manifest.DirectoryName
    $script:Bundle = Get-Content $manifest.FullName -Raw | ConvertFrom-Json -AsHashtable
}

function Get-BundleValue([string[]]$Keys) {
    $node = $script:Bundle
    foreach ($k in $Keys) {
        if ($node -isnot [System.Collections.IDictionary] -or -not $node.Contains($k)) { return $null }
        $node = $node[$k]
    }
    $node
}

#endregion

#region Phases

function Invoke-PrereqsPhase {
    $p = 'Prereqs'
    if (-not $IsWindows) {
        Add-Result $p 'Windows' $(if ($script:DryRun) { 'Skipped' } else { 'Failed' }) 'not running on Windows (dry-run only)'
    }
    Add-Result $p 'Elevation' 'Present' $(if ($script:IsAdmin) { 'running elevated' } else { 'not elevated: machine-wide items use per-user fallbacks or are listed for IT' })

    if (-not $IsWindows) {
        Add-Result $p 'winget' 'Skipped' 'simulated (not Windows)'
    } elseif ($script:HasWinget) {
        Add-Result $p 'winget' 'Present' (winget --version)
    } else {
        Add-Result $p 'winget' 'Manual' 'winget missing: install "App Installer" from Microsoft Store / Company Portal, then re-run'
    }

    if ($IsWindows) {
        $policy = Get-ExecutionPolicy -Scope CurrentUser
        if ($policy -in 'Undefined', 'Restricted', 'AllSigned') {
            $null = Invoke-Change $p 'Execution policy' 'CurrentUser -> RemoteSigned (so the profile loads)' -DoneStatus 'Updated' {
                Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            }
        } else {
            Add-Result $p 'Execution policy' 'Present' "CurrentUser = $policy"
        }
        $effective = Get-ExecutionPolicy
        if ($effective -in 'Restricted', 'AllSigned') { Add-Result $p 'Execution policy' 'Manual' "effective policy is $effective (Group Policy?) - profile may not load" }
    }

    if (Test-Path $script:RepoRoot) { Add-Result $p 'Repo root' 'Present' $script:RepoRoot }
    else { $null = Invoke-Change $p 'Repo root' "create $($script:RepoRoot)" { New-Item -ItemType Directory -Path $script:RepoRoot -Force | Out-Null } }

    if ($script:Bundle) { Add-Result $p 'Work bundle' 'Present' $script:BundleDir }
    else { Add-Result $p 'Work bundle' 'Skipped' 'no -WorkBundle: Git identity, Repos, AI and RDP phases will skip' }
}

function Test-DotnetSdk([int]$Major) {
    $dotnet = Find-Command dotnet
    $candidates = @()
    if ($dotnet) { $candidates += $dotnet.Source }
    if ($script:Paths) {
        $userDotnet = Join-Path $script:Paths.DotnetUser 'dotnet.exe'
        if (Test-Path $userDotnet) { $candidates += $userDotnet }
    }
    foreach ($exe in $candidates) {
        if (@(& $exe --list-sdks 2>$null) -match "^$Major\.") { return $true }
    }
    $false
}

function Test-PackagePresent([hashtable]$Pkg) {
    if ($Pkg.DotnetSdk) { return Test-DotnetSdk $Pkg.DotnetSdk }
    if ($Pkg.Command -and (Find-Command $Pkg.Command)) { return $true }
    foreach ($path in @($Pkg.Paths)) {
        if ($path -and $IsWindows -and (Test-Path ([Environment]::ExpandEnvironmentVariables($path)))) { return $true }
    }
    if (-not $Pkg.Command -and -not $Pkg.Paths -and $Pkg.Winget -and $script:HasWinget) {
        $null = winget list --id $Pkg.Winget --exact --accept-source-agreements --disable-interactivity 2>&1
        return $LASTEXITCODE -eq 0
    }
    $false
}

function Install-WithWinget([hashtable]$Pkg) {
    $wingetArgs = @('install', '--id', $Pkg.Winget, '--exact', '--source', 'winget', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    if ($Pkg.Scope -eq 'user') { $wingetArgs += '--scope', 'user' }
    if ($Pkg.InstallerType) { $wingetArgs += '--installer-type', $Pkg.InstallerType }
    $output = & winget @wingetArgs 2>&1 | Out-String
    if ($LASTEXITCODE -notin $script:WingetOkCodes) {
        throw "winget exit $LASTEXITCODE`: $(($output -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 2) -join ' ')"
    }
    Update-SessionPath
}

function Install-Fallback([hashtable]$Pkg) {
    $fb = $Pkg.Fallback
    $arm = $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
    switch ($fb.Type) {
        'GitHubZip' {
            $pattern = if ($arm -and $fb.AssetPatternArm64) { $fb.AssetPatternArm64 } else { $fb.AssetPattern }
            Install-ZipToPrograms $Pkg.Name (Get-GitHubAssetUrl $fb.Repo $pattern) $Pkg.Command
        }
        'UrlZip' { Install-ZipToPrograms $Pkg.Name $fb.Url $Pkg.Command }
        'MsiExtract' { Install-MsiExtract $Pkg.Name $fb.Url $Pkg.Command }
        'DotnetInstall' {
            $installer = Save-Download 'https://dot.net/v1/dotnet-install.ps1' 'dotnet-install.ps1'
            & $installer -Channel $fb.Channel -InstallDir $script:Paths.DotnetUser -NoPath
            Remove-Item (Split-Path $installer) -Recurse -Force
            [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $script:Paths.DotnetUser, 'User')
            $env:DOTNET_ROOT = $script:Paths.DotnetUser
            Add-UserPath $script:Paths.DotnetUser
            Add-UserPath (Join-Path $HOME '.dotnet\tools')
        }
        'Fnm' {
            if (-not (Find-Command fnm)) {
                if (-not $script:HasWinget) { throw 'fnm fallback needs winget' }
                Install-WithWinget @{ Winget = 'Schniz.fnm'; Scope = 'none' }
            }
            fnm install --lts
            if ($LASTEXITCODE) { throw "fnm install --lts failed ($LASTEXITCODE)" }
            fnm default lts-latest
            fnm env --shell powershell | Out-String | Invoke-Expression
        }
        default { throw "Unknown fallback type '$($fb.Type)'" }
    }
}

function Invoke-PackagesPhase([string[]]$ExcludePackage) {
    $p = 'Packages'
    foreach ($pkg in $script:Catalog.Packages) {
        $name = $pkg.Name
        if ($ExcludePackage -contains $name) { Add-Result $p $name 'Skipped' 'excluded'; continue }
        if (Test-PackagePresent $pkg) { Add-Result $p $name 'Present'; continue }

        $canWinget = $pkg.Winget -and $script:HasWinget -and ($script:IsAdmin -or $pkg.Scope -ne 'machine')
        $how = if ($canWinget) { "winget $($pkg.Winget)" + $(if ($pkg.Scope -eq 'user') { ' (user scope)' } else { '' }) }
               elseif ($pkg.Fallback) { "$($pkg.Fallback.Type) fallback (per-user)" }
               else { $null }

        if (-not $how) {
            if ($pkg.Scope -eq 'machine' -and -not $script:IsAdmin) { Add-Result $p $name 'NeedsAdmin' "winget install --id $($pkg.Winget) -e" }
            else { Add-Result $p $name 'Failed' 'no install method (winget missing?)' }
            continue
        }
        if ($script:DryRun) { Add-Result $p $name 'WouldChange' $how; continue }

        try {
            if ($canWinget) {
                try { Install-WithWinget $pkg; Add-Result $p $name 'Installed' $how; continue }
                catch { if (-not $pkg.Fallback) { throw }; Write-Host "    winget failed ($($_.Exception.Message)); trying fallback" -ForegroundColor DarkYellow }
            }
            Install-Fallback $pkg
            Add-Result $p $name 'Installed' "$($pkg.Fallback.Type) fallback (per-user)"
        } catch {
            Add-Result $p $name 'Failed' $_.Exception.Message
        }
    }
    Send-EnvironmentChange
}

function Invoke-FontsPhase {
    $p = 'Fonts'
    foreach ($font in $script:Catalog.NerdFonts) {
        $item = "$font Nerd Font"
        $installed = @($script:Paths.UserFonts, [IO.Path]::Combine(($env:WINDIR ?? 'C:\Windows'), 'Fonts')) |
            Where-Object { Test-Path $_ } |
            ForEach-Object { Get-ChildItem $_ -Filter "$font*NerdFont*.ttf" -ErrorAction Ignore } |
            Select-Object -First 1
        if ($installed) { Add-Result $p $item 'Present'; continue }

        $null = Invoke-Change $p $item 'per-user install from ryanoasis/nerd-fonts' {
            $zip = Save-Download "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font.zip" "$font.zip"
            $extract = Join-Path (Split-Path $zip) 'x'
            Expand-Archive $zip $extract -Force
            New-Item -ItemType Directory -Path $script:Paths.UserFonts -Force | Out-Null
            $reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
            if (-not (Test-Path $reg)) { New-Item $reg -Force | Out-Null }
            foreach ($ttf in Get-ChildItem $extract -Recurse -Filter '*.ttf') {
                $target = Join-Path $script:Paths.UserFonts $ttf.Name
                Copy-Item $ttf.FullName $target -Force
                Set-ItemProperty -Path $reg -Name "$($ttf.BaseName) (TrueType)" -Value $target
            }
            Remove-Item (Split-Path $zip) -Recurse -Force
        }
    }
}

function Invoke-ShellPhase {
    $p = 'Shell'
    foreach ($module in $script:Catalog.PSModules) {
        if (Get-Module -ListAvailable $module) { Add-Result $p "module $module" 'Present'; continue }
        $null = Invoke-Change $p "module $module" 'Install-Module -Scope CurrentUser' {
            Install-Module $module -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -Confirm:$false
        }
    }

    $profilePath = if ($IsWindows) { $PROFILE.CurrentUserCurrentHost } else { Join-Path $script:Paths.Documents 'PowerShell/Microsoft.PowerShell_profile.ps1' }
    Copy-ManagedFile $p 'pwsh profile' (Join-Path $script:Root 'config/Microsoft.PowerShell_profile.ps1') $profilePath

    $starshipHome = if ($IsWindows) { Join-Path $HOME '.config\starship.toml' } else { Join-Path $script:Paths.LocalAppData '../home/.config/starship.toml' }
    Copy-ManagedFile $p 'starship.toml' (Join-Path $script:Root '../Starship/starship.toml') $starshipHome
}

function Invoke-TerminalPhase {
    $p = 'Terminal'
    $settingsPath = $script:Paths.WtSettings
    if (-not (Test-Path $settingsPath)) {
        Add-Result $p 'Windows Terminal settings' 'Manual' 'open Windows Terminal once (creates settings.json), then re-run -Only Terminal'
        return
    }
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
    $before = $settings | ConvertTo-Json -Depth 32

    if ($settings.profiles -is [System.Collections.IList]) {
        $settings.profiles = [ordered]@{ defaults = [ordered]@{}; list = $settings.profiles }
    }
    if (-not $settings.profiles.Contains('defaults')) { $settings.profiles.defaults = [ordered]@{} }

    $desired = Get-Content (Join-Path $script:Root 'config/windows-terminal.json') -Raw | ConvertFrom-Json -AsHashtable
    Merge-Hashtable $settings $desired

    # Default profile: the auto-detected PowerShell 7 profile, or a custom one for a per-user (zip) pwsh.
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($settings.profiles.list)) { $list.Add($entry) }
    $pwshProfile = $list | Where-Object { $_['source'] -eq 'Windows.Terminal.PowershellCore' -and -not $_['hidden'] } | Select-Object -First 1
    if (-not $pwshProfile) {
        $customGuid = '{7c1e3d55-6a2b-4d3e-9b1f-0d4e5a1c2b3d}'
        $pwshProfile = $list | Where-Object { $_['guid'] -eq $customGuid } | Select-Object -First 1
        $pwsh = Find-Command pwsh
        if (-not $pwshProfile -and $pwsh) {
            $pwshProfile = [ordered]@{ guid = $customGuid; name = 'PowerShell 7'; commandline = "`"$($pwsh.Source)`" -NoLogo"; startingDirectory = '%USERPROFILE%' }
            $list.Add($pwshProfile)
        }
    }
    $settings.profiles.list = $list.ToArray()
    if ($pwshProfile) { $settings.defaultProfile = $pwshProfile['guid'] }
    else { Add-Result $p 'Default profile' 'Manual' 'PowerShell 7 not found; set the default profile by hand' }

    $after = $settings | ConvertTo-Json -Depth 32
    if ($after -eq $before) { Add-Result $p 'Windows Terminal settings' 'Present'; return }
    $null = Invoke-Change $p 'Windows Terminal settings' 'pwsh default, Nerd Font, opacity/acrylic, padding, copy-on-select (backup kept)' -DoneStatus 'Updated' {
        Copy-Item $settingsPath "$settingsPath.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        Set-Content -Path $settingsPath -Value $after -Encoding utf8NoBOM
    }
}

function Set-GitGlobal {
    param([string]$Phase, [string]$Key, [string]$Value)
    $current = git config --global --get $Key 2>$null
    if ($current -eq $Value) { Add-Result $Phase $Key 'Present' $Value; return }
    $null = Invoke-Change $Phase $Key $Value -DoneStatus 'Updated' {
        git config --global $Key $Value
        if ($LASTEXITCODE) { throw "git config failed ($LASTEXITCODE)" }
    }
}

function Invoke-GitPhase {
    $p = 'Git'
    if (-not (Find-Command git)) { Add-MissingToolResult $p 'git config' 'git'; return }

    foreach ($key in ($script:Catalog.GitConfig.Keys | Sort-Object)) { Set-GitGlobal $p $key $script:Catalog.GitConfig[$key] }

    $helpers = @(git config --get-all credential.helper 2>$null)
    if ($helpers -match 'manager') { Add-Result $p 'credential.helper' 'Present' ($helpers -join ', ') }
    else { Set-GitGlobal $p 'credential.helper' 'manager' }

    if (-not $script:Bundle) { Add-Result $p 'identity / work config' 'Skipped' 'no work bundle'; return }

    $name = Get-BundleValue 'git', 'name'
    $email = Get-BundleValue 'git', 'email'
    if ($name) { Set-GitGlobal $p 'user.name' $name }
    if ($email) { Set-GitGlobal $p 'user.email' $email }

    foreach ($entry in @(Get-BundleValue 'git', 'config')) {
        if ($entry) { Set-GitGlobal $p $entry.key $entry.value }
    }

    $work = Get-BundleValue 'git', 'workInclude'
    if ($work -and $work.file -and $work.email) {
        $includeFile = Join-Path $HOME $work.file
        $wanted = "# Work identity, applied by includeIf in ~/.gitconfig for the work repo folders.`n[user]`n`temail = $($work.email)`n"
        $existing = if (Test-Path $includeFile) { (Get-Content $includeFile -Raw) -replace "`r`n", "`n" } else { $null }
        if ($existing -eq $wanted) { Add-Result $p "~/$($work.file)" 'Present' }
        else { $null = Invoke-Change $p "~/$($work.file)" "work email for $(@($work.groups) -join ', ')" { Set-Content -Path $includeFile -Value $wanted -NoNewline -Encoding utf8NoBOM } }

        # Absolute path: pwsh expands a leading ~ in native-command arguments, which would never compare equal.
        $includeValue = $includeFile -replace '\\', '/'
        $root = $script:RepoRoot.TrimEnd('\', '/') -replace '\\', '/'
        foreach ($group in @($work.groups)) {
            Set-GitGlobal $p "includeIf.gitdir/i:$root/$group/.path" $includeValue
        }
    }

    $lfs = git config --global --get filter.lfs.process 2>$null
    if ($lfs) { Add-Result $p 'git lfs' 'Present' }
    else { $null = Invoke-Change $p 'git lfs' 'git lfs install' { git lfs install | Out-Null; if ($LASTEXITCODE) { throw "git lfs install failed ($LASTEXITCODE)" } } }
}

function Invoke-DevToolsPhase {
    $p = 'DevTools'

    if (Find-Command dotnet) {
        $installedTools = @(dotnet tool list -g 2>$null | Select-Object -Skip 2 | ForEach-Object { ($_ -split '\s+')[0].ToLowerInvariant() })
        foreach ($tool in $script:Catalog.DotnetTools) {
            if ($installedTools -contains $tool.ToLowerInvariant()) { Add-Result $p "dotnet tool $tool" 'Present'; continue }
            $null = Invoke-Change $p "dotnet tool $tool" 'dotnet tool install -g' {
                dotnet tool install -g $tool | Out-Null
                if ($LASTEXITCODE) { throw "dotnet tool install failed ($LASTEXITCODE)" }
            }
        }
    } else { Add-Result $p 'dotnet tools' 'Skipped' 'dotnet not found' }

    if (Find-Command npm) {
        $globals = @()
        try { $globals = @((npm ls -g --depth=0 --json 2>$null | ConvertFrom-Json -AsHashtable).dependencies.Keys) } catch { $globals = @() }
        foreach ($pkg in $script:Catalog.NpmGlobals) {
            if ($globals -contains $pkg) { Add-Result $p "npm $pkg" 'Present'; continue }
            $null = Invoke-Change $p "npm $pkg" 'npm install -g' {
                npm install -g $pkg | Out-Null
                if ($LASTEXITCODE) { throw "npm install failed ($LASTEXITCODE)" }
            }
        }
    } else { Add-Result $p 'npm globals' 'Skipped' 'npm not found' }

    $python = Find-Command python
    if ($python) {
        foreach ($pkg in $script:Catalog.PipPackages) {
            $null = & $python.Source -m pip show $pkg 2>$null
            if ($LASTEXITCODE -eq 0) { Add-Result $p "pip $pkg" 'Present'; continue }
            $null = Invoke-Change $p "pip $pkg" 'python -m pip install' {
                & $python.Source -m pip install --quiet $pkg
                if ($LASTEXITCODE) { throw "pip install failed ($LASTEXITCODE)" }
                if ($IsWindows) { Add-UserPath (& $python.Source -c 'import sysconfig; print(sysconfig.get_path("scripts"))') }
            }
        }
    } else { Add-Result $p 'pip packages' 'Skipped' 'python not found' }
}

function Invoke-VSCodePhase {
    $p = 'VSCode'
    if (-not (Find-Command code)) { Add-MissingToolResult $p 'extensions' 'VS Code (code)'; return }
    $installed = @(code --list-extensions 2>$null | ForEach-Object { $_.ToLowerInvariant() })
    $wanted = Get-Content (Join-Path $script:Root 'config/vscode-extensions.txt') |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
    foreach ($ext in $wanted) {
        if ($installed -contains $ext.ToLowerInvariant()) { Add-Result $p $ext 'Present'; continue }
        $null = Invoke-Change $p $ext 'code --install-extension' {
            code --install-extension $ext | Out-Null
            if ($LASTEXITCODE) { throw "install failed ($LASTEXITCODE)" }
        }
    }
    Add-Result $p 'Settings Sync' 'Manual' 'sign in to Settings Sync (Accounts menu) and choose Merge to bring settings, keybindings, prompts and MCP servers'
}

function Invoke-ReposPhase {
    $p = 'Repos'
    if (-not $script:Bundle) { Add-Result $p 'repos' 'Skipped' 'no work bundle'; return }
    if (-not (Find-Command git)) { Add-MissingToolResult $p 'repos' 'git'; return }
    foreach ($repo in @(Get-BundleValue 'repos')) {
        $target = [IO.Path]::Combine($script:RepoRoot, ($repo.path -replace '/', [IO.Path]::DirectorySeparatorChar))
        if (Test-Path ([IO.Path]::Combine($target, '.git'))) { Add-Result $p $repo.path 'Present'; continue }
        if ((Test-Path $target) -and (Get-ChildItem $target -Force | Select-Object -First 1)) { Add-Result $p $repo.path 'Failed' "$target exists and is not empty"; continue }
        $null = Invoke-Change $p $repo.path "git clone $($repo.url)" {
            New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
            git clone $repo.url $target
            if ($LASTEXITCODE) { throw "git clone failed ($LASTEXITCODE)" }
        }
    }
}

function Invoke-AIPhase {
    $p = 'AI'
    if (-not $script:Bundle) { Add-Result $p 'AI config' 'Skipped' 'no work bundle'; return }
    $copilotHome = Join-Path $HOME '.copilot'

    $instructions = Join-Path $script:BundleDir 'ai/copilot/instructions'
    if (Test-Path $instructions) {
        foreach ($file in Get-ChildItem $instructions -File) {
            Copy-ManagedFile $p "copilot instructions/$($file.Name)" $file.FullName (Join-Path $copilotHome "instructions/$($file.Name)")
        }
    }

    $mcp = Join-Path $script:BundleDir 'ai/copilot/mcp-config.json'
    $mcpTarget = Join-Path $copilotHome 'mcp-config.json'
    if (Test-Path $mcp) {
        if (Test-Path $mcpTarget) { Add-Result $p 'copilot mcp-config.json' 'Present' 'kept existing file' }
        else { Copy-ManagedFile $p 'copilot mcp-config.json' $mcp $mcpTarget }
    }

    $skills = Join-Path $script:BundleDir 'ai/claude/skills'
    if (Test-Path $skills) {
        foreach ($file in Get-ChildItem $skills -Recurse -File) {
            $relative = [IO.Path]::GetRelativePath($skills, $file.FullName)
            Copy-ManagedFile $p "claude skills/$($relative -replace '\\', '/')" $file.FullName (Join-Path $HOME ".claude/skills/$relative")
        }
    }
}

function Invoke-RdpPhase {
    $p = 'RDP'
    if (-not $script:Bundle) { Add-Result $p 'RDP connections' 'Skipped' 'no work bundle'; return }
    $source = Join-Path $script:BundleDir 'rdp'
    if (-not (Test-Path $source)) { Add-Result $p 'RDP connections' 'Skipped' 'bundle has no rdp folder'; return }
    $target = Join-Path $script:Paths.Documents 'RDP'
    foreach ($file in Get-ChildItem $source -Recurse -Filter '*.rdp') {
        $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
        Copy-ManagedFile $p ($relative -replace '\\', '/') $file.FullName (Join-Path $target $relative)
    }
    Add-Result $p 'RDP folder' 'Manual' "open connections from $target (mstsc); passwords were not exported, tick 'Remember me' on first connect"
}

function Invoke-SystemPhase {
    $p = 'System'
    if (-not $IsWindows) { Add-Result $p 'system settings' 'Skipped' 'not Windows'; return }

    $fs = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    if ((Get-ItemProperty $fs -Name LongPathsEnabled -ErrorAction Ignore).LongPathsEnabled -eq 1) { Add-Result $p 'Long paths' 'Present' }
    elseif (-not $script:IsAdmin) { Add-Result $p 'Long paths' 'NeedsAdmin' 'HKLM LongPathsEnabled = 1' }
    else { $null = Invoke-Change $p 'Long paths' 'HKLM LongPathsEnabled = 1' -DoneStatus 'Updated' { Set-ItemProperty $fs -Name LongPathsEnabled -Value 1 -Type DWord } }

    $env:WSL_UTF8 = '1'
    $distros = @(wsl.exe --list --quiet 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($distros -contains 'Ubuntu') {
        Add-Result $p 'WSL Ubuntu' 'Present'
        $done = wsl.exe -d Ubuntu -- bash -c 'test -f ~/.local/state/dan-tools-wsl-setup.done && echo yes' 2>$null
        if ($done -eq 'yes') { Add-Result $p 'WSL shell setup' 'Present' }
        else {
            $toWsl = { param($path) $full = (Resolve-Path $path).Path; '/mnt/' + $full.Substring(0, 1).ToLowerInvariant() + ($full.Substring(2) -replace '\\', '/') }
            $setupScript = & $toWsl (Join-Path $script:Root 'config/wsl-setup.sh')
            $toml = & $toWsl (Join-Path $script:Root '../Starship/starship.toml')
            $null = Invoke-Change $p 'WSL shell setup' 'apt tools + starship/zoxide/eza/fzf (asks for your Linux sudo password)' {
                wsl.exe -d Ubuntu -- bash $setupScript $toml
                if ($LASTEXITCODE) { throw "wsl-setup.sh failed ($LASTEXITCODE)" }
            }
        }
    } elseif (-not $script:IsAdmin) {
        Add-Result $p 'WSL Ubuntu' 'NeedsAdmin' 'wsl --install -d Ubuntu --no-launch (reboot after)'
    } else {
        $null = Invoke-Change $p 'WSL Ubuntu' 'wsl --install -d Ubuntu --no-launch' {
            wsl.exe --install -d Ubuntu --no-launch
            if ($LASTEXITCODE) { throw "wsl --install failed ($LASTEXITCODE)" }
        }
        Add-Result $p 'WSL first run' 'Manual' 'reboot, open "Ubuntu" from Start to create your Linux user, then re-run -Only System'
    }

    if ((Find-Command docker) -or (Test-Path "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe")) {
        $inGroup = (net localgroup docker-users 2>$null) -match [regex]::Escape($env:USERNAME)
        if (-not $inGroup) { Add-Result $p 'docker-users group' 'Manual' "if Docker says access denied: net localgroup docker-users $env:USERDOMAIN\$env:USERNAME /add (admin), then sign out/in" }
    }
}

#endregion

function Show-Report {
    $results = $script:Results
    Write-Host ''
    Write-Host '==== Summary ====' -ForegroundColor White
    $results | Group-Object Status | Sort-Object Name | ForEach-Object { Write-Host ('  {0,-11} {1}' -f $_.Name, $_.Count) }

    $failed = @($results | Where-Object Status -eq 'Failed')
    if ($failed) {
        Write-Host "`nFailed:" -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  - [$($_.Phase)] $($_.Item): $($_.Detail)" }
    }

    $admin = @($results | Where-Object Status -eq 'NeedsAdmin')
    if ($admin) {
        Write-Host "`nNeeds admin (send to IT, or elevate with Admin By Request):" -ForegroundColor Yellow
        $admin | ForEach-Object { Write-Host "  - $($_.Item): $($_.Detail)" }
        Write-Host '  Then, from an elevated pwsh running as YOU:' -ForegroundColor Yellow
        Write-Host "    & '$(Join-Path $script:Root 'bootstrap.ps1')' -Only Packages,System" -ForegroundColor Yellow
    }

    $manual = @($results | Where-Object Status -eq 'Manual')
    if ($manual) {
        Write-Host "`nManual steps:" -ForegroundColor Yellow
        $manual | ForEach-Object { Write-Host "  - $($_.Item): $($_.Detail)" }
    }

    $reportPath = Join-Path $script:Paths.State "last-run$(if ($script:DryRun) { '-dryrun' }).json"
    New-Item -ItemType Directory -Path $script:Paths.State -Force | Out-Null
    $results | ConvertTo-Json -Depth 4 | Set-Content $reportPath -Encoding utf8NoBOM
    Write-Host "`nReport: $reportPath"
}

function Invoke-WindowsSetup {
    [CmdletBinding()]
    param(
        [string[]]$Only,
        [string[]]$Skip,
        [string]$WorkBundle,
        [string]$RepoRoot = 'C:\Git',
        [string[]]$ExcludePackage,
        [switch]$DryRun
    )
    $Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $Skip = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $ExcludePackage = @($ExcludePackage | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($name in @($Only) + @($Skip)) {
        if ($name -notin $script:Phases) { throw "Unknown phase '$name'. Valid: $($script:Phases -join ', ')" }
    }

    $script:Results.Clear()
    $script:DryRun = [bool]$DryRun
    $script:IsAdmin = Test-Admin
    # Dry runs off Windows simulate winget so the preview shows what would be installed.
    $script:HasWinget = [bool](Find-Command winget) -or (-not $IsWindows -and $script:DryRun)
    $script:RepoRoot = $RepoRoot
    $script:Paths = Get-SetupPaths
    $script:Catalog = Import-PowerShellDataFile (Join-Path $script:Root 'packages.psd1')
    $script:Bundle = $null
    $script:BundleDir = $null
    if ($WorkBundle) { Import-WorkBundle $WorkBundle }

    New-Item -ItemType Directory -Path (Join-Path $script:Paths.State 'logs') -Force | Out-Null
    $log = Join-Path $script:Paths.State "logs/setup-$(Get-Date -Format yyyyMMdd-HHmmss).log"
    Start-Transcript -Path $log -UseMinimalHeader | Out-Null
    try {
        if ($script:DryRun) { Write-Host 'DRY RUN: nothing will be changed.' -ForegroundColor Cyan }
        $selected = if ($Only) { $script:Phases | Where-Object { $_ -in $Only } } else { $script:Phases }
        foreach ($phase in $selected) {
            if ($phase -in $Skip) { continue }
            Write-Host "`n== $phase ==" -ForegroundColor White
            try {
                switch ($phase) {
                    'Prereqs'  { Invoke-PrereqsPhase }
                    'Packages' { Invoke-PackagesPhase -ExcludePackage $ExcludePackage }
                    'Fonts'    { Invoke-FontsPhase }
                    'Shell'    { Invoke-ShellPhase }
                    'Terminal' { Invoke-TerminalPhase }
                    'Git'      { Invoke-GitPhase }
                    'DevTools' { Invoke-DevToolsPhase }
                    'VSCode'   { Invoke-VSCodePhase }
                    'Repos'    { Invoke-ReposPhase }
                    'AI'       { Invoke-AIPhase }
                    'RDP'      { Invoke-RdpPhase }
                    'System'   { Invoke-SystemPhase }
                }
            } catch {
                Add-Result $phase 'phase' 'Failed' $_.Exception.Message
            }
        }
        Show-Report
    } finally {
        Stop-Transcript | Out-Null
        Write-Host "Log: $log"
    }
}

Export-ModuleMember -Function Invoke-WindowsSetup
