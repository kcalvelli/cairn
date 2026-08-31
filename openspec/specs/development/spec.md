# Development Environment

## Purpose
Provides a comprehensive development environment with modern tools, optimized system tuning, extensible developer shells, and a full-featured neovim IDE.

## Components

### System Tuning
- **File Watchers**: `fs.inotify.max_user_watches` increased to 524,288 to support large IDE projects and hot-reloading tools (CRA, Vite, cargo-watch).
- **Implementation**: `modules/development/default.nix`

### Core Tooling
- **Editors**: Visual Studio Code (with material theme integration). Neovim provided via home-manager (`cairn.terminal.neovim.enable`), NOT the development module.
- **Languages/Runtimes**: Bun (for theme updates).
- **Shell utilities** (development module): Bat, Jq. Shell tools with home-manager `programs.*` modules (Fish, Starship, Eza, Fzf, Gh) MUST NOT be duplicated in the development module's system packages.
- **Version Control**: Git (system), GitHub CLI (home-manager `programs.gh`).
- **API/Network**: mitmproxy, k6, httpie, dog, wrangler.
- **Database**: pgcli, litecli.
- **Nix**: devenv, nil.
- **Diff**: difftastic.
- **Implementation**: `modules/development/default.nix` (system packages), `home/terminal/` (home-manager programs)

### Workflow Automation
- **Direnv/Lorri**: Automatic environment loading based on directory.
- **VSCode Server**: Support for remote development.
- **Implementation**: `modules/development/default.nix`

### Developer Shells (DevShells)
- **Profiles**: Pre-configured shells for Rust, Zig, QML, etc.
- **Access**: `nix develop .#profile-name`.
- **Neovim Integration**: Devshells set `CAIRN_NVIM_LANGUAGES` to auto-configure IDE features.
- **Implementation**: `devshells/`

## Requirements

### Requirement: Database CLI Clients

The development module SHALL include lightweight database CLI clients for interactive querying.

#### Scenario: PostgreSQL querying with pgcli
- **WHEN** user enables `development.enable = true`
- **THEN** `pgcli` SHALL be installed
- **AND** the user SHALL be able to connect to PostgreSQL databases with auto-completion and syntax highlighting

#### Scenario: SQLite querying with litecli
- **WHEN** user enables `development.enable = true`
- **THEN** `litecli` SHALL be installed
- **AND** the user SHALL be able to query SQLite databases with the same UX as pgcli

### Requirement: HTTP API Testing CLI

The development module SHALL include a modern HTTP client for API testing from the terminal.

#### Scenario: API testing with httpie
- **WHEN** user enables `development.enable = true`
- **THEN** `httpie` SHALL be installed
- **AND** the user SHALL be able to make HTTP requests with `http` and `https` commands
- **AND** response bodies SHALL be syntax-highlighted by default

### Requirement: Structural Diff Tool

The development module SHALL include an AST-aware diff tool for language-specific structural comparisons.

#### Scenario: Structural diff with difftastic
- **WHEN** user enables `development.enable = true`
- **THEN** `difftastic` SHALL be installed
- **AND** the user SHALL be able to run `difft` to compare files with language-aware structural diffing

### Requirement: System and Network Diagnostic CLI Tools

The development module SHALL include modern system monitoring and network diagnostic tools.

#### Scenario: System monitoring with btop
- **WHEN** user enables `development.enable = true`
- **THEN** `btop` SHALL be installed
- **AND** the user SHALL be able to monitor CPU, memory, disk, and network usage via the `btop` command

#### Scenario: Network path analysis with mtr
- **WHEN** user enables `development.enable = true`
- **THEN** `mtr` SHALL be installed
- **AND** the user SHALL be able to diagnose network paths combining traceroute and ping functionality

#### Scenario: DNS lookup with dog
- **WHEN** user enables `development.enable = true`
- **THEN** `dog` SHALL be installed
- **AND** the user SHALL be able to perform DNS lookups with colored, human-readable output via the `dog` command

### Requirement: Neovim IDE Preset

Cairn SHALL provide a comprehensive neovim IDE preset that delivers a productive development environment out of the box while allowing full user customization.

#### Scenario: Fresh installation with no existing neovim config
- **Given** the user has no `~/.config/nvim/init.lua`
- **When** home-manager activates
- **Then** an init.lua is generated that loads the cairn preset via `require("cairn").setup({})`
- **And** the user can edit this file to customize their experience

#### Scenario: Existing neovim configuration
- **Given** the user has an existing `~/.config/nvim/init.lua`
- **When** home-manager activates
- **Then** the existing init.lua MUST be preserved unchanged
- **And** the user can opt-in by adding `require("cairn").setup({})` to their config

#### Scenario: User customizes preset
- **Given** the user has the cairn preset loaded
- **When** they pass options to `require("cairn").setup({ colorscheme = "tokyonight" })`
- **Then** the preset MUST respect their overrides
- **And** defaults are used for unspecified options

### Requirement: LSP Auto-Configuration

The neovim preset SHALL automatically configure LSP based on language detection.

#### Scenario: Nix files (always enabled)
- **Given** the user opens a `.nix` file
- **When** the buffer is loaded
- **Then** nil_ls LSP MUST attach automatically
- **And** completion, diagnostics, and go-to-definition work

