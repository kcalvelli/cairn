#!/usr/bin/env bash
set -e

# Dank Hooks script for onWallpaperChanged
# Called with: $1 = hook name ("onWallpaperChanged"), $2 = wallpaper path

HOOK_NAME="${1:-}"
WALLPAPER="${2:-}"
START_TIME=$(date +%s%N)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wallpaper changed: $WALLPAPER"

# Overview blur is rendered natively by DMS (dms:blurwallpaper backdrop).
# No blurred-copy generation or swaybg juggling needed here anymore.

# Reload Ghostty config with keys
wtype -M ctrl -M shift , -m shift -m ctrl

# Sync kdeglobals with DankMatugen color scheme for KDE apps
# KDE apps (filelight, showfoto, etc.) read colors from kdeglobals, not qt6ct
COLOR_SCHEME="$HOME/.local/share/color-schemes/DankMatugen.colors"
KDEGLOBALS="$HOME/.config/kdeglobals"

if [ -f "$COLOR_SCHEME" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing kdeglobals with DankMatugen color scheme..."
  cp "$COLOR_SCHEME" "$KDEGLOBALS"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] kdeglobals updated"
fi

END_TIME=$(date +%s%N)
TOTAL_TIME=$(( (END_TIME - START_TIME) / 1000000 ))
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Wallpaper change handling complete (total: ${TOTAL_TIME}ms)"
