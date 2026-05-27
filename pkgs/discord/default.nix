{
  lib,
  stdenv,
  fetchurl,
  runCommand,
  writeShellScript,
  makeShellWrapper,
  makeDesktopItem,
  autoPatchelfHook,
  wrapGAppsHook3,
  brotli,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gtk3,
  jq,
  libcxx,
  libdrm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libuuid,
  libva,
  libx11,
  libxscrnsaver,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  libxcb,
  libxkbcommon,
  libxshmfence,
  libgbm,
  nspr,
  nss,
  pango,
  systemdLibs,
  libappindicator-gtk3,
  libdbusmenu,
  libunity,
  pipewire,
  speechd-minimal,
  wayland,
}:

let
  source = lib.importJSON ./sources.json;

  src = fetchurl { inherit (source.distro) url hash; };

  moduleSrcs = lib.mapAttrs (_: mod: fetchurl { inherit (mod) url hash; }) source.modules;

  # Discord's moduleUpdater fingerprints installed modules via installed.json.
  # We pre-populate it so it doesn't try to re-download the modules we've
  # already vendored into the nix store.
  installedJson = builtins.toJSON (
    lib.mapAttrs (_: mod: { installedVersion = mod.version; }) source.modules
  );

  # At first launch for a given version, symlink the vendored modules from
  # the nix store into Discord's per-version module directory and write
  # installed.json so the updater treats them as already-current.
  stageModules = writeShellScript "discord-stage-modules" ''
    store_modules="$1"
    modules_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/discord/${source.version}/modules"
    if [ ! -f "$modules_dir/installed.json" ]; then
      mkdir -p "$modules_dir"
      for m in ${lib.concatStringsSep " " (lib.attrNames moduleSrcs)}; do
        ln -sfn "$store_modules/$m" "$modules_dir/$m"
      done
      printf '%s\n' '${installedJson}' > "$modules_dir/installed.json"
    fi
  '';

  # Discord's host self-updater wants to write a new deb/tarball over the
  # install. On NixOS that path is read-only, so it would brick the client.
  # Flip SKIP_HOST_UPDATE in settings.json before launch.
  disableHostUpdate = writeShellScript "discord-disable-host-update" ''
    settings="''${XDG_CONFIG_HOME:-$HOME/.config}/discord/settings.json"
    mkdir -p "$(dirname "$settings")"
    if [ -f "$settings" ]; then
      if ! ${jq}/bin/jq -e '.SKIP_HOST_UPDATE == true' "$settings" >/dev/null 2>&1; then
        tmp="$(mktemp)"
        ${jq}/bin/jq '. + {SKIP_HOST_UPDATE: true}' "$settings" > "$tmp" \
          && mv "$tmp" "$settings"
      fi
    else
      printf '{"SKIP_HOST_UPDATE": true}\n' > "$settings"
    fi
  '';

  libPath = lib.makeLibraryPath [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    libappindicator-gtk3
    libcxx
    libdbusmenu
    libdrm
    libgbm
    libglvnd
    libnotify
    libpulseaudio
    libunity
    libuuid
    libva
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
    nspr
    # nss intentionally omitted from LD_LIBRARY_PATH: it leaks via xdg-open
    # children and breaks Firefox when major versions diverge.
    pango
    pipewire
    speechd-minimal
    stdenv.cc.cc
    systemdLibs
    wayland
  ];

  desktopItem = makeDesktopItem {
    name = "discord";
    exec = "Discord";
    icon = "discord";
    desktopName = "Discord";
    genericName = "All-in-one cross-platform voice and text chat";
    categories = [
      "Network"
      "InstantMessaging"
    ];
    mimeTypes = [ "x-scheme-handler/discord" ];
    startupWMClass = "discord";
  };
in
stdenv.mkDerivation {
  pname = "discord";
  inherit (source) version;
  inherit src;

  nativeBuildInputs = [
    autoPatchelfHook
    brotli
    cups
    libdrm
    libx11
    libxcb
    libxdamage
    libxscrnsaver
    libxshmfence
    libxtst
    libuuid
    makeShellWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    libgbm
    nspr
    nss
    # Discord ships prebuilt .node modules: discord_dispatch links against
    # openssl 1.1 (effectively unused), discord_voice against libpulseaudio.
    libpulseaudio
  ];

  strictDeps = true;
  dontUnpack = true;
  dontWrapGApps = true;

  autoPatchelfIgnoreMissingDeps = [
    "libssl.so.1.1"
    "libcrypto.so.1.1"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/Discord $out/bin $out/share/icons/hicolor/256x256/apps

    # Host distro: brotli-compressed tar, contents under files/
    brotli -d < $src | tar xf - --strip-components=1 -C $out/opt/Discord
    chmod +x $out/opt/Discord/Discord

    # Module distros: same brotli+tar+files/ layout, one per .node bundle
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: mSrc: ''
        mkdir -p $out/opt/Discord/modules/${name}
        brotli -d < ${mSrc} | tar xf - --strip-components=1 -C $out/opt/Discord/modules/${name}
      '') moduleSrcs
    )}

    wrapProgramShell $out/opt/Discord/Discord \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --prefix XDG_DATA_DIRS : "${gtk3}/share/gsettings-schemas/${gtk3.name}/" \
      --prefix LD_LIBRARY_PATH : ${libPath}:$out/opt/Discord \
      --run ${disableHostUpdate} \
      --run "${stageModules} $out/opt/Discord/modules"

    ln -s $out/opt/Discord/Discord $out/bin/Discord
    ln -s $out/opt/Discord/Discord $out/bin/discord
    ln -s $out/opt/Discord/discord.png $out/share/icons/hicolor/256x256/apps/discord.png
    ln -s "${desktopItem}/share/applications" $out/share/

    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "All-in-one cross-platform voice and text chat for gamers (vanilla, cairn-packaged)";
    homepage = "https://discord.com/";
    downloadPage = "https://discord.com/download";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "Discord";
  };
}
