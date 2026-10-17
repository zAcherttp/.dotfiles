#!/usr/bin/env bash
# shellcheck disable=SC2088  # "~/dev" in messages is meant literally
# ==============================================================================
# Dev volume: put ~/dev on its own encrypted APFS volume that Spotlight never
# indexes and fseventsd never logs, so agents, installs and worktrees stop
# costing background CPU. Projects sit at the volume root; ~/dev is a symlink.
#
#   /Volumes/dev/            <- encrypted APFS volume, same container as Data
#   ├── <your projects>
#   ├── .pnpm-store/         <- pnpm store (same volume => hard links)
#   └── .cache/{uv,bun}/     <- uv / bun caches (same volume => clones)
#   ~/dev -> /Volumes/dev
#
# Run from a plain Terminal, outside ~/dev, with editors and agents closed:
#   ~/.dotfiles/scripts/dev-volume.sh
#
# Safe to re-run: every step checks whether it's already done. Works on a
# fresh machine (no ~/dev yet) and on one with an existing ~/dev folder.
# ==============================================================================
set -euo pipefail

VOL_NAME="dev"
VOL="/Volumes/$VOL_NAME"
LINK="$HOME/dev"
BACKUP="$HOME/dev.pre-migration"
MARGIN_KB=$((10 * 1024 * 1024))   # keep 10 GB free after the copy

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[31mxx %s\033[0m\n' "$*" >&2; exit 1; }
confirm() { local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

# --- Preflight -------------------------------------------------------------
bold "Preflight"
[[ "$(uname -s)" == Darwin ]] || die "macOS only."
[[ $EUID -ne 0 ]] || die "Run as your normal user; the script calls sudo itself."
case "$(lower "$(pwd -P)")" in
  "$(lower "$LINK")"*|"$(lower "$VOL")"*) die "You're inside ~/dev. Run it from ~ instead." ;;
esac
# The APFS container that holds the boot Data volume; the new volume shares its space.
CONTAINER=$(diskutil info -plist / | plutil -extract APFSContainerReference raw -)
echo "APFS container: $CONTAINER"

MIGRATE=0
if [[ -L "$LINK" ]]; then
  echo "~/dev is already a symlink -> $(readlink "$LINK")."
elif [[ -d "$LINK" ]]; then
  MIGRATE=1
  echo "~/dev is a regular folder; it will be moved onto the volume."
else
  echo "No ~/dev yet; it will be created as a link to the volume."
fi

sudo -v
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

# --- 1. Processes holding ~/dev ---------------------------------------------
if [[ $MIGRATE -eq 1 ]]; then
  bold "1. Checking for processes running inside ~/dev"
  while true; do
    busy=$(lsof -n -d cwd 2>/dev/null \
      | awk -v d="$(lower "$LINK")" 'NR>1 { p=tolower($NF); if (p==d || index(p, d"/")==1) printf "%-8s %-20s %s\n", $2, $1, $NF }' \
      | sort -u)
    [[ -z "$busy" ]] && { echo "None."; break; }
    warn "These processes have a working directory inside ~/dev:"
    echo "$busy"
    echo
    echo "Quit them (editors, dev servers, agent sessions, terminals cd'd into ~/dev)."
    read -r -p "Press Enter to re-check, 'k' to kill them all, or Ctrl-C to abort: " ans
    if [[ "$ans" == k ]]; then
      awk '{print $1}' <<<"$busy" | xargs kill 2>/dev/null || true
      sleep 2
    fi
  done

  # --- 2. node_modules: cheaper to reinstall than to copy -----------------
  bold "2. Removing node_modules folders (reinstall them afterwards)"
  nm_count=$(find "$LINK" -xdev -type d -name node_modules -prune 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$nm_count" -gt 0 ]] && confirm "Delete $nm_count node_modules folders under ~/dev?"; then
    find "$LINK" -xdev -type d -name node_modules -prune -print0 | xargs -0 -n 20 rm -rf
    echo "Done."
  fi

  # --- 3. Space check --------------------------------------------------------
  bold "3. Checking free space"
  need_kb=$(du -sk "$LINK" | awk '{print $1}')
  free_kb=$(df -k "$HOME" | awk 'NR==2 {print $4}')
  printf "~/dev uses %.1f GB; the container has %.1f GB free.\n" \
    "$(bc -l <<<"$need_kb/1048576")" "$(bc -l <<<"$free_kb/1048576")"
  (( free_kb > need_kb + MARGIN_KB )) || die "Not enough free space (need ~/dev size + 10 GB)."
fi

# --- 4. The encrypted volume -------------------------------------------------
bold "4. Encrypted APFS volume '$VOL_NAME'"
if diskutil info "$VOL_NAME" >/dev/null 2>&1; then
  echo "Already exists."
  [[ -d "$VOL" ]] || diskutil apfs unlockVolume "$VOL_NAME" || die "Couldn't unlock '$VOL_NAME'."
else
  while true; do
    read -r -s -p "Choose a passphrase for the dev volume: " PASS; echo
    read -r -s -p "Repeat it: " PASS2; echo
    [[ -n "$PASS" && "$PASS" == "$PASS2" ]] && break
    warn "Empty or mismatched, try again."
  done
  unset PASS2
  # Case-insensitive like the Data volume, so repos behave the same.
  printf '%s' "$PASS" | sudo diskutil apfs addVolume "$CONTAINER" APFS "$VOL_NAME" -stdinpassphrase
  [[ -d "$VOL" ]] || die "Volume created but not mounted at $VOL."

  # Login-keychain entry = what Disk Utility's "Remember password" does, so
  # macOS unlocks the volume at login.
  uuid=$(diskutil info -plist "$VOL" | plutil -extract VolumeUUID raw -)
  if security add-generic-password -U \
      -a "$uuid" -s "$uuid" -l "$VOL_NAME" -D "encrypted volume password" \
      -T /System/Library/CoreServices/APFSUserAgent \
      -T /System/Library/CoreServices/CSUserAgent \
      -w "$PASS" "$HOME/Library/Keychains/login.keychain-db"; then
    echo "Passphrase saved to the login keychain (auto-unlock at login)."
  else
    warn "Keychain save failed: unlock once in Disk Utility and tick 'Remember password'."
  fi
  unset PASS
  warn "Store the passphrase in your password manager too."
fi

# --- 5. No Spotlight, no fseventsd log, no Time Machine ----------------------
bold "5. Turning off Spotlight, the fseventsd log and Time Machine for $VOL"
sudo diskutil enableOwnership "$VOL" >/dev/null   # real ownership, or git complains
sudo chown "$(id -un):staff" "$VOL"
sudo mdutil -i off "$VOL" >/dev/null 2>&1 || true
sudo mdutil -d "$VOL" >/dev/null 2>&1 || true
sudo touch "$VOL/.metadata_never_index"
# no_log stops the on-disk event log only; live FSEvents (watchers, git
# fsmonitor) keep working.
if [[ ! -f "$VOL/.fseventsd/no_log" ]]; then
  sudo rm -rf "$VOL/.fseventsd"
  sudo mkdir "$VOL/.fseventsd"
  sudo touch "$VOL/.fseventsd/no_log"
  # fseventsd reads no_log at mount time. Unmounting an encrypted volume
  # locks it, so this asks for the passphrase once.
  echo "Remounting so fseventsd picks up no_log (enter the passphrase if asked)..."
  dev_id=$(diskutil info -plist "$VOL" | plutil -extract DeviceIdentifier raw -)
  diskutil unmount "$VOL" >/dev/null
  diskutil mount "$dev_id" >/dev/null 2>&1 || diskutil apfs unlockVolume "$dev_id"
  [[ -d "$VOL" ]] || die "Volume didn't come back at $VOL."
fi
sudo tmutil addexclusion -v "$VOL" 2>/dev/null || warn "Couldn't add a Time Machine exclusion."
mdutil -s "$VOL" | sed 's/^/   /'

# --- 6. Projects onto the volume, ~/dev -> volume ----------------------------
if [[ $MIGRATE -eq 1 ]]; then
  bold "6. Copying ~/dev onto $VOL"
  entries=()
  while IFS= read -r -d '' e; do entries+=("${e##*/}"); done \
    < <(find "$LINK" -mindepth 1 -maxdepth 1 -not -name .DS_Store -print0)
  for e in "${entries[@]}"; do
    [[ -e "$VOL/$e" ]] && die "$VOL/$e already exists; resolve that clash and re-run."
  done
  for e in "${entries[@]}"; do ditto "$LINK/$e" "$VOL/$e"; done

  echo "Verifying..."
  src_n=0; dst_n=0
  for e in "${entries[@]}"; do
    src_n=$((src_n + $(find "$LINK/$e" -xdev | wc -l)))
    dst_n=$((dst_n + $(find "$VOL/$e" -xdev | wc -l)))
  done
  echo "   source: $src_n entries, copy: $dst_n entries"
  [[ "$src_n" == "$dst_n" ]] || die "Counts differ. ~/dev is untouched; check the copy on $VOL."
  mv "$LINK" "$BACKUP"
fi
if [[ ! -L "$LINK" ]]; then
  ln -s "$VOL" "$LINK"
fi
echo "~/dev -> $(readlink "$LINK")"

# --- 7. Package caches on the same volume ------------------------------------
# Clones and hard links only work within one volume, so caches live next to
# the projects. uv and bun read their paths from uv/uv.toml and
# bun/.bunfig.toml (linked by install.sh); pnpm keeps it in its global rc.
bold "7. Package caches"
mkdir -p "$VOL/.pnpm-store" "$VOL/.cache"
move_cache() {  # old new
  if [[ -d "$1" && ! -L "$1" && ! -e "$2" ]]; then
    echo "Moving $1 -> $2"; mv "$1" "$2"
  fi
  mkdir -p "$2"
}
move_cache "$HOME/.cache/uv" "$VOL/.cache/uv"
move_cache "$HOME/.bun/install/cache" "$VOL/.cache/bun"
if command -v pnpm >/dev/null; then
  pnpm config set store-dir "$VOL/.pnpm-store" --global
  echo "pnpm store-dir = $(pnpm config get store-dir)"
fi

# --- 8. Old copy -------------------------------------------------------------
if [[ -d "$BACKUP" ]]; then
  bold "8. Original folder"
  echo "The original ~/dev is still at $BACKUP. Open a few projects first."
  read -r -p "Type DELETE to remove it now, or press Enter to keep it: " ans
  if [[ "$ans" == DELETE ]]; then rm -rf "$BACKUP"; echo "Removed."
  else echo "Kept. Later:  rm -rf \"$BACKUP\""; fi
fi

bold "Done"
cat <<EOF
- ~/dev -> $VOL (encrypted; no Spotlight, no fseventsd log, no Time Machine).
- Reinstall dependencies per project (npm ci / pnpm install / bun install / uv sync).
- Still manual: System Settings > Spotlight > Search Privacy (see README).
- If ~/dev is empty after a reboot:  diskutil apfs unlockVolume $VOL_NAME
EOF
