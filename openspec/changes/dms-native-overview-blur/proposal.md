## Why

Cairn's overview-blur effect predates DMS having one. We bake a blurred
JPEG with ImageMagick on every wallpaper change, juggle a `swaybg`
process to paint it, and hand-write a niri `layer-rule` to shove it into
the overview backdrop. DMS now renders that backdrop itself — a live
shader-blurred `dms:blurwallpaper` layer surface — and auto-generates the
exact `place-within-backdrop` rule we hand-wrote, in an include Cairn is
*already pulling in*. Our pipeline is now dead weight: an extra process,
an ImageMagick dependency, a stale cache file, and blur that lags the
wallpaper transition instead of tracking it. The native path is strictly
better and the only reason it isn't already live is that its toggle
defaults off.

## What Changes

- **BREAKING (internal):** Remove the custom overview-blur pipeline:
  - `swaybg` spawn loading `~/.cache/niri/overview-blur.jpg`
    (`home/desktop/niri.nix:50-58`)
  - hand-written `namespace="^wallpaper$"` layer-rule
    (`home/desktop/niri.nix:123-128`) — DMS's generated `dms/wpblur.kdl`
    already supplies the equivalent rule for `dms:blurwallpaper`
  - duplicate `swaybg`/blur block in `home/desktop/normie.nix:103-110`
  - ImageMagick blur + `pkill`/relaunch `swaybg` block in
    `scripts/wallpaper-changed.sh:24-37`
  - `~/.cache/niri` activation dir in `home/desktop/wallpaper.nix:59-62`
    (existed only to hold the baked JPEG)
- Add `cairn.wallpapers.overviewBlur` option (bool, **default true**)
  exposing declarative opt-out with a sane default.
- When enabled, a first-run activation in `home/desktop/wallpaper.nix`
  `jq`-merges `blurredWallpaperLayer: true` into
  `~/.config/DankMaterialShell/settings.json` **only when the key is
  absent** (or the file is missing/unparseable), leaving the file
  writable. DMS keeps ownership of its settings; the GUI remains the
  runtime opt-out and a user's later toggle is never overwritten. This
  mirrors the existing seed-once hash-sentinel pattern at
  `wallpaper.nix:80` (`setRandomWallpaper`).
- Explicitly **not** using `programs.dank-material-shell.settings`: it
  generates settings.json as a read-only nix-store symlink, which makes
  *every* DMS setting declarative-only and breaks GUI persistence
  (theme, bar, all of it). Rejected.

Net result: new and existing users get the DMS-native blurred overview
with zero action, no ImageMagick, no `swaybg`, no cache file. Opt out
declaratively via the option or at runtime via the DMS GUI.

## Capabilities

### New Capabilities

<!-- None — this is a refactor of existing desktop behavior. -->

### Modified Capabilities

- `desktop`: The "Wallpaper & Theming" requirement changes how blurred
  overview backgrounds are delivered (DMS-native shader layer instead of
  a baked JPEG painted by `swaybg`) and adds a zero-touch declarative
  default with runtime/declarative opt-out.

## Impact

- **Code:** `home/desktop/wallpaper.nix` (new option + seed-once
  activation, remove cache-dir activation), `home/desktop/niri.nix`
  (remove spawn + layer-rule), `home/desktop/normie.nix` (remove
  duplicate block), `scripts/wallpaper-changed.sh` (remove blur/swaybg
  block).
- **Dependencies:** ImageMagick and `swaybg` are no longer required *for
  overview blur*; verify they have no other consumers before treating
  them as droppable (`swaybg` is still listed as a desktop Wayland tool
  in the `desktop` spec — keep the package, just stop using it here).
- **Runtime state:** `~/.config/DankMaterialShell/settings.json` gains a
  seeded `blurredWallpaperLayer` key on first activation; stale
  `~/.cache/niri/overview-blur.jpg` is left orphaned (harmless; note for
  cleanup).
- **Profiles:** Both standard desktop and `normie` profiles; behavior
  converges (normie previously carried its own copy).
- **No user-facing config break:** downstream host/user configs need no
  changes; the new option defaults to current effective behavior.
