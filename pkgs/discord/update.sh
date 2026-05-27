#!/usr/bin/env bash
# Regenerate sources.json from Discord's distribution manifest.
# Discord rejects requests without the Discord-Updater User-Agent.
set -euo pipefail

cd "$(dirname "$0")"

python3 - <<'PY'
import base64
import json
import urllib.request

def sri(hex_hash: str) -> str:
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_hash)).decode()

url = (
    "https://updates.discord.com/distributions/app/manifests/latest"
    "?channel=stable&platform=linux&arch=x64"
)
req = urllib.request.Request(url, headers={"User-Agent": "Discord-Updater/1"})
manifest = json.loads(urllib.request.urlopen(req).read())

out = {
    "version": ".".join(str(x) for x in manifest["full"]["host_version"]),
    "distro": {
        "url": manifest["full"]["url"],
        "hash": sri(manifest["full"]["package_sha256"]),
    },
    "modules": {
        name: {
            "version": mod["full"]["module_version"],
            "url": mod["full"]["url"],
            "hash": sri(mod["full"]["package_sha256"]),
        }
        for name, mod in sorted(manifest["modules"].items())
    },
}

with open("sources.json", "w") as f:
    json.dump(out, f, indent=2, sort_keys=True)
    f.write("\n")

print(f"discord {out['version']}: {len(out['modules'])} modules pinned")
PY
