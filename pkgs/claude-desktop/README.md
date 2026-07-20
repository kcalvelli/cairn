# Claude Desktop for NixOS

Claude Desktop, packaged from **Anthropic's official native Linux build**.

Since the 2026-07 Linux launch, Anthropic publishes a signed apt repository at
`downloads.claude.ai/claude-desktop/apt/stable`. This package fetches the real
`.deb` straight from that pool — a genuine native Electron app with `node-pty`,
`claude-native`, and Claude Code integration built in. No more third-party
repackaging of the Windows release.

> **History:** earlier versions of this package wrapped
> [`aaddrick/claude-desktop-debian`](https://github.com/aaddrick/claude-desktop-debian),
> a community effort that shimmed Anthropic's *Windows* Electron build onto
> Linux. That was the only option before an official build existed. It's gone.

## How it's built

Standard vendored-`.deb` recipe:

1. `fetchurl` the official `.deb` (version + hash pinned in
   [`../claude-desktop-manifest.json`](../claude-desktop-manifest.json)).
2. Extract the data tarball (dropping chrome-sandbox's setuid bit — see below).
3. `autoPatchelfHook` resolves the native ELF closure against nixpkgs.
4. `makeWrapper` the Electron entrypoint with the sandbox + Wayland flags.
5. Install the shipped `.desktop` entry and hicolor icons verbatim.

## The sandbox

Electron's bundled `chrome-sandbox` wants to be setuid root, which the nix store
can't provide. Rather than fall back to `--no-sandbox`, the wrapper points
`CHROME_DEVEL_SANDBOX` at NixOS's setuid sandbox helper
(`/run/wrappers/bin/__chromium-suid-sandbox`) so the renderer sandbox stays
**on**.

That helper only exists when `security.chromiumSuidSandbox.enable = true`.
**cairn's AI module turns this on automatically** whenever Claude Desktop ships
(`services.ai.claude.enable`), so there's nothing to configure. If you install
the package outside that module, enable the option yourself:

```nix
security.chromiumSuidSandbox.enable = true;
```

## Wayland vs X11

The wrapper uses `--ozone-platform-hint=auto`: native Wayland under a
compositor (Niri, Sway, Hyprland), X11 otherwise. This replaced the old
hard-forced `--ozone-platform=wayland`, which left a blank window under X.

## Usage

Through cairn's AI module (recommended — handles the sandbox for you):

```nix
{
  services.ai = {
    enable = true;
    claude.enable = true;  # installs claude-code + claude-desktop
  };
}
```

Standalone:

```nix
{
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = [ pkgs.claude-desktop ];
  security.chromiumSuidSandbox.enable = true;
}
```

Try it without installing:

```bash
nix run github:kcalvelli/cairn#claude-desktop
```

## Not packaged: "computer use" / cowork

The official `.deb` bundles a `cowork-linux-helper` and recommends
`qemu-system-x86`, `ovmf`, and `virtiofsd` — the VM sandbox behind computer
use. Anthropic's own docs say **computer use isn't available on Linux yet**, so
this package deliberately leaves `resources/virtiofsd`'s dependencies
unresolved rather than drag qemu's closure in for a dead feature. Revisit when
the feature actually ships on Linux.

## Updating

The version and hash live in
[`../claude-desktop-manifest.json`](../claude-desktop-manifest.json), bumped by
[`scripts/update-claude-desktop.sh`](../../scripts/update-claude-desktop.sh):

```bash
./scripts/update-claude-desktop.sh            # latest stable
./scripts/update-claude-desktop.sh 1.22209.3  # a specific version
```

The script parses the apt repository's `Packages` index and converts the
published SHA256 to SRI — no blind 150 MB re-download just to hash it.
`.github/workflows/update-claude-desktop.yml` runs it daily, builds the result,
and opens a PR on a new release. Mirrors the `claude-code` manifest flow.

## License

- **Claude Desktop**: proprietary software by Anthropic (unfree).
- **This package**: the Nix build recipe only.
