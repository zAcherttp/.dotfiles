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
├── ssh/
│   └── config                  # GitHub host aliases (keys are NOT committed)
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
Nothing tracked here names an account, email, employer or host. Everything
private lives in a `.local` file that the tracked config pulls in. `install.sh`
writes each one as a commented template the first time, so a fresh machine
tells you what it expects; it never overwrites one that already exists.

| File | Pulled in by | Holds |
|---|---|---|
| `~/.zshrc.local` | `zsh/.zshrc` | Interactive shell: tokens, aliases, PATH |
| `~/.zprofile.local` | `zsh/.zprofile` | Login shell: PATH for cron, LaunchAgents, `ssh host cmd` |
| `~/.gitconfig.local` | `git/.gitconfig` | Personal identity, plus `includeIf` for per-org ones |
| `~/.gitconfig.<org>` | `~/.gitconfig.local` | One work/client identity |
| `~/.ssh/config.local` | `ssh/config` | Work accounts, internal hosts |
| `~/.ssh/github-*` | `ssh/config` | Key pairs (generated per machine, never committed) |

⚠️ **Git ignores a missing `includeIf` path silently** — no error, exit 0. If
`~/.gitconfig.<org>` is absent, work repos quietly author as the personal
identity. After setting up a machine, check from inside a work clone:

```bash
git config user.email
```

## Several GitHub accounts, no switching

`ssh/config` defines one host alias per account, each pinned to its own key.
The alias is a nickname for `github.com`, so which account a repo uses lives
in its remote URL and nothing global has to be flipped:

```bash
git remote set-url origin git@<alias>:owner/repo.git
```

Keys are per-machine and deliberately absent from this repo. Generate one per
alias, add the `.pub` at <https://github.com/settings/keys>, and verify:

```bash
ssh-keygen -t ed25519 -C <alias> -f ~/.ssh/<alias>
ssh -T git@<alias>   # expect: Hi <account>!
```

Only the personal alias is tracked here. Work or client accounts go in
`~/.ssh/config.local` — an alias names the account it belongs to, which is
the owner's to disclose rather than this repo's.

Note for submodules: keep `.gitmodules` on an `https://github.com/...` URL
and set the alias in local `.git/config` instead. `actions/checkout` only
rewrites `git@github.com:` for token auth, so a custom alias committed there
breaks CI on private submodules.
