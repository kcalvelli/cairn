## Context

xAI distributes the Grok CLI only as a closed-source prebuilt binary. The official install path is `curl -fsSL https://x.ai/cli/install.sh | bash`. Inspecting that script (June 2026) establishes the relevant mechanics:

- The installer resolves a version from a channel pointer — `https://x.ai/cli/<channel>` returns a bare version string. Current pointers: `stable` → `0.2.33`, `alpha` → `0.2.35`, `enterprise` → `0.2.32`. The **alpha channel is the beta track** referenced in the request.
- It then downloads a single binary named `grok-<version>-<os>-<arch>` (e.g. `grok-0.2.35-linux-x86_64`) from one of two equivalent sources:
  - Primary (Cloudflare-fronted): `https://x.ai/cli/grok-<version>-<platform>`
  - Fallback (direct GCS, unauthenticated): `https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-<version>-<platform>`
- The downloaded binary is `chmod +x`'d and symlinked to **two** names, `grok` and `agent`.
- It generates shell completions by invoking `grok completions {bash,zsh,fish}`.
- It writes `~/.grok/config.toml` with `installer = "internal"`, mutates `~/.bashrc`/`.zshrc`/fish config to add `~/.grok/bin` to PATH, and the binary self-updates in place by re-running this flow.

None of the installer's runtime mutation is acceptable on NixOS, but the artifact itself (an unauthenticated, statically-named GCS object) is exactly what `fetchurl` consumes. Auth (`grok login`, `GROK_DEPLOYMENT_KEY`) only affects runtime API access, not the binary download — so the package needs no secrets. cairn already packages comparable proprietary binaries this way (`claude-desktop`, `discord` via `fetchurl` + `autoPatchelfHook`), and wires per-vendor AI CLIs through `services.ai.<vendor>.enable` (`claude`, `gemini`, `openai`).

## Goals / Non-Goals

**Goals:**
- A reproducible `pkgs/grok-cli` derivation pinning a specific beta (alpha-channel) version + sha256.
- Both `grok` and `agent` on PATH, matching upstream.
- Build-time shell completions, no user-shell mutation.
- A `services.ai.xai.enable` toggle consistent with the existing per-tool pattern.
- Neutralize / not depend on the binary's self-update behavior.

**Non-Goals:**
- Auto-updating the pinned version (manual bump, like `claude-desktop`).
- Packaging macOS/Windows builds — `x86_64-linux` only (matching the fleet; `aarch64-linux` left as a follow-up).
- Managing Grok auth, deployment keys, or `~/.grok` runtime config declaratively.
- Wrapping MCP/system-prompt integration into Grok (out of scope; can follow once the binary is in the tree).

## Decisions

**1. `fetchurl` from the direct GCS URL, not the `x.ai/cli` front.**
The GCS bucket `grok-build-public-artifacts` is the stable, CDN-independent origin and is what the installer itself falls back to. Pin `url = "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${version}-linux-x86_64"` with a fixed `sha256`. *Alternative considered:* the `x.ai/cli` Cloudflare front — rejected because it adds a redirect layer with no benefit for a pinned hash.

**2. `stdenv.mkDerivation` + `autoPatchelfHook`, `dontUnpack` / `dontBuild`.**
The source is a bare ELF, not an archive. Set `dontUnpack = true`, copy `$src` to `$out/bin/grok` in `installPhase`, `chmod +x`, and let `autoPatchelfHook` rewrite the interpreter and RPATH. `buildInputs` start with `stdenv.cc.cc.lib` (libstdc++/libgcc) and grow only as `autoPatchelfHook` reports missing `.so`s — the binary is likely a Bun- or Rust-compiled single executable, so expect a small set (commonly `zlib`, `openssl`, `stdenv.cc.cc`). Follow `pkgs/discord/default.nix` for the `autoPatchelfIgnoreMissingDeps` escape hatch if an optional `.so` is absent. *Alternative considered:* `buildFHSEnv` (as `claude-desktop` uses) — rejected as overkill for a single CLI binary; patchelf is lighter and the norm for CLI tools.

