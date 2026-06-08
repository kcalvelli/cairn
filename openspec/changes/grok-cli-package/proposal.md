## Why

xAI ships the Grok CLI (`grok` / `agent`) as a closed-source prebuilt binary installed via `curl -fsSL https://x.ai/cli/install.sh | bash`. That installer is impure: it writes to `~/.grok`, mutates `~/.bashrc`/PATH, and self-updates in place — none of which survives, or belongs on, a declarative NixOS system. To use Grok alongside the other coding agents cairn already manages (`claude-code`, `gemini-cli`, `codex`), it needs to be a proper Nix package wired into `services.ai`.

The feasibility question is settled: the installer downloads a single, statically-named binary (`grok-<version>-linux-x86_64`) from a stable, unauthenticated GCS bucket. That is the same fetch-and-patchelf shape cairn already uses for `discord` and `claude-desktop`, so a derivation is straightforward.

## What Changes

- Add a new package `pkgs/grok-cli/` — a `fetchurl` + `autoPatchelfHook` derivation that pins a specific Grok version + sha256, installs the binary, and exposes both `grok` and `agent` entrypoints (matching upstream).
- Pin to the **alpha (beta) channel** per the request, with the version/hash recorded in the derivation; the GCS artifact URL is the same across channels, only the version string differs.
- Generate shell completions (bash/zsh/fish) at build time via the binary's own `completions` subcommand, the same way the installer does.
- Add a per-tool enable option `services.ai.xai.enable` (mirroring `services.ai.claude.enable` / `.gemini.enable` / `.openai.enable`) that gates `grok-cli` into `environment.systemPackages`.
- Mark the package `license = unfree` with `sourceProvenance = [ binaryNativeCode ]`, consistent with the other proprietary AI tools cairn vendors.

## Capabilities

### New Capabilities
<!-- none — this is a package addition plus an option on an existing capability -->

### Modified Capabilities
- `ai`: Adds Grok (xAI) to the CLI coding-agent roster — a new `services.ai.xai.enable` toggle and the `grok-cli` package under the AI tool stack.

## Impact

- **New file**: `pkgs/grok-cli/default.nix` (auto-discovered by `pkgs/default.nix`; no registry edit needed).
- **Modified**: `modules/ai/default.nix` — new `services.ai.xai` option block and a `lib.optionals cfg.xai.enable [ grok-cli ]` entry in the package list.
- **Modified**: `openspec/specs/ai/spec.md` (via delta) — document Grok under "CLI Coding Agents".
- **Dependencies**: no new flake inputs. Pulls glibc/libstdc++ and whatever the binary links against, resolved by `autoPatchelfHook`.
- **Maintenance burden**: version + sha256 are pinned manually; like `claude-desktop`, there is no auto-update. The pinned beta will drift from upstream and needs periodic bumping.
- **Risks to validate in design**: (1) the binary's exact runtime library deps are unknown until `autoPatchelfHook` runs; (2) Grok writes `installer = "internal"` to `~/.grok/config.toml` and may attempt self-update — on a read-only nix store that will fail, so self-update behavior must be neutralized or documented; (3) closed-source proprietary binary that phones home to xAI, a deliberate exception to cairn's open-source-by-default stance (precedent: `claude-code`, `gemini-cli-bin`, `antigravity`, `discord`).
