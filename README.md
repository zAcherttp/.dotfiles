# Dotfiles

Personal terminal configuration, themes, fonts, and developer ergonomics for macOS.

## Structure
```
~/.dotfiles/
├── install.sh                  # 🚀 Idempotent 1-command installer
├── Brewfile                    # Homebrew bundle (CLI tools, casks)
├── README.md                   # Documentation
├── .gitignore                  # Keeps caches & secrets untracked
├── zsh/
│   └── .zshrc                  # Modular zsh config (sources ~/.zshrc.local)
├── git/
│   ├── .gitconfig              # Global Git config (includes ~/.gitconfig.local)
│   └── .gitignore_global       # Global Git ignore rules
├── iris/
│   ├── config.toml             # Iris autocomplete configuration
│   └── theme.toml              # Iris Emerald Branch color theme
├── iterm2/
│   └── VSCodeDark.itermcolors  # Deep Dark VS Code color preset
├── vscode/
│   └── settings.json           # VS Code User settings & Nerd Font
├── zed/
│   └── settings.json           # Zed editor configuration
├── fonts/                      # SFMono Nerd Font OTF files
└── scripts/
    ├── sync_iterm_colors.py    # iTerm2 color palette sync tool
    └── macos.sh                # macOS UI & key repeat defaults script
```

## Quick Installation

```bash
git clone <your-dotfiles-repo-url> ~/.dotfiles
cd ~/.dotfiles
./install.sh
```

### Options:
- `./install.sh --brew`: Installs all Homebrew packages & casks.
- `./install.sh --macos`: Applies macOS keyboard repeat rates and Finder tweaks.
- `./install.sh --all`: Runs symlinks, Brewfile, and macOS system tweaks.

## Zero-Leak Privacy Architecture
1. **Shell Secrets**: Add private API tokens and work paths to `~/.zshrc.local` (sourced automatically, ignored by Git).
2. **Git Identity**: Add your personal/work Git email to `~/.gitconfig.local` (included automatically, ignored by Git).
