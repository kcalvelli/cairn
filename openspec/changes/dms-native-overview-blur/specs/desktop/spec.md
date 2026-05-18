## ADDED Requirements

### Requirement: Overview blur uses the DMS-native backdrop

The blurred wallpaper shown behind niri's overview SHALL be rendered by
DankMaterialShell's native blurred-wallpaper backdrop surface. Cairn
SHALL NOT bake a blurred image, run a separate wallpaper painter for the
backdrop, or hand-author the niri layer-rule that places it within the
overview backdrop; the DMS-generated include already supplies that rule.

#### Scenario: User opens the overview

- **WHEN** a user with the desktop or normie profile triggers the niri
  overview
- **THEN** the wallpaper visible in the overview backdrop is the
  DMS-rendered blurred surface (namespace `dms:blurwallpaper`)
- **AND** no `swaybg` instance and no pre-blurred image file are involved
  in producing it

#### Scenario: Wallpaper changes while DMS-native blur is active

- **WHEN** the active wallpaper changes
- **THEN** the overview backdrop reflects the new wallpaper
- **AND** no external image-processing step (e.g. ImageMagick) runs to
  produce a blurred copy

#### Scenario: DMS backdrop include remains wired

- **WHEN** the niri configuration is generated
- **THEN** `wpblur` remains present in
  `programs.dank-material-shell.niri.includes.filesToInclude`
- **AND** Cairn contributes no additional niri layer-rule for the
  overview wallpaper backdrop

### Requirement: Overview blur is enabled by default with a declarative opt-out

The desktop SHALL provide a `cairn.wallpapers.overviewBlur` option of
boolean type defaulting to `true`, such that a user who configures
nothing receives the DMS-native blurred overview. Setting the option to
`false` SHALL express the opposite declarative default. The option SHALL
default to the system's current effective behavior so that no downstream
host or user configuration requires changes.

#### Scenario: Fresh configuration with no overrides

- **WHEN** a user builds a system with the desktop or normie profile and
  does not set `cairn.wallpapers.overviewBlur`
- **THEN** the DMS-native overview blur is the effective default without
  any manual step in the DMS GUI

#### Scenario: Declarative opt-out before the one-time seed

- **WHEN** a user sets `cairn.wallpapers.overviewBlur = false` and the
  seed marker does not yet exist
- **THEN** the one-time seed sets `blurredWallpaperLayer` to `false`
- **AND** the DMS-native overview blur is not enabled by Cairn

### Requirement: The blur default is seeded at most once and never overrides user intent

Cairn SHALL establish the DMS `blurredWallpaperLayer` setting at most
once, gated on a dedicated one-time marker file
(`~/.cache/cairn-overview-blur-seeded`). The on-disk presence of the
`blurredWallpaperLayer` key SHALL NOT be used as the gate, because DMS
persists every settings key (defaults included) on its first save, so
the key is present for any user who has launched DMS. Once the marker
exists, Cairn SHALL NOT modify the setting again, and a subsequent
runtime change in the DMS GUI SHALL be permanent. The marker SHALL be
written only after the seed is confirmed applied, so an unconfirmed
attempt retries on a later activation.

#### Scenario: Seed fires once when the marker is absent

- **WHEN** activation runs and the seed marker does not exist
- **THEN** `blurredWallpaperLayer` is set once to the value of
  `cairn.wallpapers.overviewBlur`
- **AND** the marker is written on confirmed success
- **AND** subsequent activations make no further change to the setting

#### Scenario: Seed does not fire when the marker exists

- **WHEN** activation runs and the seed marker already exists (a prior
  activation seeded the default)
- **THEN** Cairn does not read or modify the DMS setting
- **AND** a value the user later set in the DMS GUI survives subsequent
  rebuilds

#### Scenario: Existing user with the key already present is still seeded

- **WHEN** the DMS settings file already contains `blurredWallpaperLayer`
  (written by DMS's full-object save) but the seed marker does not exist
- **THEN** Cairn still performs the one-time seed
- **AND** the zero-touch default reaches users who have already run DMS

#### Scenario: Live-session seed applies fully on next DMS start

- **WHEN** the one-time seed enables blur via DMS IPC in an
  already-running session
- **THEN** the setting is persisted immediately
- **AND** the blurred backdrop is guaranteed to render correctly from
  the next DMS start (e.g. relogin); a one-time transitional relogin to
  get correct rendering in the current session is an accepted, documented
  cost and SHALL NOT be worked around by restarting the shell from
  activation

#### Scenario: DMS settings file remains writable

- **WHEN** Cairn establishes the blur default
- **THEN** `~/.config/DankMaterialShell/settings.json` remains a
  writable file and not a read-only store symlink
- **AND** the DMS GUI can still persist changes to any setting

#### Scenario: Unconfirmed seed retries

- **WHEN** activation runs with the marker absent, and the seed cannot be
  confirmed (DMS IPC unavailable while DMS is up, or `settings.json`
  exists but cannot be parsed as JSON)
- **THEN** Cairn does not corrupt or overwrite the settings file
- **AND** the marker is not written
- **AND** the seed is retried on the next activation
