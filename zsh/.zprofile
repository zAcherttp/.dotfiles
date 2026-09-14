# ==============================================================================
# ~/.zprofile — login shells, sourced AFTER /etc/zprofile.
# ==============================================================================
# /etc/zprofile runs macOS `path_helper`, which builds PATH from /etc/paths
# (/usr/bin, /bin, ...) and then APPENDS /etc/paths.d/* — so the Homebrew entry
# installed there lands *after* /usr/bin and system python3/openssl/pip3 win.
# Prepending here, after path_helper has run, is what actually fixes the order;
# putting it in .zshrc would miss login and non-interactive shells. brew
# shellenv also adds /opt/homebrew/sbin plus MANPATH/INFOPATH.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Docker Desktop CLI (appended: these should not shadow Homebrew).
if [ -d "$HOME/.docker/bin" ]; then
  export PATH="$PATH:$HOME/.docker/bin"
fi
