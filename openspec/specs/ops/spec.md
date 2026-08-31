# Operations & Deployment

## Purpose
Defines the procedures for system installation, automated validation, and continuous integration.

## Components

### Installation (Init Script)
- **Tool**: `nix run .#init`
- **Pattern**: Uses `hardwareConfigPath` to reference the system's `hardware-configuration.nix` directly, avoiding the fragile extraction of boot/filesystem settings.
- **Support**: Secure Boot enrollment guidance and UEFI-only partitioning.
- **Implementation**: `scripts/init-config.sh`

### Continuous Integration (GitHub Actions)
- **Flake Check**: Validates flake structure and buildable outputs.
- **Formatting**: Enforces `nixfmt-rfc-style` on all Nix files.
- **DevShell Builds**: Ensures all development shells remain buildable.
- **Dependency Updaters**: Automated PRs for `flake.lock` (weekly), the vendored `claude-code`/`claude-desktop` manifests (daily), and GitHub Action versions (Dependabot, weekly). Each PR enables auto-merge on creation.
- **Branch Protection**: `master` requires the `Validate flake` and `Check Nix formatting` checks to pass. This is the merge gate — auto-merge lands a bot PR only when CI is green; anything red waits for a human.
- **Implementation**: `.github/workflows/`

### Deployment Patterns
- **Library Model**: Cairn is exported as a flake library. Downstream hosts import modules and call `mkSystem`.
- **Secrets Management**:
    - `agenix`: System-level secrets (SSH keys, config files).
    - Session Variables: AI API keys (Brave, GitHub).
- **Implementation**: `lib/default.nix`, `modules/secrets/`

## Procedures
- **Spec-Driven Development**: All changes MUST follow the OpenSpec workflow.
    - **Tool**: `openspec` CLI.
    - **Workflow**: Create delta in `openspec/changes/`, update specs, implement, and archive.
- **Formatting**: Always run `nix fmt .` before committing.
- **Testing**: For heavy changes, validate locally with `nix flake check --all-systems` and a real build of the example config (`cd examples/example-config && nix build .#nixosConfigurations.<host>.config.system.build.toplevel`). CI runs the same as a dry-run; the library's own `flake.lock` is not the fleet's, so downstream hosts get final validation on `nixos-rebuild`.
- **Conventional Commits**: All PRs and commits should follow standard git conventions.
