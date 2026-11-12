# Windows port of the macOS pwsh profile.
# Managed by Dan-Tools/WindowsSetup (config/Microsoft.PowerShell_profile.ps1).
# Re-run `bootstrap.ps1 -Only Shell` to update; local edits are backed up, then overwritten.

# VS Code integrated terminal (this is where the Copilot agent runs commands).
$InVSCode = $env:TERM_PROGRAM -eq 'vscode'

function Test-ProfileCommand([string]$Name) { [bool](Get-Command $Name -CommandType Application -ErrorAction Ignore) }

# Node via fnm when Node.js wasn't installed machine-wide.
if (Test-ProfileCommand fnm) { fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression }

if (Test-ProfileCommand starship) { Invoke-Expression (&starship init powershell) }

if (Test-ProfileCommand zoxide) { Invoke-Expression (& { (zoxide init powershell | Out-String) }) }

if (Get-Module -ListAvailable PSFzf) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t'
    Set-PsFzfOption -PSReadlineChordReverseHistory 'Ctrl+r'
}

# Safe echo override
# Prevents the recurring hang where a bare `echo` (alias for Write-Output) with no
# input blocks on the mandatory `InputObject` parameter prompt.
if (Test-Path Alias:echo) { Remove-Item Alias:echo -Force -ErrorAction SilentlyContinue }
function echo {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]] $Text)
    $piped = @($input)
    if ($piped.Count)               { $piped }
    elseif ($Text -and $Text.Count) { $Text }
    else                            { '' }
}

# ls/ll/tree via eza. On Windows `ls` is a built-in alias, which would win over a function.
if (Test-ProfileCommand eza) {
    if (Test-Path Alias:ls) { Remove-Item Alias:ls -Force }
    # Drop icons + color inside VS Code so listings stay plain text.
    if ($InVSCode) {
        function ll   { eza -lah --git --color=never @args }
        function ls   { eza --color=never @args }
        function tree { eza --tree --color=never @args }
    } else {
        function ll   { eza -lah --icons=auto --git @args }
        function ls   { eza --icons=auto @args }
        function tree { eza --tree --icons=auto @args }
    }
}

# macOS-style `caffeinate`: keeps the machine and display awake until Ctrl+C,
# or for N seconds with `caffeinate -t N`. Other macOS flags are accepted and ignored.
function caffeinate {
    $i = [array]::IndexOf($args, '-t')
    $seconds = if ($i -ge 0 -and $i + 1 -lt $args.Count) { [int]$args[$i + 1] } else { 0 }
    if (-not ('DanTools.Power' -as [type])) {
        Add-Type -Namespace DanTools -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
    }
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED
    [void][DanTools.Power]::SetThreadExecutionState(0x80000003)
    try {
        if ($seconds -gt 0) { Write-Host "Keeping awake for $seconds s (Ctrl+C to stop)"; Start-Sleep -Seconds $seconds }
        else { Write-Host 'Keeping awake (Ctrl+C to stop)'; while ($true) { Start-Sleep -Seconds 60 } }
    } finally {
        [void][DanTools.Power]::SetThreadExecutionState(0x80000000)
    }
}

function Remove-GitBranches {
    if ((git rev-parse --is-inside-work-tree 2>$null) -ne 'true') {
        Write-Error 'Not inside a git repository.'
        return
    }

    if (-not (Get-Command Out-ConsoleGridView -ErrorAction SilentlyContinue)) {
        Write-Error "Out-ConsoleGridView not found. Install with: Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser"
        return
    }

    $current = git branch --show-current

    $branches = git for-each-ref --format='%(refname:short)' refs/heads |
        ForEach-Object {
            [PSCustomObject]@{
                Branch  = $_
                Current = if ($_ -eq $current) { '*' } else { '' }
            }
        }

    if (-not $branches) {
        Write-Warning 'No local branches found.'
        return
    }

    $selected = $branches | Out-ConsoleGridView -Title 'Select branches to DELETE (force)' -OutputMode Multiple
    if (-not $selected) {
        Write-Host 'No branches selected.'
        return
    }

    foreach ($item in $selected) {
        if ($item.Branch -eq $current) {
            Write-Warning "Skipping '$($item.Branch)': cannot delete the current branch."
            continue
        }
        git branch -D $item.Branch
    }
}
