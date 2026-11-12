# WindowsSetup

Sets up a Windows work laptop to match the macOS setup: CLI tools, pwsh 7 + starship, Windows Terminal,
git, .NET/Node/Python tooling, VS Code, work repos, Copilot/Claude config and RDP connections.

It is idempotent: every phase checks before it changes anything, so re-run it whenever you like.
Installs go through **winget** wherever a package exists. Without admin, machine-wide packages and
system settings each raise a UAC / Admin By Request prompt. Anything you decline is listed at the end.

## Two parts

| Part | Where | Contains |
|---|---|---|
| Tool | this folder (public) | scripts, package catalog, shell/terminal config, `../Starship/starship.toml` |
| Work bundle | `WindowsSetup-WorkBundle.zip` (private, never committed) | repo list + URLs, git identity and work email, Azure DevOps credential settings, Copilot instructions, Claude skills, `.rdp` files |

## 1. On the Mac: export the work bundle

```powershell
pwsh ./Export-WorkBundle.ps1 -Groups GroupA,GroupB    # folder names under ~/Git
```

- Writes `~/Desktop/WindowsSetup-WorkBundle/` and `~/Desktop/WindowsSetup-WorkBundle.zip`.
- Without `-Groups` it exports every folder your git `includeIf "gitdir:..."` rules cover.
- Linked worktrees are skipped, and SSH remotes are rewritten to HTTPS so Git Credential Manager handles auth.
- The Copilot instruction `sqlp.instructions.md` is left out because `sqlp` is macOS-only. Change this with `-ExcludeInstruction`.
- Saved PCs from **Windows App** become clean `.rdp` files (address, username, gateway, folder), plus `rdp/connections.csv`, a plain list of every address. Passwords stay in the macOS Keychain.

Move the zip over a **work** channel (work OneDrive, Teams to yourself). It contains internal hostnames and emails.

## 2. On Windows: get the tool

From Windows PowerShell (no git needed):

```powershell
irm https://raw.githubusercontent.com/djflan/Dan-Tools/main/WindowsSetup/get.ps1 | iex
```

That downloads this repo to `%LOCALAPPDATA%\WindowsSetup\Dan-Tools`. Alternatively, download the repo zip from GitHub and extract it.

## 3. Preview, then run

```powershell
$setup = "$env:LOCALAPPDATA\WindowsSetup\Dan-Tools\WindowsSetup\bootstrap.ps1"
$bundle = "$HOME\Downloads\WindowsSetup-WorkBundle.zip"

powershell -ExecutionPolicy Bypass -File $setup -WorkBundle $bundle -WhatIf   # dry run
powershell -ExecutionPolicy Bypass -File $setup -WorkBundle $bundle           # for real
```

- Run it **not elevated**, so per-user settings land in your profile. Approve the UAC / Admin By Request prompts as they come up: pwsh, .NET 8, Node, Azure CLI, AWS CLI, starship, sqlcmd, 7-Zip, Docker, long paths and WSL.
- If PowerShell 7 is missing, it installs it first with winget, then relaunches itself in pwsh.
- The first clones open a browser sign-in (GitHub, then Azure DevOps) through Git Credential Manager.
- It ends with a summary: **Needs admin** (prompts declined or failed) and **Manual steps**.
- The log and a JSON report are saved under `%LOCALAPPDATA%\WindowsSetup`.

To retry what needs admin, re-run and approve the prompts, or run from an elevated pwsh running **as you** (not a separate admin account):

```powershell
& $setup -Only Packages,System
```

If elevation isn't possible at all, `-UseFallbacks` installs those tools per-user instead of through winget.

### Options

| Parameter | Use |
|---|---|
| `-Only` / `-Skip` | Phases, comma-separated: `Prereqs, Packages, Fonts, Shell, Terminal, Git, DevTools, VSCode, Repos, AI, RDP, System` |
| `-WorkBundle` | Bundle zip or folder. Without it, the Git identity, Repos, AI and RDP phases are skipped. |
| `-RepoRoot` | Default `C:\Git`. Repos go to `<RepoRoot>\<Group>\<Repo>`. |
| `-ExcludePackage` | Package names from `packages.psd1`, e.g. `'Docker Desktop'` |
| `-UseFallbacks` | When winget fails or is missing, install per-user instead: GitHub zip, `dotnet-install.ps1`, fnm for Node, Azure CLI zip, AWS CLI `msiexec /a` |
| `-WhatIf` | Dry run. It also works on macOS for testing (Windows paths go to a temp folder). |

## What each phase does

| Phase | Details |
|---|---|
| Prereqs | Checks winget and elevation, sets execution policy `RemoteSigned` (CurrentUser), creates `C:\Git` |
| Packages | Installs everything in `packages.psd1` with winget (user scope where available; machine-wide ones raise a UAC prompt when not elevated). Only Auth0 CLI isn't in winget, so it comes from its GitHub release. |
| Fonts | JetBrainsMono and Hack Nerd Fonts, installed per-user from the Nerd Fonts release. winget's JetBrainsMono package needs admin and is behind upstream, and Hack isn't in winget. |
| Shell | Modules PSFzf, ConsoleGuiTools and SqlServer. Installs the pwsh profile (`config/Microsoft.PowerShell_profile.ps1`) and `~/.config/starship.toml`. Existing files are backed up. |
| Terminal | Windows Terminal: pwsh 7 as the default profile, JetBrainsMono Nerd Font Mono 14, 85% opacity + acrylic, padding 12, copy-on-select (the Ghostty look). Open Terminal once first so `settings.json` exists. |
| Git | `core.editor`, `autocrlf=true`, `longpaths`, `init.defaultBranch`, GCM, identity, the work identity through `includeIf "gitdir/i:C:/Git/<Group>/"`, Azure DevOps credential settings, git-lfs |
| DevTools | .NET global tools (aspire, dotnet-ef, dotnet-stack, ilspycmd, Azure Artifacts credential provider), npm globals (swa, azurite), pip `git-filter-repo` |
| VSCode | Extensions from `config/vscode-extensions.txt`, then sign in to Settings Sync (choose **Merge**) |
| Repos | Clones each bundle repo that's missing |
| AI | Copilot instructions and `mcp-config.json` to `~/.copilot`, Claude skills to `~/.claude/skills` |
| RDP | `.rdp` files to `Documents\RDP\<Folder>`. Double-click opens `mstsc`; tick *Remember me* on the first connect. On Windows, Windows App is only for AVD/Windows 365. |
| System (UAC) | `LongPathsEnabled`, WSL Ubuntu (`--no-launch`). After a reboot and first Ubuntu launch, re-run to apply `config/wsl-setup.sh` (starship, zoxide, eza, fzf, redis-tools for Valkey). |

## Mac to Windows differences

- `caffeinate` is a profile function that uses `SetThreadExecutionState`. `caffeinate -t <seconds>` works.
- `ls`/`ll`/`tree` use eza (the built-in `ls` alias is removed), and are plain text inside VS Code.
- `sqlp` is not ported (it reads the macOS Keychain).
- Valkey/Caddy: use WSL or Docker.
- Docker Desktop needs admin, possibly a paid license (check with IT), and membership in `docker-users`.
- Settings Sync brings over macOS-specific settings (`*.osx`). Review them once.

## Updating

- Packages: edit `packages.psd1`. Check winget IDs at <https://github.com/microsoft/winget-pkgs/tree/master/manifests>.
- Prompt: edit `../Starship/starship.toml`. That's the copy Windows installs. Keep it in sync with the Mac's `~/.config/starship.toml`.
- Then re-run `bootstrap.ps1 -Only Packages` or `-Only Shell`.
