## Context

Cairn's overview blur was built before DMS shipped its own. The current
pipeline: a `wallpaper-changed.sh` hook bakes a Gaussian-blurred JPEG
with ImageMagick, kills and relaunches `swaybg` to paint it, a
`spawn-at-startup` entry launches `swaybg` against
`~/.cache/niri/overview-blur.jpg`, and a hand-written niri `layer-rule`
(`namespace="^wallpaper$"` → `place-within-backdrop`) pushes that surface
into the overview backdrop. The `normie` profile carries a second copy of
the spawn/layer-rule block.

DMS (locked rev `4bb3dd8`, 2026-05-14) now renders the backdrop itself:
`Modules/BlurredWallpaperBackground.qml` paints a
`WlrLayer.Background` surface with namespace `dms:blurwallpaper`, blurred
live by a `MultiEffect` shader, and DMS auto-generates
`~/.config/niri/dms/wpblur.kdl` containing the exact
`place-within-backdrop true` rule for that namespace. Cairn **already**
includes `wpblur` in `programs.dank-material-shell.niri.includes.filesToInclude`,
so the native mechanism is half-wired today — it's inert only because the
DMS setting `blurredWallpaperLayer` defaults to `false`.

The settings live in `~/.config/DankMaterialShell/settings.json`, a file
DMS owns and rewrites at runtime. DMS's home-manager module exposes
`programs.dank-material-shell.settings`, but home-manager materializes
that as a read-only nix-store symlink; DMS detects read-only settings and
disables GUI persistence for *every* setting. That is rejected (see
Decisions). The relevant precedent is the existing seed-once activation
at `home/desktop/wallpaper.nix:80` (`setRandomWallpaper`), which seeds a
default once and then hands ownership to DMS.

## Goals / Non-Goals

**Goals:**
- Retire the ImageMagick/`swaybg`/cache-JPEG pipeline entirely.
- Make the DMS-native blurred backdrop the zero-touch default for new
  and existing users.
- Keep `settings.json` writable so the DMS GUI stays the runtime
  opt-out; never overwrite a value the user (or DMS) already wrote.
- Provide a declarative opt-out via a `cairn.wallpapers.overviewBlur`
  option that defaults to current effective behavior (blur on).
- Converge the standard and `normie` profiles onto one mechanism.

**Non-Goals:**
- Managing `settings.json` declaratively / wholesale.
- Tuning DMS blur strength, transition timing, or the shader itself —
  DMS owns those.
- Forcing blur state on every activation. The seed fires at most once
  (see Decisions); it is not a reconciler.
- Removing `swaybg` or ImageMagick from the desktop package set — they
  have other consumers; we only stop using them here.

## Decisions

**1. Seed at most once, gated by a dedicated marker file — IPC-preferred,
`jq`-fallback — not `programs.dank-material-shell.settings`.**
Rationale: the DMS HM option writes a nix-store symlink → read-only →
DMS disables GUI persistence for all settings (theme, bar, everything).
That is a catastrophic side effect for a one-key default. So the seed
goes into the real, writable file.

**The sentinel is a dedicated marker file
`~/.cache/cairn-overview-blur-seeded`, NOT the presence of the
`blurredWallpaperLayer` key.** Key-presence was the original design and
it is wrong: DMS's `SettingsData.saveSettings()` writes the *entire*
settings object — every key, defaults included — on its first save. For
any user who has ever launched DMS (i.e. everyone but a brand-new
pre-first-launch install), `blurredWallpaperLayer` is present-and-`false`
from day one. "Key absent" is therefore almost never true, so a
key-absent gate makes the zero-touch default reach essentially nobody.
This was verified empirically on `edge`: post-rebuild the key was
present-`false` and the seed correctly no-op'd — exposing the flaw. A
separate one-time marker is the only reliable "have we performed our
one-time default yet" signal, exactly mirroring the
`setRandomWallpaper` hash-sentinel precedent in the same file.

When the marker is absent, perform the one-time seed of the value
implied by `overviewBlur` via two paths (mirroring `setRandomWallpaper`):

