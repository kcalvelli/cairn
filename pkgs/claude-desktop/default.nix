{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  # Runtime dependencies (autoPatchelfHook resolves the native ELF closure
  # against these). The set is derived from the .deb's own `Depends:` line
  # plus the libraries every Electron/Chromium bundle pulls in.
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  libayatana-appindicator,
  libdrm,
  libgbm,
  libnotify,
  libpulseaudio,
  libsecret,
  libuuid,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  # X11 stack
  libX11,
  libXScrnSaver,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXi,
  libXrandr,
  libXrender,
  libXtst,
  libxcb,
  libxshmfence,
}:

# Claude Desktop, packaged from Anthropic's OFFICIAL native Linux build.
#
# Anthropic publishes a signed apt repository at downloads.claude.ai (launched
# 2026-07); this fetches the real .deb straight from their pool — no more
# third-party repackaging of the Windows build. It's a stock Electron app, so
# the recipe is the canonical vendored-.deb pattern: extract, autoPatchelf the
# native binaries, wrap the Electron entrypoint.
#
# The version + hash live in ../claude-desktop-manifest.json, bumped by
# scripts/update-claude-desktop.sh (mirrors the claude-code manifest flow).
let
  manifest = lib.importJSON ../claude-desktop-manifest.json;
  version = manifest.version;
  platform =
    manifest.platforms.${stdenv.hostPlatform.system}
      or (throw "claude-desktop: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl {
    inherit (platform) url hash;
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libayatana-appindicator
    libdrm
    libgbm
    libnotify
    libpulseaudio
    libsecret
    libuuid
    libxkbcommon
    mesa
    nspr
    nss
    pango
    systemd
    libX11
    libXScrnSaver
    libXcomposite
    libXcursor
    libXdamage
    libXext
    libXfixes
    libXi
    libXrandr
    libXrender
    libXtst
    libxcb
    libxshmfence
  ];

  # The bundled `resources/virtiofsd` belongs to the "cowork"/computer-use VM
  # helper, which isn't available on Linux (and we don't ship qemu/ovmf for it).
  # Leave its deps unresolved instead of hauling in that closure for a dead
  # feature. libvulkan is swiftshader's optional loader path.
  autoPatchelfIgnoreMissingDeps = [
    "libseccomp.so.2"
    "libcap-ng.so.0"
    "libvulkan.so.1"
  ];

  # `dpkg-deb -x` tries to restore chrome-sandbox's 4755 mode and the build
  # sandbox rejects the setuid bit. Pipe the data tarball through tar with the
  # perm bits dropped — a setuid binary in the store would be useless anyway;
  # the real setuid helper comes from NixOS's chromiumSuidSandbox wrapper.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # The whole Electron bundle, verbatim.
    mkdir -p $out/lib
    cp -r usr/lib/claude-desktop $out/lib/

    # Wrap the Electron entrypoint:
    #   * CHROME_DEVEL_SANDBOX points at NixOS's setuid sandbox helper so the
    #     renderer sandbox stays ON (the nix store can't setuid chrome-sandbox
    #     itself). Requires security.chromiumSuidSandbox.enable — modules/ai
    #     turns it on whenever this package ships.
    #   * ozone-platform-hint=auto = Wayland when there's a compositor, X11
    #     otherwise. Beats the old hard-forced --ozone-platform=wayland that
    #     left a blank window under X.
    #   * password-store=gnome-libsecret forces the libsecret backend. Chromium
    #     otherwise auto-detects the keyring from XDG_CURRENT_DESKTOP, and on a
    #     tiling compositor like niri that value ("niri") is unrecognised, so it
    #     silently falls back to the plaintext "basic" store — which makes
    #     Claude refuse to persist the login ("sign-in won't be saved"). We ship
    #     niri + gnome-keyring, so pin the backend explicitly.
    #   * LD_LIBRARY_PATH carries libsecret. Chromium doesn't LINK libsecret — it
    #     dlopen("libsecret-1.so.0")s it at runtime once the gnome-libsecret
    #     backend is chosen. autoPatchelf only fixes NEEDED libs, and glibc
    #     doesn't consult DT_RUNPATH for dlopen, so on NixOS the bare soname
    #     resolves to nothing: backend=gnome_libsecret yet
    #     isEncryptionAvailable=false → safeStorage dead → login won't persist.
    #     Putting libsecret on LD_LIBRARY_PATH is what actually makes the dlopen
    #     land. THIS is the fix for the relogin loop; the flag above only selects
    #     the backend, it can't load the library.
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      --set CHROME_DEVEL_SANDBOX /run/wrappers/bin/__chromium-suid-sandbox \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libsecret ]} \
      --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations" \
      --add-flags "--ozone-platform-hint=auto" \
      --add-flags "--password-store=gnome-libsecret"

    # Desktop entry + icons ship correct in the .deb (right app_id, desktop
    # actions, com.anthropic.Claude WM class). Take them as-is; only fix the
    # icon lookup path isn't needed since Icon=claude-desktop resolves from
    # hicolor. Exec=claude-desktop resolves to our wrapper on PATH.
    mkdir -p $out/share
    cp -r usr/share/applications $out/share/
    cp -r usr/share/icons $out/share/

    runHook postInstall
  '';

  meta = {
    description = "Claude Desktop — Anthropic's official native Linux build";
    longDescription = ''
      Claude Desktop for Linux, packaged from Anthropic's official signed apt
      repository at downloads.claude.ai. Proprietary software (unfree).

      Note: on Linux, "computer use" and dictation are not yet available, and
      the global Quick Entry hotkey has limited Wayland support.
    '';
    homepage = "https://claude.ai";
    downloadPage = "https://claude.ai/download";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    license = lib.licenses.unfree;
    mainProgram = "claude-desktop";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };

  passthru.updateScript = ../../scripts/update-claude-desktop.sh;
}
