## ADDED Requirements

### Requirement: Grok CLI packaging

Cairn SHALL provide the xAI Grok CLI as a Nix-packaged prebuilt binary (`pkgs/grok-cli`) that pins a specific version and content hash, rather than relying on the upstream `curl | bash` installer. The package SHALL expose both the `grok` and `agent` entrypoints that upstream ships, mark itself `license = unfree` with `binaryNativeCode` provenance, and target `x86_64-linux`.

#### Scenario: Package builds reproducibly from a pinned artifact

- **WHEN** the `grok-cli` package is built
- **THEN** the binary is fetched via `fetchurl` from the pinned `grok-build-public-artifacts` GCS URL with a fixed sha256
- **AND** `autoPatchelfHook` resolves its runtime library dependencies against the nix store
- **AND** no network access or in-place self-update occurs at build or first run

#### Scenario: Both entrypoints are available

- **WHEN** the package is installed and on PATH
- **THEN** both `grok` and `agent` commands resolve to the packaged binary
- **AND** `grok --version` reports the pinned version

### Requirement: Grok CLI enablement under services.ai

The `services.ai` module SHALL provide a `services.ai.xai.enable` option, mirroring the existing per-tool toggles (`claude`, `gemini`, `openai`), that gates the `grok-cli` package into `environment.systemPackages`. The Grok CLI SHALL NOT be installed unless both `services.ai.enable` and `services.ai.xai.enable` are true.

#### Scenario: Enabled adds the package

- **WHEN** `services.ai.enable = true` and `services.ai.xai.enable = true`
- **THEN** `grok-cli` is present in `environment.systemPackages`

#### Scenario: Disabled by default keeps it out

- **WHEN** `services.ai.enable = true` and `services.ai.xai.enable` is unset
- **THEN** `grok-cli` is not installed

### Requirement: Shell completions

The `grok-cli` package SHALL install bash, zsh, and fish completions generated from the binary's own `completions` subcommand at build time, so completions are available declaratively without the installer's mutation of user shell config.

#### Scenario: Completions are present in the package output

- **WHEN** the `grok-cli` package is built
- **THEN** completion files for bash, zsh, and fish are installed under the package's standard completion directories