**3. Both entrypoints via symlink.**
`ln -s $out/bin/grok $out/bin/agent`, mirroring the installer. `meta.mainProgram = "grok"`.

**4. Completions generated in a `postInstall` (or `installCheckPhase`) by running the patched binary.**
After patchelf, run `$out/bin/grok completions bash > …`, `zsh`, `fish`, writing to `$out/share/bash-completion/completions/grok`, `$out/share/zsh/site-functions/_grok`, and `$out/share/fish/vendor_completions.d/grok.fish`. These subcommands are offline (the installer runs them with no network), so they work in the sandbox. Guard with `|| true` like the installer does, so a completions-format change upstream never breaks the build. *Alternative:* vendoring static completion files — rejected as drift-prone.

**5. Channel = pinned version, documented, not a build-time fetch.**
Nix cannot resolve a moving channel pointer at build time (impure). The derivation pins the alpha/beta version chosen at packaging time; the `passthru` records the channel and the update procedure. Bumping = edit `version` + `sha256` (or run a small update script analogous to `pkgs/discord/update.sh`).

**6. Wire into `services.ai` via a new `xai` sub-option.**
Add `services.ai.xai.enable = lib.mkEnableOption "Grok CLI (xAI)";` next to `claude`/`gemini`/`openai`, and append `++ lib.optionals cfg.xai.enable [ grok-cli ]` to `environment.systemPackages` in `modules/ai/default.nix`. No `modules/default.nix` or `lib/default.nix` edit needed — this is a package + an option on an already-registered module. The package auto-registers through `pkgs/default.nix`'s directory scan.

## Risks / Trade-offs

- **[Unknown runtime deps until first build]** → Build iteratively: add `stdenv.cc.cc.lib`, run `nix build`, read `autoPatchelfHook`'s "missing dependency" output, add the named libs, repeat. This is mechanical and bounded.
- **[Binary self-updates in place]** → On a read-only nix store the self-update write simply fails; the CLI keeps running the pinned build. To avoid noisy errors, document `GROK_BIN_DIR`/config behavior and, if the CLI respects it, consider setting an env/config that disables auto-update. Treated as a runtime-config concern, not a packaging blocker. Mirrors the `SKIP_HOST_UPDATE` handling cairn already does for `discord`.
- **[Closed-source binary that phones home to xAI]** → Deliberate exception to cairn's open-source-default, with clear precedent (`claude-code`, `gemini-cli-bin`, `antigravity`). Flagged via `license = unfree` + `sourceProvenance = [ binaryNativeCode ]` so `allowUnfree` gates it honestly.
- **[Pinned beta drifts from upstream]** → Accepted; same maintenance posture as `claude-desktop`. Record version + channel in `passthru` and provide an update note/script.
- **[GCS artifact could disappear / URL scheme could change]** → Low near-term risk (it's the installer's own fallback origin). If it breaks, the fix is a re-pin; nothing downstream is load-bearing on it.
- **[`completions` subcommand requires network]** → Believed offline (installer runs it post-download with no auth), but if it isn't, guard with `|| true` and fall back to no completions rather than failing the build.

## Migration Plan

1. Add `pkgs/grok-cli/default.nix`; iterate `nix build .#grok-cli` until patchelf is clean and `grok --version` runs.
2. Add `services.ai.xai` option + package gating in `modules/ai/default.nix`.
3. Update `openspec/specs/ai/spec.md` per the delta.
4. `nix fmt .` and `nix flake check`.
5. Commit + push (downstream configs pull from the remote before rebuild).
6. Rollback: revert the two files; the package is additive and off-by-default, so no downstream system is affected until it opts in with `services.ai.xai.enable = true`.

## Open Questions

- Which exact beta version to pin first — current alpha is `0.2.35`. Confirm at implementation time (the pointer moves).
- Does the Grok CLI honor an env var or `config.toml` key to disable self-update cleanly? Determine empirically; if not, in-place update failure on a read-only store is harmless but may log warnings.
- `aarch64-linux` (pangolin? future hardware) — defer unless needed; the GCS bucket has `linux-aarch64` artifacts, so adding it later is a platform-conditional `src`.
