@{
    # Scope:
    #   user    - winget has a per-user installer (passes --scope user, no admin needed)
    #   none    - zip/portable/msix package, installs without admin (no --scope flag)
    #   machine - winget only has a machine-wide installer; when not elevated it raises a UAC / Admin By Request prompt
    # Detection: Command (on PATH), DotnetSdk (major version), Paths, otherwise `winget list --id`.
    # Fallback: used only when there is no Winget ID, or with bootstrap.ps1 -UseFallbacks after winget fails.
    # Fallback types: GitHubZip (Repo + AssetPattern[/AssetPatternArm64]), UrlZip (Url), MsiExtract (Url), DotnetInstall (Channel), Fnm.
    Packages = @(
        # Core
        @{ Name = 'PowerShell 7'; Winget = 'Microsoft.PowerShell'; Scope = 'machine'; Command = 'pwsh'
           Fallback = @{ Type = 'GitHubZip'; Repo = 'PowerShell/PowerShell'; AssetPattern = '^PowerShell-[\d.]+-win-x64\.zip$'; AssetPatternArm64 = '^PowerShell-[\d.]+-win-arm64\.zip$' } }
        @{ Name = 'Git'; Winget = 'Git.Git'; Scope = 'user'; Command = 'git' }
        @{ Name = 'GitHub CLI'; Winget = 'GitHub.cli'; Scope = 'none'; InstallerType = 'zip'; Command = 'gh'
           Fallback = @{ Type = 'GitHubZip'; Repo = 'cli/cli'; AssetPattern = '^gh_[\d.]+_windows_amd64\.zip$'; AssetPatternArm64 = '^gh_[\d.]+_windows_arm64\.zip$' } }
        @{ Name = 'GitHub Copilot CLI'; Winget = 'GitHub.Copilot'; Scope = 'none'; Command = 'copilot' }
        @{ Name = 'Visual Studio Code'; Winget = 'Microsoft.VisualStudioCode'; Scope = 'user'; Command = 'code' }
        @{ Name = 'Windows Terminal'; Winget = 'Microsoft.WindowsTerminal'; Scope = 'none'; Command = 'wt' }

        # Shell
        @{ Name = 'Starship'; Winget = 'Starship.Starship'; Scope = 'machine'; Command = 'starship'
           Fallback = @{ Type = 'GitHubZip'; Repo = 'starship/starship'; AssetPattern = '^starship-x86_64-pc-windows-msvc\.zip$'; AssetPatternArm64 = '^starship-aarch64-pc-windows-msvc\.zip$' } }
        @{ Name = 'zoxide'; Winget = 'ajeetdsouza.zoxide'; Scope = 'none'; Command = 'zoxide' }
        @{ Name = 'eza'; Winget = 'eza-community.eza'; Scope = 'none'; Command = 'eza' }
        @{ Name = 'fzf'; Winget = 'junegunn.fzf'; Scope = 'none'; InstallerType = 'zip'; Command = 'fzf' }
        @{ Name = 'jq'; Winget = 'jqlang.jq'; Scope = 'none'; Command = 'jq' }

        # Runtimes
        @{ Name = '.NET SDK 8'; Winget = 'Microsoft.DotNet.SDK.8'; Scope = 'machine'; DotnetSdk = 8
           Fallback = @{ Type = 'DotnetInstall'; Channel = '8.0' } }
        @{ Name = '.NET SDK 10'; Winget = 'Microsoft.DotNet.SDK.10'; Scope = 'machine'; DotnetSdk = 10
           Fallback = @{ Type = 'DotnetInstall'; Channel = '10.0' } }
        @{ Name = 'Node.js LTS'; Winget = 'OpenJS.NodeJS.LTS'; Scope = 'machine'; Command = 'node'
           Fallback = @{ Type = 'Fnm' } }
        @{ Name = 'Python 3.12'; Winget = 'Python.Python.3.12'; Scope = 'user'; Command = 'python' }

        # Cloud / data CLIs
        @{ Name = 'Azure CLI'; Winget = 'Microsoft.AzureCLI'; Scope = 'machine'; Command = 'az'
           Fallback = @{ Type = 'UrlZip'; Url = 'https://aka.ms/installazurecliwindowszipx64' } }
        @{ Name = 'AWS CLI'; Winget = 'Amazon.AWSCLI'; Scope = 'machine'; Command = 'aws'
           Fallback = @{ Type = 'MsiExtract'; Url = 'https://awscli.amazonaws.com/AWSCLIV2.msi' } }
        @{ Name = 'Azure Functions Core Tools'; Winget = 'Microsoft.Azure.FunctionsCoreTools'; Scope = 'none'; InstallerType = 'zip'; Command = 'func' }
        @{ Name = 'Terraform'; Winget = 'Hashicorp.Terraform'; Scope = 'none'; Command = 'terraform' }
        @{ Name = 'Atlassian CLI'; Winget = 'Atlassian.AtlassianCLI'; Scope = 'none'; Command = 'acli' }
        @{ Name = 'Auth0 CLI'; Command = 'auth0'
           Fallback = @{ Type = 'GitHubZip'; Repo = 'auth0/auth0-cli'; AssetPattern = '^auth0-cli_[\d.]+_Windows_x86_64\.zip$'; AssetPatternArm64 = '^auth0-cli_[\d.]+_Windows_arm64\.zip$' } }
        @{ Name = 'sqlcmd (go)'; Winget = 'Microsoft.Sqlcmd'; Scope = 'machine'; Command = 'sqlcmd'
           Fallback = @{ Type = 'GitHubZip'; Repo = 'microsoft/go-sqlcmd'; AssetPattern = '^sqlcmd-windows-amd64\.zip$'; AssetPatternArm64 = '^sqlcmd-windows-arm64\.zip$' } }
        @{ Name = 'actionlint'; Winget = 'rhysd.actionlint'; Scope = 'none'; Command = 'actionlint' }

        # Apps
        @{ Name = 'Beyond Compare 5'; Winget = 'ScooterSoftware.BeyondCompare.5'; Scope = 'user'
           Paths = @('%LOCALAPPDATA%\Programs\Beyond Compare 5\BCompare.exe', '%ProgramFiles%\Beyond Compare 5\BCompare.exe') }
        @{ Name = '7-Zip'; Winget = '7zip.7zip'; Scope = 'machine'; Paths = @('%ProgramFiles%\7-Zip\7z.exe') }
        @{ Name = 'Docker Desktop'; Winget = 'Docker.DockerDesktop'; Scope = 'machine'; Command = 'docker'
           Paths = @('%ProgramFiles%\Docker\Docker\Docker Desktop.exe') }
    )

    # Installed per-user by the Fonts phase from the Nerd Fonts GitHub release.
    NerdFonts = @('JetBrainsMono', 'Hack')

    # Installed with Install-Module -Scope CurrentUser by the Shell phase.
    PSModules = @('PSFzf', 'Microsoft.PowerShell.ConsoleGuiTools', 'SqlServer')

    DotnetTools = @(
        'aspire.cli'
        'dotnet-ef'
        'dotnet-stack'
        'ilspycmd'
        'Microsoft.Artifacts.CredentialProvider.NuGet.Tool'
    )

    NpmGlobals = @('@azure/static-web-apps-cli', 'azurite')

    PipPackages = @('git-filter-repo')

    # Global git settings applied by the Git phase (identity and work settings come from the work bundle).
    GitConfig = @{
        'core.editor'        = 'code --wait'
        'core.autocrlf'      = 'true'
        'core.longpaths'     = 'true'
        'init.defaultBranch' = 'main'
    }
}