- **DMS running → IPC.** `dms ipc call settings set blurredWallpaperLayer
  <bool>` (verified handler: `DMSShellIPC.qml:867`, target `settings`;
  validates the key exists, coerces the `"true"`/`"false"` string to
  boolean, sets the live value, and calls `SettingsData.saveSettings()`
  which writes the full object to disk). DMS performs the write, so
  there is no clobber race. On `SETTINGS_SET_SUCCESS`, write the marker.
  **Caveat (verified on `edge`):** the *persisted* value is correct
  immediately, but the blur surface does not necessarily *render*
  correctly from a live toggle. `DMSShell.qml:66` loads
  `BlurredWallpaperBackground` via a `Loader` gated on the setting;
  instantiating that component mid-session, alongside the always-on
  `WallpaperBackground` sharing the same source, wedged DMS's wallpaper
  repaint until a DMS restart (relogin). The rendering is correct from
  the **next DMS start**, where the persisted setting is present at
  init and both wallpaper components come up together. So the IPC path
  guarantees persistence, not live render. An earlier draft claimed
  "applies live"; that was wrong and the empirical test caught it.
- **DMS not running → `jq`.** Set the key in `settings.json` (create the
  file if missing). On success, write the marker. DMS reads it on next
  launch; nothing is running to clobber it.

The marker is written **only on confirmed success** (IPC success, or a
successful `jq`/file write while DMS is down). If neither path can
confirm — IPC unavailable while DMS appears up, or `settings.json`
unparseable — the marker is **not** written and the seed retries on the
next activation, exactly like `setRandomWallpaper` only records its hash
on a confirmed `dms ipc` success.

Once the marker exists the seed never runs again, so a subsequent GUI
toggle is permanent and is never overwritten.

Alternatives considered: (a) declarative HM option — rejected, read-only
blast radius; (b) key-presence sentinel — **rejected, DMS pre-populates
all keys so it never fires for existing users** (this was the original
mistaken decision); (c) IPC-only — fails on fresh installs where DMS
isn't running yet; (d) `jq`-only — eats a one-session latency and a
clobber race when DMS is live (resolved by preferring IPC); (e)
value-comparison against the DMS default — cannot distinguish "user
chose `false`" from "DMS default `false`," same blind spot as the IPC
getter, which is *why* an out-of-band marker is required.

**2. `jq` fallback sets the key during the one-time seed.**
This path runs only when the marker is absent and IPC was unavailable.
- File missing → write `{"blurredWallpaperLayer": <bool>}`. DMS loads
  this partial file, fills the rest from defaults, and preserves the key
  on its first full-object save.
- File present and parses → `jq '.blurredWallpaperLayer = <bool>'`,
  written back atomically (tmp + `mv`). This is an unconditional set
  because it is the one-time seed gated by the marker — not a
  merge-if-absent.
- File present but unparseable → **skip, do not write the marker**. DMS
  itself refuses to overwrite an unparseable settings.json; we match
  that and retry next activation.

**3. `overviewBlur` selects the one-time seeded value; it is not a
reconciler.**
`cairn.wallpapers.overviewBlur` (bool, default `true`). On the single
seeding occasion it sets `blurredWallpaperLayer` to the option's value.
After the marker is written the option has no further effect — DMS/GUI
owns the value. Consequence to accept and document: on the one seeding
activation (including the first rebuild *after this change* for an
existing user) the value is set per the option, which can override a
pre-existing manual GUI choice that one time. The default is `true`,
matching the feature intent and Cairn's prior always-on blur, so for the
common case this aligns with what users already had. Alternative
considered: option=`false` forcibly rewrites the key every activation —
rejected, it would permanently fight the GUI and contradict the
writable-settings principle.

**4. Keep `wpblur` in `filesToInclude`; remove only the custom
`^wallpaper$` layer-rule and the `swaybg` spawn.**
The DMS-generated `dms/wpblur.kdl` *is* the native backdrop rule and
must stay included. The hand-written `namespace="^wallpaper$"`
layer-rule in `niri.nix` existed solely to backdrop our retired `swaybg`
surface; with `swaybg` gone it is dead. The `wallpaper-changed.sh` blur
block loses its ImageMagick + `pkill`/relaunch section but the hook
script otherwise stays (it still does color-scheme sync, etc.).

**5. Best-effort removal of the orphaned cache JPEG.**
Add a one-line `rm -f ~/.cache/niri/overview-blur.jpg` to the activation
(and drop the `~/.cache/niri` mkdir, which existed only for it). Cheap,
keeps the home dir honest, no rollback concern.

## Risks / Trade-offs