#### Scenario: Devshell language detection
- **Given** the user enters a rust devshell (`nix develop .#rust`)
- **And** `CAIRN_NVIM_LANGUAGES` is set to `"rust,toml"`
- **When** they open a `.rs` file in neovim
- **Then** rust-analyzer LSP MUST attach (using the binary from devshell PATH)
- **And** Rust-specific treesitter highlighting MUST be enabled

#### Scenario: LSP binary not found
- **Given** the user opens a `.rs` file outside a devshell
- **And** rust-analyzer is not in PATH
- **When** the buffer is loaded
- **Then** no LSP SHALL attach
- **And** a non-intrusive message SHOULD indicate rust-analyzer is not available
- **And** syntax highlighting via treesitter still works

### Requirement: AI-Powered Coding (Conditional)

AI coding features SHALL be enabled only when the system AI module is active, using avante.nvim for a Cursor-like experience.

#### Scenario: AI module enabled
- **Given** the system has `services.ai.enable = true`
- **And** `CAIRN_AI_ENABLED=1` is set in the environment
- **When** the user starts neovim
- **Then** avante.nvim MUST be available via `<leader>a` keymaps
- **And** Claude SHALL be the default AI provider

#### Scenario: AI module disabled
- **Given** the system has `services.ai.enable = false`
- **And** `CAIRN_AI_ENABLED` is not set
- **When** the user starts neovim
- **Then** avante.nvim SHALL NOT be loaded
- **And** `<leader>a` keymaps MUST NOT be registered

#### Scenario: Claude auth_type configuration
- **Given** the user configures `ai.claude.auth_type = "max"` in setup
- **When** avante.nvim initializes
- **Then** it MUST use the Claude Max subscription authentication
- **And** benefit from higher rate limits

### Requirement: Plugin Lazy-Loading

All plugins SHALL be lazy-loaded to ensure fast startup.

#### Scenario: Startup time
- **Given** a fresh neovim installation with the cairn preset
- **When** neovim starts with no file argument
- **Then** startup MUST complete in under 100ms
- **And** only essential UI plugins are loaded

#### Scenario: Plugin loading on demand
- **Given** the user has not used telescope
- **When** they press `<leader>ff` (find files)
- **Then** telescope.nvim MUST load on first use
- **And** the file picker opens

### Requirement: Discoverable Keybindings

All keybindings SHALL be documented via which-key and follow mnemonic patterns.

#### Scenario: Keybind discovery
- **Given** the user is in normal mode
- **When** they press `<leader>` and wait
- **Then** which-key popup MUST appear showing available prefixes
- **And** each prefix MUST be labeled (f=Find, g=Git, l=LSP, etc.)

#### Scenario: Keybind prefix groups
- **Given** the which-key popup is visible
- **When** the user presses `g` (git prefix)
- **Then** all git-related keybinds MUST be shown
- **And** each MUST have a description

### Requirement: Devshell Neovim Integration

Devshells SHALL configure neovim for their tech stack automatically.

#### Scenario: Rust devshell
- **Given** the user enters the rust devshell
- **When** neovim is started
- **Then** rust-analyzer LSP MUST be auto-configured
- **And** codelldb debugger MUST be available for DAP
- **And** Rust treesitter parser MUST be active

#### Scenario: Zig devshell
- **Given** the user enters the zig devshell
- **When** neovim is started
- **Then** zls LSP MUST be auto-configured
- **And** Zig treesitter parser MUST be active

## Baseline Requirements (unchanged)
- **Nix Flakes**: The entire development environment relies on Nix flakes for reproducibility.
- **Interactive Shell**: The development module automatically switches the interactive bash shell to Fish.

## Keybind Reference

| Keybind | Action | Plugin |
|---------|--------|--------|
| `<leader>ff` | Find files | telescope |
| `<leader>fg` | Live grep | telescope |
| `<leader>fb` | Buffers | telescope |
| `<leader>fh` | Help tags | telescope |
| `<leader>e` | Toggle file explorer | neo-tree |
| `<leader>gg` | Open lazygit | lazygit.nvim |
| `<leader>gd` | Diff view | diffview |
| `<leader>gb` | Git blame line | gitsigns |
| `<leader>lf` | Format buffer | LSP |
| `<leader>lr` | Rename symbol | LSP |
| `<leader>la` | Code action | LSP |
| `<leader>ld` | Diagnostics | telescope |
| `<leader>db` | Toggle breakpoint | DAP |
| `<leader>dc` | Continue | DAP |
| `<leader>ds` | Step over | DAP |
| `<leader>di` | Step into | DAP |
| `<leader>dr` | Open REPL | DAP |
| `<leader>aa` | Toggle Avante panel | avante |
| `<leader>ae` | Edit with AI | avante |
| `<leader>ar` | Refresh Avante | avante |
| `<leader>af` | Focus Avante | avante |
| `<leader>tt` | Toggle terminal | toggleterm |
| `gd` | Go to definition | LSP |
| `gr` | Go to references | LSP |
| `K` | Hover documentation | LSP |
| `[d` / `]d` | Previous/next diagnostic | LSP |
