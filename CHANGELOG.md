# Changelog

All notable changes to Cairn will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Calendar Versioning](https://calver.org/) (YYYY-MM-DD format).

## [v2026.05.18] - 2026-05-18

A small maintenance release. The overview-blur effect got handed back to DMS now that it does it natively, cairn-mail got a round of fixes and finished its rebrand, and a Cachix substituter means the next hipblaslt build won't eat an evening. No breaking changes — downstream configs need no updates.

### Changed

- **Overview blur is now DMS-native.** The old pipeline — ImageMagick baking a blurred JPEG on every wallpaper change, `swaybg` painting it, and a hand-written niri `layer-rule` to push it into the overview backdrop — is gone. DMS now renders its own `dms:blurwallpaper` shader-blurred backdrop and generates the `place-within-backdrop` rule itself (Cairn already pulled that include in via `wpblur`). A new `cairn.wallpapers.overviewBlur` option (bool, default `true`) seeds the DMS `blurredWallpaperLayer` setting exactly once via a marker sentinel, then hands ownership to the DMS GUI — toggle it off in DMS and it stays off across rebuilds. For the default case the behavior is unchanged: blur was on, blur stays on, just lighter (no ImageMagick, no `swaybg` process, no cached JPEG) and live-tracking instead of lagged behind a hook.

  **One-time cost for existing live sessions:** the first rebuild after this lands flips the DMS setting live, and DMS's blur layer does not render correctly until the shell restarts. Log out and back in once; it is correct from then on and on every subsequent boot. Fresh installs are unaffected. This is deliberately not papered over by restarting the shell from a home-manager activation.

### Fixed

- **cairn-mail**: several fixes, plus the tail end of the `axios-ai-mail` → `cairn-mail` rebrand.

### Infrastructure

- Added the `nix-community` Cachix substituter so `hipblaslt` and friends come from cache instead of a ~10-hour local ROCm build.
- Routine flake input updates.

## [v2026.05.01] - 2026-05-01

A consolidation release. The distro got a real name, the local LLM stack got a sensible engine, the AI and browser firehose got shut off by default, and cairn-companion finally landed as a first-class module. After this, the intent is to slow down — fewer drive-by changes, more time to bake.

### ⚠️ BREAKING CHANGES

- **Rename: axiOS → Cairn (full distribution rebrand).**
  Every reference to `axios` / `axiOS` — option namespaces, package names, branding strings, environment variables, desktop app IDs, directory names, resource files, documentation, and URLs — has been renamed to `cairn`. The branded form `axiOS` becomes simply `Cairn`. 261 files touched across the entire base distro.

  Downstream configs need to be updated for:
  - **Option paths**: `axios.system.*` → `cairn.system.*`, `axios.users.*` → `cairn.users.*`, `axios.hardware.*` → `cairn.hardware.*`, etc.
  - **Flake input names**: `axios.url = "github:kcalvelli/axios"` → `cairn.url = "github:kcalvelli/cairn"`. Sibling repos (`axios-ai-mail`, `axios-dav`, `axios-companion`) renamed to `cairn-mail`, `cairn-dav`, `cairn-companion`.
  - **Tailscale service names**: `axios-ollama.<tailnet>.ts.net` → `cairn-llama.<tailnet>.ts.net`, `axios-mcp-gateway` → `cairn-mcp-gateway`, `axios-mail` → `cairn-mail`.
  - **Environment variables**: any `AXIOS_*` consumed externally is now `CAIRN_*`.

  The old `axios` repository will continue to exist as a forwarding stub.

- **Replace Ollama with llama.cpp** for local LLM inference. `services.ai.local` now drives a `llama-server` systemd unit instead of an Ollama daemon. GGUF models are loaded directly from disk — there is no pull/keep-alive lifecycle.

  Option changes under `services.ai.local`:
  - `models = [ ... ]` (list of pull names) → `model = "/path/to/model.gguf"` (single GGUF path, required when `local.enable = true`)
  - **Removed**: `keepAlive`, `rocmOverrideGfx` (GPU detection now flows from `cairn.hardware.gpuType`; ROCm override is set internally)
  - **Added**: `contextSize` (default `32768`), `gpuLayers` (default `-1` for all layers), `extraArgs` (pass-through list to `llama-server`)
  - Tailscale service renamed: `axios-ollama` → `cairn-llama`
  - Client environment variable: `OLLAMA_HOST` → `LLAMA_API_URL`

  Use `nix run .#download-llama-models` to fetch GGUFs into `/var/lib/llama-models/` before pointing `services.ai.local.model` at one.

- **AI tool ecosystems are now opt-in.** Setting `services.ai.enable = true` no longer drags in every coding agent on Earth. The only unconditional package is `whisper-cpp`. Per-vendor flags now default to `false`:
  ```nix
  services.ai = {
    enable = true;
    claude.enable   = true;   # claude-code, claude-desktop, claude-code-router, claude-monitor
    gemini.enable   = true;   # gemini-cli, antigravity
    openai.enable   = true;   # codex (Deno-heavy, slow first build)
    workflow.enable = true;   # spec-kit, openspec
  };
  ```
  `claude-monitor` moved under `claude.enable`. `spec-kit` and `openspec` moved out of the base AI bundle and behind the new `workflow.enable` flag.

- **Browser selection is now explicit.** `modules.desktop = true` no longer installs three browsers. Only Brave stable defaults on; everything else opts in:
  ```nix
  desktop.browsers.brave.enable        = true;   # default
  desktop.browsers.braveNightly.enable = true;   # opt-in
  desktop.browsers.braveBeta.enable    = true;   # opt-in
  desktop.browsers.braveOrigin.enable  = true;   # opt-in (new experimental Brave channel)
  desktop.browsers.chrome.enable       = true;   # opt-in
  ```
  Chromium is no longer installed as a standalone browser — it remains an implicit PWA backend with the GPU-aware command-line args plumbed in.

### Added

- **Companion module** (`modules/companion/`, `home/companion/`).
  cairn-companion is now a first-class Cairn module instead of a manual flake-input dance. Setting `modules.companion = true` wires the NixOS module (Syncthing-based persona memory sync) and auto-imports the home-manager module (daemon, CLI, TUI, spokes, channels) for standard-profile users. Downstream configs can drop their own `cairn-companion` flake input.

- **Bluetooth refinement** (`cairn.system.bluetooth`).
  - `powerOnBoot` (default `true`) — automatically power on Bluetooth adapters at boot.
  - `disableSeatMonitoring` (default `false`) — disable WirePlumber's bluez seat monitor. Use this on headless boxes where there is no active logind seat (otherwise the bluez monitor never starts).
  - The module also unconditionally disables bluetoothd's HFP/HSP profiles so PipeWire's native Bluetooth backend owns the headset codec, eliminating the long-standing profile fight that made Bluetooth headsets randomly drop into garbage SCO.

- **`linger` option for the user submodule.** `cairn.users.users.<name>.linger` enables systemd lingering so user services keep running after logout and start at boot. Useful for cairn-companion, syncthing-as-user, and anything else that should survive a console logout.

- **Greeter group + fprintd** for laptop hosts. Desktop users get added to the greeter group and laptops pick up `fprintd` so fingerprint readers Just Work.

- **`networking.nameservers` MulticastDNS** is now enabled in the global networking module so `<host>.local` resolution works without per-host fiddling.

- **MCP gateway routing via Tailscale Service.**
  - New `services.ai.mcp.gatewayUrl` is the single source of truth for the gateway base URL. Server hosts default to `http://127.0.0.1:<port>`; client hosts default to `https://cairn-mcp-gateway.<tailnet>.ts.net`. Both home-manager (`mcp_servers.json`) and the user environment (`MCP_GATEWAY_URL`) read this value.
  - Client-role hosts no longer try to spawn local stdio MCP children for PIM tools (mail, DAV) that have no local backend; they get a unified HTTP entry pointed at the remote gateway.

- **Brave Origin channel** is supported via the `brave-browser-previews` flake input.

### Changed

- **claude-code packaging**: `claude-code-bin` was merged into `claude-code` upstream in nixpkgs. Cairn now consumes the unified `claude-code` package (no more `-bin` suffix, no more `npm install` at build time).

- **OpenSpec workflow**: cairn now consumes `openspec` from its flake input instead of building from source.

- **MCP server set**: Servers that duplicate Claude's native capabilities were removed from the gateway config. `brave-search` was re-added after the dust settled. New MCP tools shipped via `cairn-dav` and `cairn-mail` updates.

- **Calamares installer branding** updated end-to-end: axiOS strings, URLs, image references, and the QML config page (`notesqml@axiosconfig.qml` → `notesqml@cairnconfig.qml`, which fixes a latent bug where the cairn-config page wasn't appearing). The unused `axios-logo.svg` placeholder is gone.

- **Logo assets**: Logo images removed from `README.md`. Cairn mark in `docs/` had a stray Gemini sparkle watermark scrubbed out.

- **Discord** is now `vesktop` (native Wayland, working screen share, Material You theming, Vencord baked in).

- **Starship prompt** configuration cleaned up.

### Fixed

- **`cli-helpers` package** (`pgcli`, `litecli`): broken Python interpreter override fixed; tests skipped where they hang in the Nix sandbox; correct use of `doInstallCheck` rather than `doCheck`. These together unbroke the `development` module on a clean build.
- **`fastmcp`** test suite skipped — it hangs indefinitely under sandbox isolation. Unblocks the `cairn-dav` rebuild.
- **`deno`** test suite skipped — TTY assertion fails inside the Nix sandbox. Unblocks the `codex` build chain.
- **Neovim** adopts the new `withRuby` / `withPython3` defaults from upstream (no more deprecation warnings on rebuild).
- **`defaults.nix` rename to `default.nix`** in `home/profiles/` — corrects a broken import that snuck through earlier.
- **kded6 service**: added `After=graphical-session.target` so it stops racing the session it depends on.
- **vdirsyncer issue** in `cairn-dav` resolved upstream and pulled in via flake bump.

### Removed

- **Ollama** inference stack (superseded by llama.cpp).
- **`services.ai.local.keepAlive`**, **`services.ai.local.rocmOverrideGfx`** options.
- Old axiOS branding assets (Calamares SVG placeholder, etc.).

### Migration

```nix
# Before
services.ai.enable = true;
# (got claude-code, gemini-cli, codex, openspec, spec-kit, claude-monitor, ...)
services.ai.local.models = [ "mistral:7b" ];

# After
services.ai = {
  enable = true;
  claude.enable   = true;
  gemini.enable   = true;
  openai.enable   = true;     # only if you actually use Codex
  workflow.enable = true;     # if you use openspec / spec-kit
  local = {
    enable      = true;
    model       = "/var/lib/llama-models/mistral-7b-instruct-v0.3.Q4_K_M.gguf";
    contextSize = 32768;
    gpuLayers   = -1;
  };
};

# Brave Nightly / Chrome no longer installed by default:
desktop.browsers.braveNightly.enable = true;
desktop.browsers.chrome.enable       = true;

# All `axios.*` option paths and Tailscale service names rename to `cairn.*` / `cairn-*`.
# All `kcalvelli/axios*` flake inputs rename to `kcalvelli/cairn*`.
```

After rebuilding, log out and back in for `LLAMA_API_URL` and `MCP_GATEWAY_URL` to refresh in the user environment.

---

## [v2026.03.30] - 2026-03-30

### Changed
- Replace Discord with `vesktop` for native Wayland, working screen share, and Material You theming.
- Greeter group added for desktop users; `fprintd` added on laptop form factor.
- DMS update with greeter and window-rules settings; flake inputs refreshed.

### Fixed
- `claude-code-acp` and `claude-code-router` made conditional on nixpkgs availability, then restored as direct deps when upstream caught up.
- AI module: properly handle hyphenated package names.
- `electron_39` → `electron_38` pin removed once upstream patch landed.
- `wivrn` module updated for upstream `defaultRuntime` removal.
- Neovim activation: clean up `init.lua.hm-backup` files; use `verboseEcho` rather than the removed `verbose`.
- Git signing format set to `null` to silence deprecation warning.

## [v2026.03.10] - 2026-03-10

### Added
- **Desktop sub-option toggles**: `desktop.media`, `desktop.office`, `desktop.streaming`, `desktop.social` for finer-grained control over what gets installed alongside the compositor.
- `MCP_GATEWAY_URL` set on client-role machines.
- `mcp-gw` CLI shipped via mcp-gateway.

### Changed
- Removed redundant package installs across modules (the same packages were being added in two or three places).
- Removed redundant MCP servers from gateway config (servers Claude already provides natively).
- `nix-devshell-mcp` flake input dropped — wasn't earning its keep.

### Fixed
- Neovim: removed colorscheme management from cairn preset so DMS's base16 colorscheme actually applies; removed global `lazy = true` default that prevented the colorscheme from loading; user plugin specs imported from `lua/plugins/`.
- Qt 6.10 PipeWire audio backend crash worked around.
- `printing.nix`: added `cairn.system.printing.enable` (default `true`) so headless boxes can disable CUPS.
- `graphics/default.nix`: GPU diagnostic tools wrapped in `lib.mkIf (gpuType != null)` so they're only installed when there's a GPU configured.

## [v2026.03.07] - 2026-03-07

### Added
- **Calamares installer integration**: full graphical installer flow for live ISO with cairn-config QML page, hardware confirmation, and first-boot wizard.
- First-boot wizard (`home/first-boot/`) — runs on first login on freshly-installed systems.
- Default normie apps replace stock NixOS ISO apps in the live environment.
- Brave-search MCP server re-added.

### Changed
- Switched from on-the-fly nodejs/npm to `claude-code-bin` (downloading npm dependencies during a Nix build is no one's idea of fun).
- MulticastDNS enabled globally in networking config.
- Stale Cachix references removed from project docs.

### Fixed
- A long string of Calamares fixes: Wayland vs XWayland startup, Qt platform plugin selection, software rendering for VMs, hostname field, broken pre-baked `flake.lock`, missing icon themes in live ISO, generic example tailnet domain in scripts, raw `TextInput` instead of `TextField` for tailnet, etc.
- `pkexec` removed from `nixos-install` (dialog spam).

## [v2026.01.13] - 2026-01-13

Major release with 329 commits over 33 days. Includes new PIM and C64 modules, enhanced PWA workflow, and major desktop refinements.

### ⚠️ BREAKING CHANGES

- **MCP Secrets Management Removed**: `services.ai.secrets` options have been removed. Users must now configure API keys via `environment.sessionVariables`:
  ```nix
  environment.sessionVariables = {
    BRAVE_API_KEY = "your-api-key";
    GITHUB_TOKEN = "ghp_your-token";  # Optional, gh CLI handles this
  };
  ```

### Added

#### New Modules

- **PIM Module** (`modules/pim/`)
  - New dedicated module for Personal Information Management
  - Geary email client integration
  - GNOME Calendar and Contacts with GNOME Online Accounts integration
  - vdirsyncer for calendar/contact syncing
  - Supported backends: Gmail, IMAP/SMTP, CalDAV, CardDAV
  - **Note**: Outlook/Office365 integration currently not working
  - Uses Evolution Data Server (lightweight D-Bus service) without requiring full GNOME desktop
  - Enable via `modules.pim = true`

- **C64/Ultimate64 Integration** (`modules/c64/`)
  - Full support for Commodore 64 and Ultimate64 hardware
  - c64-stream-viewer: Real-time video/audio streaming from Ultimate64 hardware
  - c64term: Terminal emulator with authentic PETSCII colors and boot screen
  - ultimate64-mcp: MCP server for AI-driven control (file transfer, program execution)
  - Niri window rules for C64 applications
  - Enable via `modules.c64 = true`

#### AI & MCP Enhancements

- **System Prompts for AI Agents**
  - Comprehensive cairn system prompt (auto-injected into Claude Code)
  - MCP server usage guides for AI agents
  - Dynamic tool discovery with mcp-cli documentation
  - Per-tool enablement (claude.enable, gemini.enable)
  - Unified AI coding experience
  - Custom instructions support via `~/.config/ai/prompts/cairn.md`
  - Auto-injection into `~/.claude.json` during home-manager switch

- **MCP Examples**
  - Comprehensive MCP server configuration examples (`home/ai/mcp-examples.nix`)
  - 100+ ready-to-use server configurations
  - Examples for Notion, Slack, Jira, PostgreSQL, SQLite, Docker, and more

#### Desktop & PWA Enhancements

- **Enhanced PWA Workflow**
  - `add-pwa` script now auto-updates configuration
  - Auto-format with `nix fmt` after insertion
  - Smart insertion detection for cairn project structure
  - Auto-sanitize manifest categories to Freedesktop standards
  - Improved icon fetching with better quality and transparency handling
  - 20+ PWA icons updated (Google suite, productivity apps)
  - Added new PWAs: Linear, Notion, Figma, Excalidraw, Flathub

- **Desktop Refinements**
  - Major Niri/KDE interoperability fixes (xdg-portals, kdialog, file choosers)
  - Dedicated keybindings guide (`home/desktop/niri-keybinds.nix`)
  - Improved window rules for various applications
  - Enhanced DMS outputs.kdl configuration
  - Mouse wheel bindings for column navigation
  - Fixed Qt platform environment variables
  - Portal configuration for KDE file choosers

#### Gaming & Graphics

- **Gaming Module Enhancements**
  - Binary compatibility via nix-ld for native Linux games
  - SDL2 family libraries (SDL2_image, SDL2_mixer, SDL2_ttf)
  - Graphics APIs (libGL, vulkan-loader)
  - Audio libraries (alsa-lib, openal, libpulseaudio)
  - Fixes "library not found" errors for indie games, Unity, MonoGame

- **Desktop Module**
  - USB device permissions for game controllers (Sony, Microsoft, Nintendo, Valve)
  - Normal users can access USB devices without root
  - Also benefits Arduino, dev boards, USB peripherals

- **Graphics Module**
  - vulkan-tools (vulkaninfo, vkcube) for all GPU types
  - Helps users verify GPU setup and debug graphics issues

#### Development

- **Development Module**
  - Inotify tuning for file watchers (fs.inotify.max_user_watches = 524288)
  - Fixes "ENOSPC: System limit for number of file watchers reached"
  - Critical for VS Code, Rider, WebStorm, hot-reload workflows

### Fixed

- **Graphics Module (Critical)**
  - Fixed nvidia/intel GPU support (was broken, AMD-only prior to this release)
  - Added missing `services.xserver.videoDrivers = ["nvidia"]` (critical for Nvidia to work!)
  - Added hardware.nvidia.nvidiaSettings and nvidia-settings package
  - Added power management defaults (disabled by default per NixOS wiki)
  - Graphics module now conditionally applies GPU-specific configuration:
    - AMD: radeontop, corectrl, amdgpu_top, HIP_PLATFORM
    - Nvidia: nvtopPackages.nvidia, nvidia-settings, proper driver loading
    - Intel: intel-gpu-tools, intel-media-driver
    - Common packages (clinfo, wayland-utils, vulkan-tools) available for all GPU types

- **Desktop**
  - Portal configuration for KDE file choosers
  - Numerous Niri window rules and keybindings fixes
  - Icon and desktop entry corrections
  - Fixed clipboard functionality with manual wl-paste spawn
  - Prevented duplicate DMS spawning with systemd service configuration

- **Scripts**
  - Improved robustness and error handling in add-pwa
  - Better edge case handling in configuration scripts

### Changed

- **AI Tools**
  - Removed copilot-cli (focus on Claude Code and Gemini CLI)
  - MCP secrets now configured via environment variables instead of agenix
  - Simplified MCP configuration for easier setup

- **Hardware Configuration**
  - New `hardwareConfigPath` option replacing `diskConfigPath` (backward compatible)
  - Init script now copies complete hardware-configuration.nix
  - Prevents missing VirtIO modules and boot configuration issues

### Documentation

- **Consolidated MCP Documentation**
  - Created comprehensive `docs/MCP_GUIDE.md` (complete setup and usage)
  - Created `docs/MCP_REFERENCE.md` (quick command reference)
  - Removed 6 redundant MCP documentation files
  - Clearer navigation and reduced duplication

- **New Documentation**
  - Added `docs/PWA_GUIDE.md` - Progressive Web Apps guide
  - Added `docs/MODULE_REFERENCE.md` - Complete module reference
  - Added `docs/APPLICATIONS.md` - Application catalog
  - Merged `docs/hardware-quirks.md` into `docs/TROUBLESHOOTING.md`

- **Migrated to OpenSpec SDD**
  - Moved from monolithic `spec-kit-baseline` to modular `openspec/`
  - Integrated delta-based development workflow
  - Updated AI agent instructions for spec-driven development
  - Documented C64/Ultimate64 module across all baseline files
  - Documented PIM module architecture and features
  - Updated MCP secrets management documentation
  - Added graphics module fixes and troubleshooting
  - Added system prompts architecture documentation
  - Updated hardware configuration pattern documentation

### Migration Guide

**For users with Brave Search or other MCP servers requiring API keys:**

Old configuration (no longer works):
```nix
services.ai.secrets.braveApiKeyPath = config.age.secrets.brave-api-key.path;
```

New configuration:
```nix
environment.sessionVariables = {
  BRAVE_API_KEY = "your-api-key";
};
```

**Note**: Log out and log back in after rebuilding for environment variables to take effect.

## [2025-12-11] - VM Support & Hardware Configuration Fix

### Added
- **Hardware Configuration Support**
  - Added `hardwareConfigPath` option for full hardware configuration
  - Init script now copies complete `hardware-configuration.nix` instead of extracting parts
  - Includes boot modules, kernel modules, filesystems, and swap in one file
  - Fixes VM boot failures caused by missing VirtIO kernel modules
  - Fixes boot issues on exotic hardware requiring specific kernel modules

### Changed
- **Init Script**
  - Simplified hardware config generation by copying full file instead of filtering
  - Renamed generated file from `disks.nix` to `hardware.nix` (clearer naming)
  - Removed complex AWK extraction logic that missed critical boot configuration
  - Updated templates to use `hardwareConfigPath` instead of `diskConfigPath`

### Fixed
- **VM Installation**
  - Fixed emergency boot in VMs due to missing VirtIO kernel modules
  - Fixed boot failures on hardware requiring specific initrd kernel modules
  - Documentation previously claimed kernel modules were extracted, but they weren't

### Documentation
- **Migration Guide**
  - Added comprehensive migration guide from `diskConfigPath` to `hardwareConfigPath`
  - Documented backward compatibility (both options supported)
  - Clarified UEFI-only requirement for Cairn (BIOS/MBR not supported)
  - Updated all examples and templates to use new `hardwareConfigPath`

### Backward Compatibility
- **No Breaking Changes**
  - `diskConfigPath` still works (legacy support maintained)
  - Existing configurations continue to work unchanged
  - Migration is optional but recommended

## [2025-12-04] - Idle Management & Comprehensive Documentation

### Added
- **Idle Management**
  - Implemented swayidle-based automatic screen power management
  - Default 30-minute timeout to power off monitors via `niri msg action power-off-monitors`
  - Managed via systemd user service (auto-starts with desktop session)
  - Fully configurable via home-manager `services.swayidle.timeouts`
  - Manual lock available via Super+Alt+L (DMS lock screen keybind)
- **Documentation**
  - Created comprehensive `docs/APPLICATIONS.md` with complete 80+ app catalog
  - Organized by category: desktop, development, terminal, gaming, virtualization, AI
  - Added application count summary and finding applications guide
  - Added PWA configuration examples

### Changed
- **Desktop Module**
  - Enhanced DankMaterialShell feature documentation
  - Added window rules for Brave picture-in-picture mode
  - Added window rules for DMS settings window
  - Fixed clipboard functionality with manual wl-paste spawn
  - Prevented duplicate DMS spawning with systemd service configuration
- **Documentation Overhaul**
  - Rewrote AI module documentation with two-tier architecture
  - Documented local LLM stack (Ollama, OpenCode)
  - Added ROCm acceleration details and 32K context window information
  - Expanded DankMaterialShell features (10+ specific features listed)
  - Added library philosophy section explaining design principles
  - Updated README with accurate application counts
  - Added comprehensive MCP server documentation

### Fixed
- **Desktop**
  - Restored clipboard functionality after DMS systemd service migration
  - Fixed duplicate DMS instance spawning
  - Optimized polkit agent configuration (consolidated to DMS built-in)

## [2025-11-21] - Immich 2.3.1 Custom Package

### Added
- **Custom Immich Package**
  - Added complete Immich 2.3.1 derivation in `pkgs/immich/`
  - Fixes critical rendering loop bug from version 2.2.3
  - Includes corePlugin manifest for workflow capabilities
  - Proper pnpmDeps hash for reproducible builds
  - Will be removed once nixpkgs updates to 2.3.1+

### Fixed
- **Immich Service**
  - Fixed browser freeze caused by new version notification rendering loop
  - Fixed 502 error from missing corePlugin manifest.json
  - Fixed externalDomain configuration for proper web app connectivity
  - Service now starts reliably and web app works correctly
- **Desktop Module**
  - Removed deprecated `programs.file-roller.enable` option
  - Added file-roller directly to system packages

### Changed
- Updated Immich service to use custom package from `pkgs.immich`
- Simplified Immich module by removing failed override attempts

## [2025-11-19] - DMS Integration & Upstream Module Architecture

### Changed
- **DankMaterialShell Integration**
  - Updated to DMS v0.6.2 with new NixOS module architecture
  - Removed dms-cli input (DMS now packages dmsCli directly)
  - Moved DMS NixOS modules to baseModules in lib/default.nix
  - Auto-detect greeter configHome from cairn.user.name
  - Removed 9 redundant packages now provided by DMS:
    - wl-clipboard, cava, hyprpicker, matugen, qt6ct
    - Fonts: fira-code, inter, material-symbols
    - khal (calendar)
  - Removed redundant wl-paste clipboard spawn (DMS provides this)

### Added
- **PWA Module**
  - Added extensible PWA module for custom progressive web apps
  - Users can add custom PWAs with their own URLs and icons

### Fixed
- Added required tailscale domain to server example config
- Fixed duplicate DMS module import causing option declaration errors
- Enabled DMS NixOS module for system packages (matugen, hyprpicker, cava)
- Set quickshell package at NixOS level for proper theme worker operation

### Removed
- Removed dgop input (DMS now manages its own)

## [2025-11-13] - MCP Integration & Home Module Architecture

### Added
- **MCP Server Enhancements**
- Integrated nix-devshell-mcp server for Nix development environment management
- **AI Tools Expansion**
- Added Google Jules CLI via npm
- Added Gemini CLI and integration
- Added Claude Desktop and additional Claude tools
- Added Claude usage monitoring to AI module
- Added Claude Code project context file (CLAUDE.md)

### Changed
- **Module Architecture Refactoring**
- Implemented CODE_REVIEW.md recommendations for home module architecture
- Added cairn.system.enable option with mkIf guards for consistency
- Moved browser and calendar modules to desktop.enable conditional loading
- Fixed AI module to follow conditional import pattern at system level
- Cleaned up base profile to include only core tools (security, terminal)
- **AI Module Restructuring**
- Migrated from mcpo to mcp-servers-nix library for declarative MCP configuration
- Removed ollama and open-webui from AI module (these were overly opinionated for a library)
- Renamed 'code' from nix-ai-tools to 'coder' to avoid VSCode conflict
- Removed overlapping AI CLI tools, retained only essentials
- Removed spec-kit devshell, integrated spec-kit from nix-ai-tools
- **Dependency Updates**
- Updated flake inputs for latest features and fixes

### Fixed
- **AI Module Fixes**
- Fixed MCP server package names from mcp-servers-nix
- Enabled programs.claude-code module for proper MCP configuration
- Fixed brave-search to use npx for execution
- **Build System Fixes**
- Fixed deprecated system references to use stdenv.hostPlatform.system
- **Configuration Fixes**
- Fixed age identityPaths to use absolute paths
- **Home Module Fixes**
- Fixed AI module conditional loading (removed from base.nix)
- Fixed home module import paths after restructuring

### Removed
- **AI Module Cleanup**
- Removed mcp-chat custom package (experimental tool no longer needed)
- Removed ollama module (overly opinionated for a library distribution)
- Removed open-webui module (overly opinionated for a library distribution)

### Documentation
- Enhanced GEMINI.md with project overview and workflow improvements
- Added comprehensive CODE_REVIEW.md implementation documentation
- Updated documentation for new MCP server integrations

## [2025-11-08.1] - Theming & VSCode Integration Improvements

### Added
- **DankMaterialShell Enhancements**
- Added DankHooks plugin for enhanced functionality
- Integrated dsearch (DankMaterialShell search) feature
- Added VSCode extension registration system
- Implemented Base16 color scheme support for VSCode (Dank16)
- Added wallpaper-changed.sh script integration

### Changed
- **Theming Improvements**
- Simplified theming documentation for better clarity
- Disabled Material Code theme as DMS default
- Reverted to simple plugin installation per documentation
- Allow users to modify plugin settings via GUI
- Made Base16 VSCode extension files writable for proper detection

### Fixed
- Added config parameter to function signature in theming module
- Fixed wallpaper script path to reference deployed location in user home directory
- Removed material-code theme update from wallpaper hook (refactored approach)

## [2025-11-08] - Desktop Consolidation & Module Cleanup

### Added
- **Containers Module Enhancements**
- Added Docker alongside Podman (Winboat requires Docker)
- Added Winboat and FreeRDP packages
- Automatic docker group membership for all normal users when containers enabled
- **Virtualization Improvements**
- Added dynamic ownership configuration for libvirt/QEMU
- Fixed permission denied errors when accessing ISO files in user directories
- Added polkit support for better user permissions

### Changed
- **Major Module Refactoring**
- Consolidated `wayland` and `niri` home modules into unified `desktop` module
- Merged `wayland-theming` and `wayland-material` into single `desktop/theming.nix`
- Consolidated `modules/wayland` into `modules/desktop`
- Moved DankMaterialShell configuration to desktop default.nix
- **AI Module Restructuring**
- Separated ollama and open-webui into independent modules
- Merged caddy.nix into open-webui.nix (co-located with service it supports)
- Consolidated packages.nix into AI module default.nix
- Added separate enable options: `services.ai.ollama.enable` and `services.ai.openWebUI.enable`
- **Code Quality**
- Removed all unused code detected by deadnix (27 files cleaned up)
- Fixed deprecated NixOS options (qemuVerbatimConfig → qemu.verbatimConfig)
- Removed deprecated OVMF configuration (now included by default)

### Fixed
- Restored required `config`, `osConfig`, and `inputs` to secrets module
- Fixed duplicate gnome-keyring.enable definition in desktop module
- Corrected import paths in profile modules (./profiles/base.nix → ./base.nix)
- Added required `cairn.system.timeZone` to example configurations
- Fixed init app missing meta.description attribute

### CI/CD
- Removed fragile validation tests (too many breaking changes during active development)
- Updated example configurations to work with new module structure
- Simplified GitHub Actions to focus on flake structure validation

### Documentation
- Updated examples to reflect new desktop module structure
- Improved inline documentation for module organization
- Added clear comments about UEFI/OVMF being available by default

## [2024-XX-XX] - Initial Release

Initial release of Cairn as a NixOS library.

### Added
- Core library API with `mkSystem` function
- System modules: system, desktop, development, graphics, networking, services, users, virtualization
- Home modules: wayland, workstation, laptop, AI tools
- Hardware support for AMD/Intel CPUs, AMD/Nvidia GPUs, System76/MSI hardware
- Niri compositor with DankMaterialShell integration
- AI module with Ollama, OpenWebUI, and Claude Code support
- Interactive config generator (`nix run github:kcalvelli/cairn#init`)
- Comprehensive documentation and examples
- CI/CD with automated testing and binary cache

---

## Versioning Policy

Cairn follows [Calendar Versioning (CalVer)](https://calver.org/) using **YYYY-MM-DD** format.

### Version Format

Releases are dated by when they were released:
- **2025-11-04**: Release on November 4, 2025
- **2025-12-15**: Release on December 15, 2025

### Release Cadence

Cairn doesn't follow a fixed schedule. New releases when:
- Significant features are added
- Important bug fixes accumulate
- Breaking changes are necessary (rare)

### Breaking Changes

Breaking changes are avoided when possible and clearly documented:
- Renaming or removing exported modules (e.g., `flake.nixosModules.*`)
- Changing `mkSystem` API parameters or behavior
- Removing or renaming module options users might reference
- Changing default behaviors that affect user systems

### Non-Breaking Changes

Internal improvements that don't affect user configs:
- Internal module refactoring (implementation details)
- Adding new modules or options
- Improving error messages or validation
- Documentation updates
- Performance improvements
- Bug fixes that restore intended behavior

---

**See Also**: [MIGRATION_GUIDE.md](docs/MIGRATION_GUIDE.md) for detailed upgrade instructions
