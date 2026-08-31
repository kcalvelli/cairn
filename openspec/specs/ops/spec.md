# Operations & Deployment

## Purpose

Defines the procedures for system installation, automated validation, continuous integration, and dependency maintenance.

## Components

### Installation (Init Script)

- **Tool**: `nix run .#init`
- **Pattern**: Uses `hardwareConfigPath` to reference the system's `hardware-configuration.nix` directly, avoiding the fragile extraction of boot/filesystem settings.
- **Support**: Secure Boot enrollment guidance and UEFI-only partitioning.
- **Implementation**: `scripts/init-config.sh`

### Continuous Integration (GitHub Actions)

- **Flake Check**: Validates flake structure and buildable outputs (`Validate flake` job).
- **Formatting**: Enforces `nixfmt-rfc-style` on all Nix files (`Check Nix formatting` job).
- **DevShell Builds**: Ensures all development shells remain buildable.
- **Init Script**: Smoke-tests `nix run .#init`.
- **Implementation**: `.github/workflows/`

### Dependency Updaters

- **flake.lock**: Weekly automated `nix flake update` PR (`flake-lock-updater.yml`).
- **AI Manifests**: Daily PRs bumping the vendored `claude-code` and `claude-desktop` manifests, each gated on a real `nix build` of the overlay package before the PR opens.
- **GitHub Actions**: Weekly Dependabot PRs for action version bumps.
- **Auto-merge**: Every updater PR (including Dependabot's, via `dependabot-automerge.yml`) enables squash auto-merge on creation. It lands only when required checks pass.

### Deployment Patterns

- **Library Model**: Cairn is exported as a flake library. Downstream hosts import modules and call `mkSystem`.
- **Lock Scope**: Cairn's own `flake.lock` feeds only its CI, examples, and devshells — it is NOT the fleet's lock. Downstream hosts pin cairn in their own config and get final validation on `nixos-rebuild`.
- **Secrets Management**:
    - `agenix`: System-level secrets (SSH keys, config files).
    - Session Variables: AI API keys (Brave, GitHub).
- **Implementation**: `lib/default.nix`, `modules/secrets/`

## Requirements

### Requirement: Branch Protection Gate

The `master` branch SHALL require the `Validate flake` and `Check Nix formatting` status checks to pass before any pull request merges.

#### Scenario: Green PR merges

- **Given**: A pull request targeting `master`
- **When**: Both the `Validate flake` and `Check Nix formatting` checks pass
- **Then**: The pull request is eligible to merge
- **And**: A pull request with auto-merge enabled merges automatically

#### Scenario: Red PR blocked

- **Given**: A pull request targeting `master`
- **When**: Either required check fails
- **Then**: The pull request is blocked from merging
- **And**: A pull request with auto-merge enabled waits rather than merging, deferring to a human

### Requirement: Automated Dependency Updates

The project SHALL open automated pull requests for dependency updates, and each SHALL enable squash auto-merge on creation so that it lands unattended when CI is green.

#### Scenario: flake.lock update

- **Given**: The weekly `flake-lock-updater` workflow runs
- **When**: `nix flake update` produces a changed `flake.lock`
- **Then**: A pull request is opened with the updated lock
- **And**: Squash auto-merge is enabled on that pull request
- **And**: The PR merges automatically once required checks pass, or waits if they fail

#### Scenario: AI manifest bump

- **Given**: A daily `update-claude-code` or `update-claude-desktop` workflow runs
- **When**: A newer upstream release changes the vendored manifest
- **Then**: The workflow performs a real `nix build` of the overlay package as validation
- **And**: On success, a pull request is opened with squash auto-merge enabled

#### Scenario: Dependabot action bump

- **Given**: Dependabot opens a GitHub Actions version bump pull request
- **When**: The `dependabot-automerge` workflow runs for that PR
- **Then**: Squash auto-merge is enabled on the pull request
- **And**: It merges once required checks pass

#### Scenario: No changes to apply

- **Given**: A dependency updater workflow runs
- **When**: There is nothing to update
- **Then**: No pull request is opened

### Requirement: Installation Init Script

The project SHALL provide `nix run .#init` to generate a downstream host configuration.

#### Scenario: Init smoke test

- **Given**: The `test-init-script` workflow runs
- **When**: `nix run .#init -- --help` is invoked
- **Then**: The command exits successfully

### Requirement: Library Deployment Model

Cairn SHALL be consumed as a flake library by downstream hosts rather than deployed directly.

#### Scenario: Downstream host build

- **Given**: A downstream configuration importing cairn and calling `mkSystem`
- **When**: The host runs `nixos-rebuild`
- **Then**: Cairn's modules are evaluated against the host's own pinned inputs
- **And**: Cairn's own `flake.lock` does not affect the host's resolved dependencies

## Procedures

- **Spec-Driven Development**: All changes MUST follow the OpenSpec workflow.
    - **Tool**: `openspec` CLI.
    - **Workflow**: Create delta in `openspec/changes/`, update specs, implement, and archive.
- **Formatting**: Always run `nix fmt .` before committing.
- **Testing**: For heavy changes, validate locally with `nix flake check --all-systems` and a real build of the example config toplevel (`cd examples/example-config && nix build .#nixosConfigurations.<host>.config.system.build.toplevel`). CI runs the same as a dry-run; because the library's lock is not the fleet's, downstream hosts get final validation on `nixos-rebuild`.
- **Conventional Commits**: All PRs and commits should follow standard git conventions.

---

*Last updated: August 2026*
