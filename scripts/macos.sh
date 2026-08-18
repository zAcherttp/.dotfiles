#!/usr/bin/env bash
# macOS Developer System Defaults
# Run this script on a fresh Mac to optimize UI, speed up key repeats, and improve developer ergonomics.

set -e

echo "⚙️  Configuring macOS developer defaults..."

# Close any open System Preferences panes
osascript -e 'tell application "System Preferences" to quit' 2>/dev/null || true

###############################################################################
# Keyboard & Typing (Fast key repeats for coding & vim)
###############################################################################
# Set a blazingly fast keyboard repeat rate
defaults write -g InitialKeyRepeat -int 15
defaults write -g KeyRepeat -int 2

# Disable automatic capitalization, smart dashes, smart periods, and auto-correct
defaults write -g NSAutomaticCapitalizationEnabled -bool false
defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false

# Disable press-and-hold for keys in favor of key repeat (crucial for VS Code / terminal Vim)
defaults write -g ApplePressAndHoldEnabled -bool false

###############################################################################
# Finder
###############################################################################
# Always show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Always show all filename extensions
defaults write -g AppleShowAllExtensions -bool true

# Show status bar and path bar in Finder
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowPathbar -bool true

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Avoid creating .DS_Store files on network or USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

###############################################################################
# Dock & Window Management
###############################################################################
# Speed up Mission Control animations
defaults write com.apple.dock expose-animation-duration -float 0.1

# Do not automatically rearrange Spaces based on most recent use
defaults write com.apple.dock mru-spaces -bool false

# Don't show recent applications in Dock
defaults write com.apple.dock show-recents -bool false

###############################################################################
# Restart Affected Services
###############################################################################
for app in "Finder" "Dock"; do
    killall "${app}" >/dev/null 2>&1 || true
done

echo "✅ macOS defaults applied successfully! (Some changes take full effect after logout/restart)"
