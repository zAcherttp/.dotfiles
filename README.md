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
├── uv/
│   └── uv.toml                 # uv cache on the dev volume
├── bun/
│   └── .bunfig.toml            # bun cache on the dev volume
├── fonts/                      # SFMono Nerd Font OTF files
└── scripts/
    ├── sync_iterm_colors.py    # iTerm2 color palette sync tool
    ├── macos.sh                # macOS UI & key repeat defaults script
    └── dev-volume.sh           # ~/dev on an encrypted, unindexed volume
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
- `./install.sh --dev-volume`: Moves `~/dev` onto its own volume (see below).

## Dev volume

Spotlight and fseventsd treat every file an install, build or agent worktree
writes as something to index and log. With many parallel agents that is a
core's worth of background CPU, and the fseventsd log keeps growing for days.
So `~/dev` lives on its own volume that neither of them touches:

```
APFS container (one shared pool of space; volumes have no fixed size)
├── Macintosh HD   macOS, sealed and read-only
├── Data           home, apps, caches            Spotlight: on
└── dev            projects, at the volume root  Spotlight: off, fseventsd log: off,
                   encrypted, auto-unlocks        Time Machine: excluded
~/dev -> /Volumes/dev
```

`scripts/dev-volume.sh` builds this on a fresh machine or migrates an existing
`~/dev`; it is idempotent. Run it from a plain Terminal outside `~/dev`, with
editors and agents closed. What it sets up:

| Piece | Where | Why |
|---|---|---|
| Projects | `/Volumes/dev/<project>` | Not indexed, not logged |
| pnpm store | `/Volumes/dev/.pnpm-store` (pnpm global rc) | Hard links only work within one volume |
| uv, bun caches | `/Volumes/dev/.cache/{uv,bun}` (`uv/`, `bun/` here) | Clones only work within one volume |
| git | `core.fsmonitor`, `core.untrackedCache` in `git/.gitconfig` | `git status` asks a watcher instead of rescanning |

`no_log` only stops fseventsd writing its on-disk log. Live file events still
flow, so file watchers and git's fsmonitor keep working.

Things the script can't do:

- **Spotlight Search Privacy** (System Settings → Spotlight → Search Privacy):
  add `~/Library/Application Support`, `~/Documents/Codex`, `~/Library/pnpm`,
  `~/.cache`, `~/.claude`, `~/.local`. That is app data nobody searches for,
  and it was most of what was left in the index.
- **Reinstall dependencies** after a migration (it deletes `node_modules`).

If `~/dev` looks empty after a reboot, the volume didn't auto-unlock:

```bash
diskutil apfs unlockVolume dev
```

Unmounting an encrypted volume locks it, so `diskutil unmount` + `mount` will
always ask for the passphrase.

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
