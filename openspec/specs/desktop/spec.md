# Desktop Environment

## Purpose
Provides a modern, polished Wayland-based desktop experience using the Niri compositor and DankMaterialShell (DMS).

## Components

### Niri Wayland Compositor
- **Features**: Scrollable tiling, overview mode, sophisticated window rules, and custom keybindings guide.
- **Rules**: Deep integration with DMS for theming and session management.
- **Implementation**: `home/desktop/niri.nix`, `home/desktop/niri-keybinds.nix`

### DankMaterialShell (DMS)
- **Architecture**: Launched via Niri's `spawn-at-startup` mechanism (managed by the `dank-material-shell` niri module).
- **Lifecycle**: Systemd integration is explicitly disabled in `cairn` to eliminate race conditions with PipeWire/Wayland during boot.
- **Features**: Material Design shell, system monitoring, clipboard, VPN status, and dynamic theming via `matugen`.
- **Theming**: Automatic color extraction from wallpaper.
- **Implementation**: `home/desktop/default.nix`, `home/desktop/theming.nix`, `home/desktop/niri.nix`

### Personal Information Management (PIM)

**Email**: cairn-mail - AI-powered email management with local LLM classification.
- Multi-account support (Gmail OAuth, IMAP/SMTP)
- Privacy-first local processing via OpenAI-compatible API
- Modern web UI with PWA support
- Tailscale integration for cross-device access

