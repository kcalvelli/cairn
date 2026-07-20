#!/usr/bin/env bash
#
# Update the vendored claude-desktop manifest to the latest (or a given)
# version. The cairn overlay builds pkgs/claude-desktop from this manifest,
# fetching Anthropic's official native Linux .deb.
#
# Anthropic's apt repository publishes a machine-readable Packages index that
# already carries a SHA256 per release, so we don't download the 150 MB .deb
# just to hash it — we convert the published hex digest to SRI.
#
# Usage:
#   ./scripts/update-claude-desktop.sh              # latest stable release
#   ./scripts/update-claude-desktop.sh 1.22209.3    # a specific version
#
# Run by .github/workflows/update-claude-desktop.yml on a schedule; safe to
# run locally. Prints the resulting version on stdout.
set -euo pipefail

REPO_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
PACKAGES_URL="$REPO_BASE/dists/stable/main/binary-amd64/Packages"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/pkgs/claude-desktop-manifest.json"

PACKAGES="$(mktemp)"
trap 'rm -f "$PACKAGES"' EXIT
curl -fsSL "$PACKAGES_URL" --output "$PACKAGES"

# Emit "version<TAB>sha256<TAB>filename" for every stanza. Debian control
# stanzas are blank-line separated; awk collects the fields we need per record.
records() {
  awk '
    /^Version:/  { v = $2 }
    /^SHA256:/   { s = $2 }
    /^Filename:/ { f = $2 }
    /^$/         { if (v) print v "\t" s "\t" f; v = s = f = "" }
    END          { if (v) print v "\t" s "\t" f }
  ' "$PACKAGES"
}

if [ $# -ge 1 ]; then
  VERSION="$1"
else
  # Highest version by natural sort — the index isn't guaranteed ordered.
  VERSION="$(records | cut -f1 | sort -V | tail -n1)"
fi

LINE="$(records | awk -F'\t' -v v="$VERSION" '$1 == v { print; exit }')"
if [ -z "$LINE" ]; then
  echo "error: version $VERSION not found in $PACKAGES_URL" >&2
  exit 1
fi

SHA_HEX="$(printf '%s' "$LINE" | cut -f2)"
FILENAME="$(printf '%s' "$LINE" | cut -f3)"
URL="$REPO_BASE/$FILENAME"

# Convert the published hex digest to the SRI form fetchurl wants.
SRI="$(nix hash convert --hash-algo sha256 --to sri "sha256:$SHA_HEX" 2>/dev/null \
       || nix hash to-sri --type sha256 "$SHA_HEX")"

TMP="$(mktemp)"
cat > "$TMP" <<EOF
{
  "version": "$VERSION",
  "platforms": {
    "x86_64-linux": {
      "url": "$URL",
      "hash": "$SRI"
    }
  }
}
EOF
mv "$TMP" "$DEST"
echo "$VERSION"
