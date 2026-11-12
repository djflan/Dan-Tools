#!/usr/bin/env bash
# Shell setup inside WSL Ubuntu. Run by the System phase once the distro has a user, or by hand:
#   wsl -d Ubuntu -- bash /mnt/c/<path>/WindowsSetup/config/wsl-setup.sh /mnt/c/<path>/Starship/starship.toml
# Safe to re-run.
set -euo pipefail

starship_toml="${1:-}"

sudo apt-get update
# redis-tools provides redis-cli, which also talks to Valkey.
sudo apt-get install -y curl git unzip fzf eza zoxide redis-tools

if ! command -v starship >/dev/null 2>&1; then
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y
fi

mkdir -p ~/.config
if [ -n "$starship_toml" ] && [ -f "$starship_toml" ]; then
    cp "$starship_toml" ~/.config/starship.toml
fi

marker='# >>> dan-tools wsl-setup >>>'
if ! grep -qF "$marker" ~/.bashrc; then
    cat >> ~/.bashrc <<'EOF'
# >>> dan-tools wsl-setup >>>
alias ls="eza --icons"
alias ll="eza -lah --icons --git"
alias tree="eza --tree --icons"
eval "$(zoxide init bash)"
eval "$(starship init bash)"
[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && source /usr/share/doc/fzf/examples/key-bindings.bash
# <<< dan-tools wsl-setup <<<
EOF
fi

mkdir -p ~/.local/state && touch ~/.local/state/dan-tools-wsl-setup.done
echo "WSL shell setup complete. Open a new WSL shell to pick it up."
