#!/usr/bin/env bash
# ==============================================================================
# Dotfiles Idempotent Installer
# Safe to run multiple times. Backs up colliding files and restores symlinks.
# ==============================================================================
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)"

echo "🚀 Bootstrapping dotfiles from: $DOTFILES_DIR"

# Helper function to safely symlink files with automatic backup
link_file() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ "$(readlink "$dst" 2>/dev/null)" = "$src" ]; then
            echo "  ✓ Already linked: $dst"
            return 0
        else
            mkdir -p "$BACKUP_DIR"
            echo "  ⚠️  Backing up existing $(basename "$dst") to $BACKUP_DIR"
            mv "$dst" "$BACKUP_DIR/"
        fi
    fi

    ln -s "$src" "$dst"
    echo "  ✓ Linked: $dst -> $src"
}

# 1. Fonts
echo "📦 Installing fonts..."
mkdir -p "$HOME/Library/Fonts"
if [ -d "$DOTFILES_DIR/fonts" ]; then
    cp -n "$DOTFILES_DIR/fonts/"* "$HOME/Library/Fonts/" 2>/dev/null || true
    echo "  ✓ Fonts verified"
fi

# 2. Symlinks
echo "🔗 Symlinking configurations..."
link_file "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
link_file "$DOTFILES_DIR/zsh/.zprofile" "$HOME/.zprofile"
link_file "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
link_file "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
# ssh refuses to use a config in a world-writable directory.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
link_file "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config"
link_file "$DOTFILES_DIR/iris/config.toml" "$HOME/.config/iris/config.toml"
link_file "$DOTFILES_DIR/iris/theme.toml" "$HOME/.config/iris/theme.toml"
link_file "$DOTFILES_DIR/iterm2/VSCodeDark.itermcolors" "$HOME/.config/iterm2/VSCodeDark.itermcolors"
link_file "$DOTFILES_DIR/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
link_file "$DOTFILES_DIR/zed/settings.json" "$HOME/.config/zed/settings.json"
link_file "$DOTFILES_DIR/uv/uv.toml" "$HOME/.config/uv/uv.toml"
link_file "$DOTFILES_DIR/bun/.bunfig.toml" "$HOME/.bunfig.toml"

# Create local templates if not existing
if [ ! -f "$HOME/.zshrc.local" ]; then
    echo "  ✓ Creating template ~/.zshrc.local"
    cat << 'EOF' > "$HOME/.zshrc.local"
# ~/.zshrc.local - Machine-specific environment variables & private secrets.
#
# Sourced near the end of ~/.zshrc, so it can override anything the repo sets.
# INTERACTIVE shells only -- for PATH that LaunchAgents, cron or `ssh host cmd`
# also need, use ~/.zprofile.local instead.
#
#   export SOME_API_TOKEN="..."          # never commit these
#   export PATH="$HOME/some/tool:$PATH"
#   alias work="cd ~/dev/<org>"
EOF
fi

if [ ! -f "$HOME/.zprofile.local" ]; then
    echo "  ✓ Creating template ~/.zprofile.local"
    cat << 'EOF' > "$HOME/.zprofile.local"
# ~/.zprofile.local - Machine-specific LOGIN-shell setup.
#
# Sourced at the end of ~/.zprofile, so it runs for non-interactive login
# shells too (LaunchAgents, cron, `ssh host cmd`) where ~/.zshrc -- and so
# ~/.zshrc.local -- is never read. Put a PATH entry here when something
# outside an interactive terminal has to find it.
#
#   export PATH="/opt/whatever/bin:$PATH"
EOF
fi

if [ ! -f "$HOME/.gitconfig.local" ]; then
    echo "  ✓ Creating template ~/.gitconfig.local"
    cat << 'EOF' > "$HOME/.gitconfig.local"
# ~/.gitconfig.local - Local Git user details, not committed.
#
# Use the noreply address verified on the GitHub account. A plain personal
# address that is not on the account authors commits that link to nobody.
[user]
    name = Your Name
    email = 0000000+you@users.noreply.github.com

# A work or client identity applies per directory, so cloning into the right
# folder is all it takes. Pair it with a matching SSH alias in
# ~/.ssh/config.local, and keep the identity file itself out of the repo:
#
#   [includeIf "gitdir:~/dev/<org>/"]
#       path = ~/.gitconfig.<org>
#
# ...where ~/.gitconfig.<org> is just the identity itself:
#
#   [user]
#       name = Your Name
#       email = you@<org>.com
#
# Create that file too. Git ignores a missing include path silently -- exit 0,
# no warning -- so if it is absent the work repos quietly author as the
# personal identity above. Verify after setup, from inside a work clone:
#
#   git config user.email
EOF
fi

if [ ! -f "$HOME/.ssh/config.local" ]; then
    echo "  ✓ Creating template ~/.ssh/config.local"
    cat << 'EOF' > "$HOME/.ssh/config.local"
# ~/.ssh/config.local - Machine-specific hosts, not committed.
#
# Included first by ssh/config, so anything here wins.
#
# The personal GitHub alias is tracked in the repo and already works. Work and
# client accounts live here instead, because an alias names the account it
# belongs to. On a machine that needs one, uncomment and fill in:
#
#   Host github-<account>
#       HostName github.com
#       User git
#       IdentityFile ~/.ssh/github-<account>
#       IdentitiesOnly yes
#
# Then, once per machine:
#   ssh-keygen -t ed25519 -C github-<account> -f ~/.ssh/github-<account>
#   pbcopy < ~/.ssh/github-<account>.pub   # add at github.com/settings/keys
#   ssh -T git@github-<account>            # expect: Hi <account>!
#
# Point a repo at it with the remote URL, not by switching anything global:
#   git remote set-url origin git@github-<account>:owner/repo.git
#
# A work machine usually also wants a matching commit identity -- see the
# includeIf block in ~/.gitconfig.local.
EOF
    chmod 600 "$HOME/.ssh/config.local"
fi

# 3. Synchronize iTerm2 Colors
if [ -f "$DOTFILES_DIR/scripts/sync_iterm_colors.py" ]; then
    echo "🎨 Syncing iTerm2 colors..."
    python3 "$DOTFILES_DIR/scripts/sync_iterm_colors.py" || true
fi

# 4. Optional Homebrew Bundle
if command -v brew >/dev/null 2>&1 && [ -f "$DOTFILES_DIR/Brewfile" ]; then
    if [ "$1" = "--brew" ] || [ "$1" = "-b" ]; then
        echo "🍺 Installing Homebrew dependencies..."
        brew bundle --file="$DOTFILES_DIR/Brewfile"
    else
        echo "💡 Tip: Run './install.sh --brew' to install all Brewfile packages."
    fi
fi

# 5. Optional macOS Defaults
if [ "$1" = "--macos" ] || [ "$1" = "-m" ] || [ "$1" = "--all" ]; then
    echo "⚙️  Running macOS system optimizations..."
    "$DOTFILES_DIR/scripts/macos.sh"
fi

# 6. Optional dev volume (interactive: asks for sudo and a passphrase)
if [ "$1" = "--dev-volume" ]; then
    echo "💽 Setting up the dev volume..."
    "$DOTFILES_DIR/scripts/dev-volume.sh"
elif [ ! -L "$HOME/dev" ]; then
    echo "💡 Tip: Run './install.sh --dev-volume' to move ~/dev onto an unindexed volume."
fi

echo ""
echo "🎉 Dotfiles setup complete!"
