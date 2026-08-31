# Normie Profile

## Purpose
Defines the "normie" home-manager profile — a ChromeOS-like desktop experience for non-technical users. Mouse-driven with window titlebars, DMS shelf, PWAs, and minimal keybindings. No tiling concepts, developer tools, or AI tooling exposed.

## Components

### Profile Module
- **Implementation**: `home/profiles/normie.nix`
- **Imports**: `base.nix`, `../desktop/normie.nix`
- **Does NOT import**: `../desktop` (the standard desktop module)

### Normie Desktop Module
- **Implementation**: `home/desktop/normie.nix`
- **Imports**: `theming.nix`, `wallpaper.nix`, `pwa-apps.nix`, `mpv.nix`, Niri home module, DMS home modules
- **Does NOT import**: `niri-keybinds.nix`, `cairn-monitor`, `dsearch`
- **Provides**: DMS shell, MIME associations, Flatpak setup, gnome-keyring, KDE Connect, simplified niri config

### Normie Keybindings
- **Implementation**: `home/desktop/niri-keybinds-normie.nix`
- **Scope**: Minimal set of bindings for mouse-first users

## Requirements

### Requirement: Normie profile provides ChromeOS-like desktop

The normie profile SHALL provide a mouse-driven desktop experience where all interaction is possible without learning keyboard shortcuts. Window management relies on titlebars, the DMS taskbar, and Alt+Tab.

#### Scenario: Normie user logs in

- **WHEN** a user with `homeProfile = "normie"` logs in
- **THEN** DMS shell (taskbar, notifications, clipboard) is running
- **AND** windows have client-side decorations (titlebars with close/minimize/maximize buttons)
- **AND** the keybinding help overlay (cairn-help) does NOT launch at startup
- **AND** the drop-down terminal does NOT launch at startup
- **AND** the DMS app launcher is accessible via Mod+Space or by clicking the taskbar

#### Scenario: Normie user opens an application

- **WHEN** a normie user launches an application from the DMS launcher or taskbar
- **THEN** the application opens maximized (same as standard profile)
- **AND** the application window has a titlebar with close, minimize, and maximize buttons
- **AND** the user can close the window by clicking the X button on the titlebar

#### Scenario: Normie user switches between windows

- **WHEN** a normie user has multiple windows open
- **THEN** the user can switch between them using Alt+Tab (DMS alt-tab)
- **AND** the user can switch between them by clicking on the DMS taskbar
- **AND** no workspace or tiling knowledge is required

### Requirement: Normie profile enables client-side decorations

The normie niri configuration SHALL set `prefer-no-csd = false` so that GTK and Qt applications draw their own titlebars with window controls.

#### Scenario: GTK application window decorations

- **WHEN** a normie user opens a GTK application (e.g., Brave, Dolphin file manager dialogs)
- **THEN** the application draws its own titlebar with close/minimize/maximize buttons
- **AND** the titlebar follows the GTK theme (Colloid/dank-colors)

#### Scenario: Qt application window decorations

- **WHEN** a normie user opens a Qt application (e.g., Dolphin, Okular, Qalculate)
- **THEN** the application draws its own titlebar with window controls
- **AND** the titlebar follows the Qt theme

### Requirement: Normie keybindings are minimal

The normie profile SHALL provide only essential keybindings. All other interaction is via mouse through the DMS panel.

#### Scenario: Available keybindings for normie users

- **WHEN** the normie profile keybindings are loaded
- **THEN** the following bindings are available:
  - `Mod+Q` — close focused window
  - `Mod+F` — toggle maximize column
  - `Print` — interactive screenshot
- **AND** DMS-injected bindings are available (media keys, Mod+Space launcher, Mod+N notifications, Mod+X power menu, Mod+V clipboard, Super+Alt+L lock)
- **AND** NO tiling bindings are defined (no column movement, consume/expel, focus-column-left/right)
- **AND** NO workspace navigation bindings are defined (no Mod+1-9, no Mod+U/I)
- **AND** NO developer launchers are defined (no Mod+Shift+V for VS Code, no Mod+` for drop-down terminal, no Mod+Shift+T for text editor)
- **AND** NO application launcher bindings are defined beyond DMS Spotlight (no Mod+B, Mod+D, Mod+E, Mod+G)

### Requirement: Normie profile excludes AI home modules

The normie profile SHALL NOT receive AI home-manager modules (claude-code, gemini, MCP servers, system prompts). User-facing AI applications that do not depend on the AI home-manager stack MAY still be provided when they are intentionally included as normie applications.

#### Scenario: AI tools not present for normie user

- **WHEN** a normie user's home-manager configuration is evaluated
- **THEN** `home/ai/` modules are NOT imported
- **AND** no AI tool packages are added to the user's PATH
- **AND** no `~/.mcp.json` or `~/.config/ai/` files are generated for this user
- **AND** the system-level AI module (`services.ai`) remains unchanged

#### Scenario: Normie user receives approved AI applications

- **WHEN** a normie user's home-manager configuration is evaluated
- **THEN** approved user-facing AI applications can be included without importing `home/ai/`
- **AND** those applications do not require the broader AI power-user workflow to be enabled

### Requirement: Normie profile retains core desktop features

The normie profile SHALL include the same visual polish, MIME associations, PWA apps, media playback, and approved user-facing applications as the standard profile where those applications improve the non-technical user experience.

#### Scenario: Normie user has full PWA catalog

- **WHEN** a normie user opens the DMS app launcher
- **THEN** all default PWA apps are available (Gmail, YouTube, Google Drive, ChatGPT, etc.)
- **AND** PWA desktop entries and launcher scripts are generated
- **AND** PWA icons appear in the launcher

#### Scenario: Normie user launches ChatGPT PWA

- **WHEN** the ChatGPT PWA is included for the normie workflow
- **THEN** the user can launch it from the normal application surface
- **AND** it behaves as a standalone user-facing application rather than as part of the cairn AI power-user stack

#### Scenario: Normie user opens a file

- **WHEN** a normie user double-clicks a file in Dolphin
- **THEN** the correct application opens based on MIME type (same associations as standard profile)
- **AND** PDFs open in Okular, images in Gwenview, videos in mpv, etc.

#### Scenario: Normie user has themed desktop

- **WHEN** a normie user's session is active
- **THEN** the GTK theme (Colloid), cursor (Bibata), and Qt theme are applied
- **AND** the wallpaper and dynamic theming (matugen) are active
- **AND** the DMS shell uses Material Design theming

### Requirement: Normie profile includes Solaar when hardware is present

The normie profile SHALL autostart Solaar for Logitech device management when the system has Logitech hardware support enabled.

#### Scenario: Normie user on system with Logitech hardware

- **WHEN** `osConfig.hardware.logitech.wireless.enableGraphical` is true
- **AND** the user has `homeProfile = "normie"`
- **THEN** Solaar autostarts with `--window=hide --battery-icons=solaar`

#### Scenario: Normie user on system without Logitech hardware

- **WHEN** `osConfig.hardware.logitech.wireless.enableGraphical` is false or unset
- **AND** the user has `homeProfile = "normie"`
- **THEN** Solaar does NOT autostart
