> **Implementation note:** The pinned binary turned out to be **static-pie linked**
> (no `.interp`, no `NEEDED` libs), so `autoPatchelfHook` and `buildInputs` were
> unnecessary — the derivation is simpler than design.md anticipated. Tasks 1.3/1.5
> are marked done on that basis (deviation recorded).

## 1. Package the binary

- [x] 1.1 Resolve the current alpha/beta version pointer (`curl -fsSL https://x.ai/cli/alpha`) and record it as the pinned `version`. → `0.2.35`
- [x] 1.2 Compute the sha256 with `nix store prefetch-file https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-<version>-linux-x86_64` (or `nix-prefetch-url`). → `sha256-pBivJiE8jSQwBicL58Jzsty7WpMSg/G94SD8TE2wL5k=`
- [x] 1.3 Create `pkgs/grok-cli/default.nix`: `stdenv.mkDerivation` with `fetchurl` src, `dontUnpack = true`, `dontBuild = true`. (Static binary → no `autoPatchelfHook`/`buildInputs` needed; `dontPatchELF = true` instead.)
- [x] 1.4 `installPhase`: install `$src` to `$out/bin/grok` (mode 755), then `ln -s grok $out/bin/agent`.
- [x] 1.5 Run `nix build .#grok-cli`. Binary is static-pie — no missing-dep iteration required; ELF inspection (`patchelf --print-needed` → empty) confirmed.
- [x] 1.6 Verify `result/bin/grok --version` and `result/bin/agent --version` both print `grok 0.2.35`.

## 2. Completions and metadata

- [x] 2.1 `postInstall` emits completions: bash → `$out/share/bash-completion/completions/grok`, zsh → `$out/share/zsh/site-functions/_grok`, fish → `$out/share/fish/vendor_completions.d/grok.fish`, each guarded with `|| true`.
- [x] 2.2 `meta`: `description`, `homepage = "https://x.ai/cli"`, `license = lib.licenses.unfree`, `sourceProvenance = [ lib.sourceTypes.binaryNativeCode ]`, `platforms = [ "x86_64-linux" ]`, `mainProgram = "grok"`.
- [x] 2.3 `passthru` records `channel = "alpha"` and a manual-update note (`updateScript` warning with re-pin steps).
- [x] 2.4 Rebuilt; all three completion files present in the output.

## 3. Wire into services.ai

- [x] 3.1 Added `xai = { enable = lib.mkEnableOption "Grok CLI (xAI)"; };` in `modules/ai/default.nix` next to `claude`/`gemini`/`openai`.
- [x] 3.2 Added `++ lib.optionals cfg.xai.enable [ grok-cli ]` to `environment.systemPackages`.
- [x] 3.3 Confirmed `grok-cli` resolves via the auto-discovery overlay (`nix build .#grok-cli` + `nix flake check` both green); no `modules/default.nix` or `lib/default.nix` edits required.

## 4. Spec, format, validate

- [x] 4.1 Documented Grok under "CLI Coding Agents" (new **xAI Ecosystem** entry) in `openspec/specs/ai/spec.md`.
- [x] 4.2 `nix fmt .` (1 file reformatted, clean after).
- [x] 4.3 `nix flake check` passes; `grok-cli` derivation evaluates. (No in-repo host config to dry-run `services.ai.xai.enable`; that's downstream — see §5.)
- [ ] 4.4 Commit and **push** — held for approval (on `master`; house rule: no push to master without asking).

## 5. Runtime sanity (manual / downstream)

- [ ] 5.1 Install via a host with `services.ai.xai.enable = true`, run `grok --version` and tab-completion in bash/zsh/fish.
- [ ] 5.2 Confirm the read-only-store self-update path fails harmlessly (no breakage); note any disable-auto-update env/config key discovered, for follow-up.
