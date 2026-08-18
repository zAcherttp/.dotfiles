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
link_file "$DOTFILES_DIR/git/.gitconfig" "$HOME/.gitconfig"
link_file "$DOTFILES_DIR/git/.gitignore_global" "$HOME/.gitignore_global"
link_file "$DOTFILES_DIR/iris/config.toml" "$HOME/.config/iris/config.toml"
link_file "$DOTFILES_DIR/iris/theme.toml" "$HOME/.config/iris/theme.toml"
link_file "$DOTFILES_DIR/iterm2/VSCodeDark.itermcolors" "$HOME/.config/iterm2/VSCodeDark.itermcolors"
link_file "$DOTFILES_DIR/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
link_file "$DOTFILES_DIR/zed/settings.json" "$HOME/.config/zed/settings.json"

# Create local templates if not existing
if [ ! -f "$HOME/.zshrc.local" ]; then
    echo "  ✓ Creating template ~/.zshrc.local"
    cat << 'EOF' > "$HOME/.zshrc.local"
# ~/.zshrc.local - Machine-specific environment variables & private secrets
EOF
fi

if [ ! -f "$HOME/.gitconfig.local" ]; then
    echo "  ✓ Creating template ~/.gitconfig.local"
    cat << 'EOF' > "$HOME/.gitconfig.local"
# ~/.gitconfig.local - Local Git user details
[user]
    name = Your Name
    email = your.email@example.com
EOF
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

echo ""
echo "🎉 Dotfiles setup complete!"