**Calendar**: vdirsyncer + khal + PWA apps
- Automated CalDAV sync via systemd timers
- khal CLI for DMS calendar widget integration
- PWA apps for graphical interface (user's choice)

**Contacts**: Cloud provider UIs or PWA apps
- Future: cairn-mail contacts module (planned)

**Implementation**:
- `modules/pim/default.nix` (system services)
- `home/pim/default.nix` (user configuration)
- See `openspec/specs/pim/spec.md` for full documentation

### Application Management
- **PWA support**: Dedicated builder for Progressive Web Apps with configurable browser backend (Chromium, Brave, Chrome).
- **Add-PWA Script**: Automated tool (`scripts/add-pwa.sh`) that installs icons, registers manifest categories, and inserts configuration into `home/desktop/pwa-apps.nix` with auto-formatting.
- **Implementation**: `modules/desktop/default.nix`, `home/desktop/pwa-apps.nix`, `scripts/add-pwa.sh`

### Wallpaper & Theming
- **Features**: Curated collection at `~/Pictures/Wallpapers`, blurred background effects, and Base16/Dank16 support for VSCode.
- **Implementation**: `home/desktop/wallpaper.nix`, `home/desktop/theming.nix`

## Session Lifecycle Management

### Ghostty Singleton Mode
Ghostty is managed via **systemd user service** (`app-com.mitchellh.ghostty.service`) for proper lifecycle management:
- **Startup**: Automatically starts on `graphical-session.target`
- **Singleton mode**: `--gtk-single-instance=true` for instant window creation
- **Resident process**: `--quit-after-last-window-closed=false` keeps process alive for drop-down terminal
- **Zombie prevention**: Systemd handles cleanup on logout/crash (no manual pkill needed)

Performance benefits:
- **First launch**: Slow (~300ms-1s) due to GTK initialization overhead
- **Subsequent windows**: Near-instant (~10-50ms) as they reuse the existing process
- **Memory**: Shared process reduces memory usage with multiple terminals

**Implementation**: `home/terminal/ghostty.nix` (service override), NOT spawn-at-startup

### Known Upstream Stability Issues

#### DMS/Quickshell SIGSEGV at Greeter
- **Status**: Known issue, upstream dependency (quickshell)
- **Impact**: Occasional greeter session crash before login
- **Workaround**: Re-attempt login; usually succeeds on second try
- **Contributing factors**: May be exacerbated by GPU memory pressure from previous LLM inference sessions (see GPU Correlation below)

#### kded6 SIGABRT at Session Startup
- **Status**: Known issue, upstream (KDE)
- **Impact**: KDE services may not start properly on first login
- **Workaround**: Services usually recover; manual restart via `kded6` if needed

## Requirements

### Requirement: Configurable PWA Backend

The PWA system SHALL allow selecting the underlying browser engine to balance privacy, open-source compliance, and feature support (DRM, Push API). A global default can be set, and individual apps can override it.

#### Scenario: Default Configuration (Chromium)

- **Given**: User does not specify a PWA browser
- **When**: PWA apps are generated
- **Then**: `pkgs.chromium` is used as the backend
- **And**: Push notifications work out-of-the-box (standard Chromium)
- **And**: WMClass is `chrome-{domain}-Default` (Chromium uses `chrome` prefix internally)

#### Scenario: Brave Preference

- **Given**: User sets `cairn.pwa.browser = "brave"`
- **When**: PWA apps are generated
- **Then**: `pkgs.brave` is used
- **And**: WMClass is `brave-{domain}-Default`
- **And**: User accepts manual push notification configuration (per profile)

#### Scenario: Chrome Preference

- **Given**: User sets `cairn.pwa.browser = "google-chrome"`
- **When**: PWA apps are generated
- **Then**: `pkgs.google-chrome` is used
- **And**: WMClass is `chrome-{domain}-Default`

#### Scenario: Per-App Browser Override

- **Given**: User sets `cairn.pwa.apps.youtube-music.browser = "brave"`
- **And**: Global `cairn.pwa.browser` is `"chromium"`
- **When**: PWA apps are generated
- **Then**: YouTube Music uses `pkgs.brave` (Widevine DRM support)
- **And**: All other apps use `pkgs.chromium`
- **And**: Both browser packages are installed automatically

### Requirement: PWA Launcher Scripts

Each PWA SHALL have a `pwa-{appId}` launcher script on `$PATH`, decoupling keybinds and desktop entries from browser selection.

#### Scenario: Launching via keybind

- **Given**: `cairn.pwa.apps.google-messages` is defined
- **When**: User presses `Mod+G` (bound to `pwa-google-messages`)
- **Then**: Google Messages opens in the configured browser
- **And**: Changing `cairn.pwa.browser` automatically updates the launcher

#### Scenario: Desktop entry exec

- **Given**: A PWA desktop entry is generated
- **When**: User launches the app from the application menu
- **Then**: `Exec=pwa-{appId}` is used (not a raw browser command)
- **And**: The launcher respects per-app browser overrides

#### Scenario: PWA inherits browser hardware acceleration flags

- **Given**: `cairn.hardware.gpuType` is set to `"amd"` or `"nvidia"`
- **And**: `desktop.browserArgs` exposes computed acceleration flags per browser
- **When**: A PWA launcher script is generated
- **Then**: The launcher exec line includes all flags from `desktop.browserArgs` for the effective browser
- **And**: Flags appear before `--app=` in the command line
- **And**: The PWA has identical GPU acceleration behavior to launching the URL in the browser directly

#### Scenario: PWA launch without GPU configuration

- **Given**: `cairn.hardware.gpuType` is not set (null)
- **When**: A PWA launcher script is generated
- **Then**: Only base args (`--password-store=detect`) are included
- **And**: No GPU-specific flags are added

### Requirement: Browser Args Exposure

The desktop module SHALL expose computed browser command-line arguments as a read-only NixOS option (`desktop.browserArgs`) so that downstream modules (including home-manager PWA generation) can consume GPU-aware flags without duplicating detection logic.

#### Scenario: Home-manager module reads browser args

- **Given**: `desktop.enable = true`
- **And**: `cairn.hardware.gpuType = "amd"`
- **When**: `pwa-apps.nix` evaluates
- **Then**: `osConfig.desktop.browserArgs.brave` contains AMD acceleration flags
- **And**: `osConfig.desktop.browserArgs.chromium` contains the same flags
- **And**: `osConfig.desktop.browserArgs.google-chrome` contains the same flags

#### Scenario: Chromium receives acceleration flags

- **Given**: `desktop.enable = true` (previously Chromium had no flags)
- **When**: System builds
- **Then**: `programs.chromium.commandLineArgs` includes GPU acceleration flags
- **And**: Chromium (the default PWA browser) has hardware acceleration parity with Brave and Chrome

### Requirement: Centralized PWA Definition

PWA applications (PIM, Immich, generic apps) SHALL be defined via a central `cairn.pwa.apps` option to ensure consistency.

#### Scenario: Module Registration

- **Given**: `pim` module is enabled
- **When**: Configuration is evaluated
- **Then**: `pim` module sets `cairn.pwa.apps.cairn-mail`
- **And**: `desktop` module consumes this definition to generate the desktop entry and launcher
- **And**: `desktop` module applies the global or per-app browser setting

#### Scenario: Unified URL Generation

- **Given**: `immich` module is enabled (server role)
- **When**: PWA definition is created
- **Then**: URL is `https://cairn-immich.<tailnet>/` (unified via loopback proxy)
- **And**: Desktop entry uses this URL, ensuring consistent app_id across devices

### Requirement: File Manager Integration

Dolphin is configured to use Ghostty as its terminal emulator, and KDE Activities (unused in Niri) are hidden from the UI.

#### Scenario: User opens terminal from Dolphin context menu

- **Given**: User is browsing files in Dolphin
- **When**: User right-clicks and selects "Open Terminal Here" (or presses Shift+F4)
- **Then**: Ghostty opens in the selected directory
- **And**: The Ghostty window uses the singleton daemon (instant launch)

#### Scenario: User views Dolphin context menu

- **Given**: User right-clicks in Dolphin's file view
- **When**: The context menu appears
- **Then**: There is no "Activities" menu item visible
- **And**: All other standard context menu items remain functional

### Requirement: Flatpak Installation Handler

Clicking "Install" on the Flathub website triggers a transparent, terminal-based installation flow.

#### Scenario: User installs app from Flathub

- **Given**: User visits flathub.org in Brave browser
- **And**: Flatpak service is enabled
- **When**: User clicks "Install" on an application page
- **Then**: Browser downloads the `.flatpakref` file
- **And**: A small, floating Ghostty terminal window opens (not full screen) showing the flatpak install command
- **And**: User sees the application name and is prompted to confirm (y/N)
- **And**: Installation progress is visible in the terminal

#### Scenario: Flatpak installation completes

- **Given**: User confirmed the installation
- **When**: `flatpak install` completes successfully
- **Then**: Terminal displays a success message
- **And**: User presses Enter to close the terminal
- **And**: The installed application appears in the application launcher

#### Scenario: Flatpak installation fails

- **Given**: Installation fails (network error, permission issue, etc.)
- **When**: `flatpak install` exits with non-zero status
- **Then**: Terminal displays the error message from flatpak
- **And**: User can read the error and press Enter to close

### Requirement: Drop-down Terminal Identity

The drop-down terminal uses a proper Cairn app-id and does not appear in the DMS dock.

#### Scenario: User toggles drop-down terminal

- **Given**: User presses Mod+` (backtick)
- **When**: The drop-down terminal appears
- **Then**: Its app-id is `com.github.kcalvelli.cairn.dropterm`
- **And**: It does not appear as a separate icon in the DMS dock
- **And**: It floats at the top of the screen under the panel (existing behavior)

#### Scenario: User views dock with drop-down terminal open

- **Given**: The drop-down terminal is currently visible
- **When**: User looks at the DMS dock/taskbar
- **Then**: There is no icon or entry for the drop-down terminal

### Requirement: Curated Application Set

The desktop module SHALL organize applications into toggleable sub-groups, each with an independent enable option defaulting to `true`. Core desktop packages (file management, theming, launchers, system utilities, Wayland tools) SHALL always be installed when `desktop.enable = true`. Optional groups (media, office, streaming, social) SHALL be independently disableable.

#### Scenario: Default desktop installation (all sub-options true)

- **WHEN** user enables `desktop.enable = true`
- **AND** all sub-options are at their defaults (`true`)
- **THEN** the following application categories are present:
  - Core: File management (Dolphin, Ark), launchers (Fuzzel), theming, system utilities (Mousepad, lxqt-openssh-askpass, pavucontrol, ImageMagick, libnotify), Wayland tools (wtype, playerctl, slurp, swaybg)
  - Media (`desktop.media.enable`): Gwenview, Tauon, FFmpeg, wf-recorder, Swappy, Krita
  - Office (`desktop.office.enable`): LibreOffice-qt, Ghostwriter, Okular, Qalculate-qt, Filelight
  - Streaming (`desktop.streaming.enable`): OBS Studio (gamemode-wrapped), Discord
  - Social (`desktop.social.enable`): Materialgram, Spotify, Zenity
- **AND** DMS community plugins are available via `programs.dank-material-shell.plugins`
- **AND** core Niri plugins (displayManager, niriWindows, niriScreenshot, dankKDEConnect) are auto-enabled
- **AND** conditional plugins are enabled based on system module flags
- **AND** nixMonitor plugin is explicitly disabled (cairn-monitor provides this)

#### Scenario: User disables a sub-group

- **WHEN** user sets any sub-option to `false` (e.g., `desktop.streaming.enable = false`)
- **THEN** packages in that group MUST NOT be in `environment.systemPackages`
- **AND** all other desktop groups remain functional
- **AND** Elisa (Qt music player) is NOT included by default
- **AND** Haruna (Qt video player) is NOT included by default
- **AND** GStreamer packages are NOT included by default
- **AND** Database tools (DBeaver) are NOT included by default
- **AND** Heavy photo managers (DigiKam) are NOT included by default
- **AND** Vector editors (Inkscape) are NOT included by default
- **AND** File sharing tools (LocalSend) are NOT included by default
- **AND** Graphics debuggers (RenderDoc) are NOT included by default
- **AND** Tailscale tray apps (Trayscale) are NOT included by default (DMS provides VPN widget)

#### Scenario: User needs a removed application

- **GIVEN** user wants to use Elisa for music library management
- **WHEN** user adds `kdePackages.elisa` and GStreamer packages to their `extraConfig.environment.systemPackages`
- **THEN** Elisa is installed and fully functional
- **AND** user must also set `QT_MEDIA_BACKEND` and `GST_PLUGIN_SYSTEM_PATH_1_0` environment variables
- **AND** no Cairn modules need to be modified

### Requirement: Office Suite

The desktop module SHALL include LibreOffice with Qt integration for document productivity.

#### Scenario: Default desktop includes LibreOffice

- **WHEN** user enables `desktop.enable = true`
- **THEN** `libreoffice-qt` SHALL be installed
- **AND** the application SHALL inherit Qt theming from the DMS Material You theme engine
- **AND** LibreOffice Writer, Calc, Impress, and Draw SHALL be launchable from Fuzzel

#### Scenario: User opts out of LibreOffice

- **WHEN** user does not want LibreOffice installed
- **THEN** user MAY override `environment.systemPackages` in their `extraConfig` to exclude it
- **AND** no Cairn module changes are required

### Requirement: Hoppscotch Default PWA

Hoppscotch SHALL be included as a default PWA in `pkgs/pwa-apps/pwa-defs.nix`, with its icon in `home/resources/pwa-icons/`, following the same pattern as all other Cairn-shipped PWAs. Downstream user configs that previously defined Hoppscotch manually can remove their duplicate entries since Cairn defaults use `mkDefault`.

#### Scenario: Hoppscotch appears in launcher

- **WHEN** user enables `cairn.pwa.enable = true` with `includeDefaults = true` (the default)
- **THEN** a `pwa-hoppscotch` launcher script SHALL exist on `$PATH`
- **AND** a Hoppscotch desktop entry SHALL appear in Fuzzel
- **AND** the PWA SHALL use `https://hoppscotch.io/` as its URL
- **AND** the icon SHALL be sourced from `home/resources/pwa-icons/hoppscotch.png`

#### Scenario: Hoppscotch respects PWA browser configuration

- **WHEN** user sets `cairn.pwa.browser = "brave"`
- **THEN** Hoppscotch SHALL open in Brave
- **AND** the PWA SHALL inherit GPU acceleration flags from `desktop.browserArgs`

#### Scenario: Downstream override still works

- **WHEN** a user defines `cairn.pwa.apps.hoppscotch` in their user config
- **THEN** the user's definition SHALL override the Cairn default (since defaults use `mkDefault`)
- **AND** no conflict or duplicate entry SHALL occur

### Requirement: GStreamer is not included by default

**Rationale**: GStreamer causes boot instability due to glib symbol mismatches and race conditions with PipeWire. Media playback uses mpv with FFmpeg decoding instead.

#### Scenario: User needs GStreamer for specific Qt apps

- **GIVEN** user needs GStreamer for a specific Qt application
- **WHEN** user configures it manually in their `extraConfig`
- **THEN** the following packages and environment variables are required:
  ```nix
  environment.systemPackages = with pkgs; [
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
  ];
  environment.sessionVariables = {
    QT_MEDIA_BACKEND = "gstreamer";
    GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPath "lib/gstreamer-1.0" [
      pkgs.gst_all_1.gstreamer
      pkgs.gst_all_1.gst-plugins-base
      pkgs.gst_all_1.gst-plugins-good
    ];
  };
  ```

### Requirement: SSD-Consistent Application Selection

All primary desktop applications respect the compositor's `prefer-no-csd` setting. Brief utility windows (screenshot annotation, audio control) are exempt. The normie profile uses `prefer-no-csd = false`, so applications draw client-side decorations (titlebars with window controls).

#### Scenario: User opens any default application (standard profile)

- **Given**: Niri is running with `prefer-no-csd = true` (standard profile)
- **WHEN**: User opens any application from the default desktop set
- **THEN**: The application uses server-side decorations (compositor-drawn titlebar)
- **AND**: The application's appearance is visually consistent with other windows

#### Scenario: User opens any default application (normie profile)

- **Given**: Niri is running with `prefer-no-csd = false` (normie profile)
- **WHEN**: User opens any application from the default desktop set
- **THEN**: The application draws its own client-side decorations (titlebar with close/minimize/maximize)
- **AND**: GTK and Qt apps may have slightly different titlebar styles

#### Scenario: Brief utility exceptions

- **Given**: Swappy (screenshot annotation) or Pavucontrol (audio routing) is opened
- **When**: The window appears
- **Then**: CSD may be visible (these are brief utility windows)
- **And**: This is acceptable because these are transient tools, not primary work surfaces

### Requirement: Solaar autostart is hardware-conditional

Solaar autostart SHALL be determined by hardware configuration, not by profile selection. Both standard and normie profiles receive Solaar autostart when Logitech hardware support is enabled.

#### Scenario: System with Logitech support enabled

- **WHEN** `osConfig.hardware.logitech.wireless.enableGraphical` is true
- **THEN** a Solaar autostart desktop entry is created in the user's home
- **AND** Solaar launches with `--window=hide --battery-icons=solaar`
- **AND** this applies to both standard and normie profile users

#### Scenario: System without Logitech support

- **WHEN** `osConfig.hardware.logitech.wireless.enableGraphical` is false or unset
- **THEN** no Solaar autostart entry is created
- **AND** this applies to both standard and normie profile users

### Requirement: AI home modules are profile-conditional

The AI home-manager modules SHALL be imported only for profiles that include developer tooling (currently: standard). They SHALL NOT be applied universally via `sharedModules`.

#### Scenario: Standard user gets AI tools

- **WHEN** a user with `homeProfile = "standard"` is on a host with `modules.ai = true`
- **THEN** `home/ai/` modules are imported for that user
- **AND** AI tool packages, MCP configuration, and system prompts are available

#### Scenario: Normie user does not get AI tools

- **WHEN** a user with `homeProfile = "normie"` is on a host with `modules.ai = true`
- **THEN** `home/ai/` modules are NOT imported for that user
- **AND** no AI packages or configuration files are generated in their home directory
- **AND** the system-level AI NixOS module remains functional for other users

### Requirement: Init script prompts per-user profile

The init script SHALL prompt for each user's profile during user collection instead of deriving the host-level profile from form factor.

#### Scenario: Primary user profile selection

- **WHEN** the init script collects primary user information
- **THEN** it prompts for profile selection: "standard" or "normie"
- **AND** the selection is stored per-user in the generated `users/<name>.nix` file as `homeProfile = "<selection>"`
- **AND** the host-level `homeProfile` defaults to `"standard"`

#### Scenario: Additional user profile selection

- **WHEN** the init script collects an additional user
- **THEN** it prompts for that user's profile: "standard" or "normie"
- **AND** the selection is written to that user's generated config file

#### Scenario: Form factor no longer determines profile

- **WHEN** the init script detects form factor (desktop or laptop)
- **THEN** form factor is used for hardware configuration only
- **AND** form factor does NOT influence the `homeProfile` value
- **AND** the `HOME_PROFILE` derivation from form factor is removed

### Requirement: Default Text Editor

Mousepad serves as the default text editor, providing syntax highlighting and clean editing without IDE-weight features.

#### Scenario: User opens text editor via keybind

- **Given**: User presses Mod+Shift+T
- **When**: Mousepad launches
- **Then**: The window uses server-side decorations (GTK3, traditional menubar)
- **And**: Syntax highlighting works for common languages (Nix, Python, Bash, JSON, YAML, Markdown)
- **And**: The GTK theme (colloid/dank-colors) is applied consistently

#### Scenario: User needs advanced text editing

- **Given**: User needs LSP support, project management, or other advanced features
- **When**: User adds `kdePackages.kate` to their `extraConfig.environment.systemPackages`
- **Then**: Kate is installed with full KTextEditor features
- **And**: Kate inherits DankShell syntax theme if the user also installs the matugen template

### Requirement: GPU Resource Correlation Awareness

Desktop session stability correlates with GPU memory state; Cairn documents this relationship to aid troubleshooting.

#### Scenario: Login after heavy LLM inference

- **Given**: User ran large model inference before logout
- **And**: ROCm had queue evictions during the session
- **When**: User logs back in and greeter starts quickshell
- **Then**: quickshell MAY have increased crash probability
- **And**: User SHOULD know to check AI spec's GPU troubleshooting section

#### Scenario: Stable session startup

- **Given**: llama-server was stopped or no large models were loaded before logout
- **And**: No queue evictions occurred in previous session
- **When**: User logs in
- **Then**: Greeter SHOULD start normally with low crash probability

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

## Constraints
- **Wayland Compatibility**: All desktop components must be Wayland-native.
- **Spawn Order**: DMS must spawn after `dbus-update-activation-environment` to ensure session variables are available.
- **Singleton Cleanup**: Singleton applications in `spawn-at-startup` must have pre-startup cleanup commands.
- **GPU Resource Sharing**: Desktop GPU usage must coexist with AI inference; see AI spec for memory reservation guidance.

## Troubleshooting

### Frequent Quickshell Crashes at Login

If DMS/Quickshell crashes frequently at greeter startup:

1. **Check if llama-server was running heavy workloads**: `journalctl -u llama-server --since "1 hour ago" | grep -E "evict|error"`
2. **Stop llama-server before logout**: `systemctl stop llama-server`
3. **Reduce GPU layers**: Lower `services.ai.local.gpuLayers` to reduce VRAM footprint
4. **Use smaller models**: See AI spec model size guidance

If crashes persist without LLM inference correlation, this is the known upstream quickshell issue.
