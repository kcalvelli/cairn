## 1. Verification gates (do before any deletion)

- [x] 1.1 Inspect DMS's non-blur wallpaper surface
  (`Modules/WallpaperBackground.qml`) at the pinned rev and record its
  `WlrLayershell.namespace`. Confirm it is NOT `wallpaper` (i.e. the
  hand-written `namespace="^wallpaper$"` layer-rule in `niri.nix` only
  ever matched the retired `swaybg` surface). — VERIFIED:
  `WallpaperBackground.qml:25` sets only `WlrLayer.Background`, no
  namespace (quickshell default, ≠ `wallpaper`). Only `swaybg` ever used
  namespace `wallpaper`.
- [x] 1.2 Confirm DMS generates its own placement for the regular
  wallpaper (the `outputs`/`wpblur` includes already in
  `filesToInclude`), so deleting the `^wallpaper$` rule cannot regress
  the normal (non-overview) wallpaper. — VERIFIED: DMS only emits
  `place-within-backdrop` for `dms:blurwallpaper` (`niri-wpblur.kdl`);
  normal wallpaper rides `WlrLayer.Background` and needs no rule.
- [x] 1.3 If 1.1/1.2 show the `^wallpaper$` rule serves DMS's normal
  wallpaper, STOP and revise design before proceeding. — N/A, gate
  cleared.

## 2. Option + seed-once activation (`home/desktop/wallpaper.nix`)

- [x] 2.1 Add `cairn.wallpapers.overviewBlur` option: `lib.types.bool`,
  `default = true`, description noting it seeds the DMS
  `blurredWallpaperLayer` default and that the DMS GUI is the runtime
  opt-out.
- [x] 2.2 Add a `home.activation` entry (after `writeBoundary`,
  alongside `setRandomWallpaper`) that runs only the seed logic and is
  gated on the on-disk presence of the `blurredWallpaperLayer` key in
  `~/.config/DankMaterialShell/settings.json`:
  - key present (any value) → no-op
  - file exists but unparseable (`jq` parse fails) → no-op, leave file
    untouched
  - key absent: derive desired value from `cairn.wallpapers.overviewBlur`
- [x] 2.3 When seeding and DMS is running: best-effort
  `dms ipc call settings set blurredWallpaperLayer <true|false>`
  (path the dms binary via
  `inputs.dankMaterialShell.packages.${pkgs.stdenv.hostPlatform.system}.default`,
  same as `setRandomWallpaper`), `2>/dev/null`, tolerate failure.
- [x] 2.4 When seeding and IPC is unavailable / DMS not running: `jq`
  merge into the file — create `{"blurredWallpaperLayer": <bool>}` if the
  file is missing, else add the key only if absent; write atomically
  (tmp file + `mv`). Use `${pkgs.jq}` / `${pkgs.coreutils}`.
- [x] 2.5 Remove the `~/.cache/niri` `createNiriCache` activation
  (existed only for the baked JPEG); add a best-effort
  `rm -f $HOME/.cache/niri/overview-blur.jpg` to clean the orphan.
- [x] 2.6 Confirm the seed logic is profile-agnostic (fires for both
  standard and normie since both import `wallpaper.nix`).

## 3. Remove the custom pipeline

- [x] 3.1 `home/desktop/niri.nix`: delete the `swaybg` `spawn-at-startup`
  entry loading `~/.cache/niri/overview-blur.jpg` (lines ~50-58).
- [x] 3.2 `home/desktop/niri.nix`: delete the `layer-rules` entry
  matching `namespace="^wallpaper$"` → `place-within-backdrop` (lines
  ~123-128). Leave `wpblur` in `filesToInclude` untouched.
- [x] 3.3 `home/desktop/normie.nix`: delete the duplicate `swaybg`
  spawn / blur block (lines ~103-110); leave `wpblur` in its
  `filesToInclude` untouched.
- [x] 3.4 `scripts/wallpaper-changed.sh`: remove the ImageMagick blur +
  `pkill swaybg` + `swaybg` relaunch section (lines ~24-37). Leave the
  rest of the hook (color-scheme sync, Ghostty reload, logging) intact.
- [x] 3.5 Grep the repo for any remaining references to
  `overview-blur.jpg`, `~/.cache/niri`, or the retired `swaybg` blur
  spawn; confirm none remain outside intentional cleanup.

## 4. Validate

- [x] 4.1 `nix fmt .` — formatted clean (1 file reflowed).
- [x] 4.2 `nix flake check` — all checks passed (incl. `homeModules`).
- [x] 4.3 Build the example config (dry-run) to confirm the
  home-manager activation evaluates. — `iso` toplevel `--dry-run`
  evaluated with no errors; `homeModules` evaluated in flake check.
- [x] 4.4 `openspec validate dms-native-overview-blur`. — valid.
- [x] 4.5 Manual smoke on `edge`. — PASSED. First rebuild exposed the
  key-absence sentinel bug (DMS persists all keys → never fires);
  corrected to marker file. Re-test: marker written, `blurredWallpaperLayer`
  seeded `true` via IPC, no swaybg, orphan JPEG gone, `dms:blurwallpaper`
  Background surface present, `dms/wpblur.kdl` include intact. Live IPC
  toggle wedged DMS wallpaper render until relogin; after relogin both
  normal wallpaper and overview blur render correctly. One-time
  transitional relogin documented in design + spec; not automated.

## 5. Ship

- [x] 5.1 Commit with a message that isn't "update files", then **push**
  (downstream rebuilds pull from origin — unpushed commits are
  invisible to the user's `nixos-rebuild`).
