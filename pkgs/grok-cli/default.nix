{
  lib,
  stdenv,
  fetchurl,
}:

# xAI Grok CLI — closed-source prebuilt binary.
#
# Upstream ships this only via `curl -fsSL https://x.ai/cli/install.sh | bash`,
# which downloads a single statically-named artifact from an unauthenticated
# GCS bucket and then mutates your shell config. We skip all the mutation and
# just vendor the binary.
#
# The binary is a 131M static-pie executable (no .interp, no NEEDED libs), so
# unlike claude-desktop/discord it needs NO autoPatchelfHook — it runs as-is on
# NixOS. Hence the tiny dependency set below.
#
# Channel/version: pinned to the `alpha` (beta) track. Bump by re-resolving
# `curl -fsSL https://x.ai/cli/alpha` and re-prefetching the hash:
#   nix store prefetch-file \
#     https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-<ver>-linux-x86_64

let
  pname = "grok-cli";
  version = "0.2.35";
  channel = "alpha";

  src = fetchurl {
    url = "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${version}-linux-x86_64";
    hash = "sha256-pBivJiE8jSQwBicL58Jzsty7WpMSg/G94SD8TE2wL5k=";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  dontUnpack = true;
  dontBuild = true;
  # Static-pie binary, already stripped — nothing for fixup to patch or strip.
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/grok
    # Upstream installs the same binary under both names.
    ln -s grok $out/bin/agent

    runHook postInstall
  '';

  # Generate shell completions from the binary itself, the way the upstream
  # installer does. These subcommands are offline. Guarded with `|| true` so a
  # completions-format change upstream can never break the build.
  postInstall = ''
    install -d $out/share/bash-completion/completions \
               $out/share/zsh/site-functions \
               $out/share/fish/vendor_completions.d
    $out/bin/grok completions bash > $out/share/bash-completion/completions/grok 2>/dev/null || true
    $out/bin/grok completions zsh  > $out/share/zsh/site-functions/_grok        2>/dev/null || true
    $out/bin/grok completions fish > $out/share/fish/vendor_completions.d/grok.fish 2>/dev/null || true
  '';

  # Smoke-test the vendored binary actually runs in the sandbox.
  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/grok --version
  '';

  passthru = {
    inherit channel;
    # No auto-update: re-resolve the channel pointer and re-pin manually.
    # `curl -fsSL https://x.ai/cli/${channel}` gives the current version.
    updateScript = lib.warn ''
      grok-cli is pinned manually. To bump:
        1. ver=$(curl -fsSL https://x.ai/cli/${channel})
        2. nix store prefetch-file \
             https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-$ver-linux-x86_64
        3. update version + hash in pkgs/grok-cli/default.nix
    '' null;
  };

  meta = {
    description = "xAI Grok CLI coding agent (grok / agent), beta channel, cairn-packaged";
    homepage = "https://x.ai/cli";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "grok";
  };
}