- **Key-presence is not a valid sentinel (the original design bug)** →
  DMS persists the full settings object, so `blurredWallpaperLayer` is
  present for every existing user and a key-absent gate never fires.
  Resolved by Decision 1's dedicated marker file. Caught only because
  the change was tested on `edge` before commit — noted here so the
  marker is never "simplified" back to key-presence.
- **DMS running during `nixos-rebuild switch` clobbers a raw file
  edit** → when DMS is up we use the IPC setter, so DMS performs the
  write — no race. The `jq` path only runs when DMS is *not* running,
  where there is nothing to clobber. Residual risk is IPC being
  unavailable while DMS is up (e.g. socket not ready early in session
  start); the marker is then not written and the seed retries next
  activation — same tolerance as `setRandomWallpaper`.
- **Transitional render wedge on the seeding activation (verified on
  `edge`)** → when the seed flips the setting live via IPC in a running
  session, the blur layer does not render correctly until DMS restarts;
  DMS's wallpaper repaint wedged (normal *and* blurred) until relogin,
  after which it is correct and stays correct. Impact is bounded: it
  occurs at most once per user — the single activation that performs the
  seed in a live session — and never on fresh installs (DMS starts with
  the setting already persisted). Mitigation is deliberately *not*
  automated: forcing a DMS/shell restart from a home-manager activation
  is more disruptive than a one-time relogin. Documented as a known
  one-time transitional cost in the spec instead.
- **The one-time seed runs once even for existing users** → on the first
  rebuild after this change lands, the marker is absent, so the value is
  set per `overviewBlur` that one time, potentially overriding a
  pre-existing manual GUI choice. Accepted: default `true` matches prior
  Cairn behavior (blur was always on), so the common case is unchanged;
  documented in the spec so it is not mistaken for a bug.
- **The `^wallpaper$` layer-rule might serve DMS's *non-blur*
  wallpaper** → if DMS's ordinary wallpaper surface also uses namespace
  `wallpaper` and depends on that backdrop rule, deleting it regresses
  normal wallpaper. Mitigation: before deletion, verify DMS's non-blur
  `WallpaperBackground.qml` namespace and that DMS generates its own
  placement (it generates `outputs`/`wpblur` includes). Treat as a
  verification gate in tasks, not an assumption.
- **Pre-seeding a partial `settings.json` before DMS's first run** →
  relies on DMS merging unknown-absent keys from defaults rather than
  treating a sparse file as authoritative. Verified against
  `SettingsData.loadSettings` (`Store.parse` over defaults, full-object
  save). Low risk; called out so the tasks step re-checks if the DMS
  pin moves.
- **Trade-off: the option is a one-time seed value, not an enforced
  state.** Once the marker exists, flipping `overviewBlur` has no effect
  — DMS/GUI owns the value. Intentional (GUI ownership wins post-seed);
  documented in the spec so it isn't mistaken for a bug. To re-seed
  deliberately, delete `~/.cache/cairn-overview-blur-seeded`.

## Migration Plan

1. Add `cairn.wallpapers.overviewBlur` option + seed-once activation in
   `home/desktop/wallpaper.nix`; drop the `~/.cache/niri` mkdir, add the
   stale-JPEG `rm -f`.
2. Remove the `swaybg` spawn-at-startup and the `^wallpaper$`
   layer-rule from `home/desktop/niri.nix` (after the namespace
   verification gate).
3. Remove the duplicate block from `home/desktop/normie.nix`.
4. Strip the ImageMagick + `pkill`/`swaybg` section from
   `scripts/wallpaper-changed.sh`; leave the rest of the hook intact.
5. `nix fmt .`, `nix flake check`, build the example config.
6. Rollback: revert the commit. No persistent state migration — the
   seeded `blurredWallpaperLayer` key is harmless if left, and the
   retired pipeline can be restored verbatim.

## Open Questions

- ~~Does `dms ipc` expose a settings setter?~~ **Resolved: yes.**
  `DMSShellIPC.qml:867`, target `settings`, `set(key, value)` — validates
  the key, coerces `"true"` → boolean, sets live, and `saveSettings()`
  persists. Folded into Decision 1 as the preferred seed path.
- Confirm DMS's non-blur wallpaper surface namespace so the
  `^wallpaper$` layer-rule deletion is provably safe (verification gate
  in tasks).
