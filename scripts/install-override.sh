#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_ROOT="/Library/Displays/Contents/Resources/Overrides"
OWNER="${SUDO_USER:-$USER}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "re-running with sudo..."
  exec sudo "$0" "$@"
fi

mkdir -p "$DEST_ROOT"
# Let the installing user create per-display plists later without sudo.
# Directory only — do not recursively steal other overrides.
chown "$OWNER" "$DEST_ROOT"
chmod u+rwx "$DEST_ROOT"
echo "override directory owned by $OWNER: $DEST_ROOT"
echo "Menu-bar native changes will not need sudo after this."
