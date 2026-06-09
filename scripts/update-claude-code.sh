#!/usr/bin/env bash
#
# Update the vendored claude-code release manifest to the latest (or a given)
# version. The cairn overlay (pkgs/default.nix) imports this manifest to pin
# claude-code ahead of nixpkgs.
#
# Usage:
#   ./scripts/update-claude-code.sh           # latest stable release
#   ./scripts/update-claude-code.sh 2.1.170   # a specific version
#
# Run by .github/workflows/update-claude-code.yml on a schedule, but safe to
# run locally too. Prints the resulting version on stdout.
set -euo pipefail

BASE_URL="https://downloads.claude.ai/claude-code-releases"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pkgs/claude-code-manifest.json"

VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"

# Download to a temp file first so a failed/partial fetch never clobbers the
# committed manifest.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -fsSL "$BASE_URL/$VERSION/manifest.json" --output "$TMP"

# Sanity check: the fetched manifest must report the version we asked for.
GOT="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$TMP" | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
if [ "$GOT" != "$VERSION" ]; then
  echo "error: manifest version ($GOT) does not match requested version ($VERSION)" >&2
  exit 1
fi

mv "$TMP" "$DEST"
trap - EXIT
echo "$VERSION"
