{
  inputs,
  pkgs,
  config,
  lib,
  osConfig,
  ...
}:

{
  imports = [
    ./theming.nix
    ./wallpaper.nix
    ./niri.nix
    ./niri-keybinds.nix
    ./pwa-apps.nix
    ./mpv.nix
    inputs.cairn-monitor.homeManagerModules.default
    inputs.dankMaterialShell.homeModules.dank-material-shell
    inputs.dms-plugin-registry.homeModules.default
    inputs.dsearch.homeModules.default
  ];

  # Enable PWA apps by default for desktop users
  cairn.pwa.enable = true;

  # Enable Cairn Monitor widget by default for desktop users
  programs.cairn-monitor.enable = lib.mkDefault (osConfig.desktop.enable or false);

  # Configure sudo to use GUI password prompt
  home.sessionVariables = {
    SUDO_ASKPASS = "${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass";

    # Force Qt6Multimedia to use PulseAudio backend instead of native PipeWire.
    # Qt 6.10's new PipeWire backend has a SIGSEGV in QAudioDeviceMonitor::objectAdded
    # when audio devices are registered at startup. PulseAudio works fine via
    # PipeWire's pulse compatibility layer. Remove when Qt fixes the bug.
    QT_MEDIA_BACKEND = "pulseaudio";
  };

  # DankMaterialShell configuration
  programs.dank-material-shell = {
    enable = true;
    quickshell.package = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;

    # Systemd integration - DISABLED to use Niri spawn-at-startup instead
    # This eliminates race conditions with PipeWire/Wayland at boot
    systemd = {
      enable = false; # Use Niri spawn instead (see niri.nix)
      restartIfChanged = false;
    };

    # Feature toggles (explicit configuration for clarity)
    enableSystemMonitoring = true; # System resource monitoring widgets
    enableVPN = true; # VPN status widget
    enableDynamicTheming = true; # Dynamic theme generation (matugen)
    enableAudioWavelength = true; # Audio visualizer (cava)
    enableCalendarEvents = true; # Calendar integration (khal)

    # Note: The following options are now built-in to DMS and have been removed:
    # - enableClipboard: Clipboard history built-in
    # - enableBrightnessControl: Brightness controls built-in
    # - enableColorPicker: Color picker (hyprpicker) built-in
    # - enableSystemSound: System sounds now included in dms-shell package

    # Community plugins via dms-plugin-registry
    plugins = {
      # Core Niri integration (always-on)
      displayManager.enable = true;
      niriWindows.enable = true;
      niriScreenshot.enable = true;
      dankKDEConnect.enable = true;

      # Conditional on AI module
      claudeCodeUsage.enable = osConfig.services.ai.enable or false;

      # Conditional on networking
      tailscale.enable = osConfig.services.tailscale.enable or false;

      # Conditional on virtualisation
      dockerManager.enable = osConfig.virt.enable or false;

      # Conditional on laptop form factor
      dankBatteryAlerts.enable = osConfig.hardware.laptop.enable or false;
      powerUsagePlugin.enable = osConfig.hardware.laptop.enable or false;

      # Explicitly disabled (cairn-monitor provides this)
      nixMonitor.enable = false;
    };
  };

  programs.dsearch = {
    enable = true;
  };

  # Helper scripts
  home.packages = [
    (pkgs.writeShellScriptBin "focus-or-spawn-qalculate" ''
      # robust-focus.sh

      # 1. Define the App ID explicitly
      MATCH_APP="io.github.Qalculate.qalculate-qt"

      # 2. Use jq to parse the JSON array
      # -j: Output raw string (no quotes around the ID)
      # select: Filter the list for windows matching the app_id
      # .id: Extract only the window ID
      # head -n 1: In case multiple windows exist, pick the first one
      WINDOW_ID=$(niri msg -j windows | jq -r ".[] | select(.app_id == \"$MATCH_APP\") | .id" | head -n 1)

      if [ -n "$WINDOW_ID" ]; then
          niri msg action focus-window --id "$WINDOW_ID"
      else
          qalculate-qt &
      fi
    '')
  ];

  # Desktop services
  # NOTE: gnome-keyring is started + unlocked by PAM at login (see
  # modules/desktop: security.pam.services.{greetd,login}.enableGnomeKeyring).
  # Do NOT also enable home-manager's services.gnome-keyring here — it spawns a
  # second daemon that can't auto-unlock and races the PAM one for the Secret
  # Service. PAM or the service, never both.
  services.kdeconnect = {
    enable = true;
    indicator = false; # DMS now has a built in indicator
  };

  # Default application associations for all installed apps
  # Ensures every MIME type opens with the correct Cairn-shipped application
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      # === KDE Connect scheme handler ===
      "x-scheme-handler/kdeconnect" = "org.kde.dolphin.desktop";

      # === Flatpak install handler ===
      "application/vnd.flatpak.ref" = "com.github.kcalvelli.cairn.flatpak-install.desktop";
      "application/vnd.flatpak.repo" = "com.github.kcalvelli.cairn.flatpak-install.desktop";

      # === File Manager (Dolphin) ===
      "inode/directory" = "org.kde.dolphin.desktop";

      # === Web Browser (Brave) ===
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/about" = "brave-browser.desktop";
      "x-scheme-handler/unknown" = "brave-browser.desktop";
      "text/html" = "brave-browser.desktop";
      "application/xhtml+xml" = "brave-browser.desktop";

      # === Claude Desktop deep-link (OAuth callback) ===
      # Claude Desktop tries to self-register this handler at runtime, but on a
      # declarative system ~/.config/mimeapps.list is a read-only store symlink,
      # so its write fails and the browser's claude:// login callback lands on
      # "No Apps Available". Declare it here so the callback routes to the app.
      "x-scheme-handler/claude" = "com.anthropic.Claude.desktop";

      # === Text Editor (Mousepad) ===
      "text/plain" = "org.xfce.mousepad.desktop";
      "text/x-csrc" = "org.xfce.mousepad.desktop";
      "text/x-chdr" = "org.xfce.mousepad.desktop";
      "text/x-c++src" = "org.xfce.mousepad.desktop";
      "text/x-c++hdr" = "org.xfce.mousepad.desktop";
      "text/x-java" = "org.xfce.mousepad.desktop";
      "text/x-python" = "org.xfce.mousepad.desktop";
      "text/x-shellscript" = "org.xfce.mousepad.desktop";
      "text/x-script.python" = "org.xfce.mousepad.desktop";
      "text/x-perl" = "org.xfce.mousepad.desktop";
      "text/x-ruby" = "org.xfce.mousepad.desktop";
      "text/x-lua" = "org.xfce.mousepad.desktop";
      "text/x-makefile" = "org.xfce.mousepad.desktop";
      "text/x-cmake" = "org.xfce.mousepad.desktop";
      "text/x-diff" = "org.xfce.mousepad.desktop";
      "text/x-patch" = "org.xfce.mousepad.desktop";
      "text/x-log" = "org.xfce.mousepad.desktop";
      "text/css" = "org.xfce.mousepad.desktop";
      "text/javascript" = "org.xfce.mousepad.desktop";
      "text/x-sql" = "org.xfce.mousepad.desktop";
      "text/x-readme" = "org.xfce.mousepad.desktop";
      "text/csv" = "org.xfce.mousepad.desktop";
      "text/tab-separated-values" = "org.xfce.mousepad.desktop";
      "text/x-tex" = "org.xfce.mousepad.desktop";
      "text/x-nix" = "org.xfce.mousepad.desktop";
      "application/x-shellscript" = "org.xfce.mousepad.desktop";
      "application/xml" = "org.xfce.mousepad.desktop";
      "application/json" = "org.xfce.mousepad.desktop";
      "application/x-yaml" = "org.xfce.mousepad.desktop";
      "application/toml" = "org.xfce.mousepad.desktop";
      "application/javascript" = "org.xfce.mousepad.desktop";
      "application/x-desktop" = "org.xfce.mousepad.desktop";

      # === Markdown Editor (Ghostwriter) ===
      "text/markdown" = "org.kde.ghostwriter.desktop";
      "text/x-markdown" = "org.kde.ghostwriter.desktop";

      # === Image Viewer (Gwenview) ===
      "image/png" = "org.kde.gwenview.desktop";
      "image/jpeg" = "org.kde.gwenview.desktop";
      "image/gif" = "org.kde.gwenview.desktop";
      "image/bmp" = "org.kde.gwenview.desktop";
      "image/x-bmp" = "org.kde.gwenview.desktop";
      "image/webp" = "org.kde.gwenview.desktop";
      "image/tiff" = "org.kde.gwenview.desktop";
      "image/x-tga" = "org.kde.gwenview.desktop";
      "image/x-ico" = "org.kde.gwenview.desktop";
      "image/vnd.microsoft.icon" = "org.kde.gwenview.desktop";
      "image/x-portable-pixmap" = "org.kde.gwenview.desktop";
      "image/x-portable-graymap" = "org.kde.gwenview.desktop";
      "image/x-portable-bitmap" = "org.kde.gwenview.desktop";
      "image/x-xpixmap" = "org.kde.gwenview.desktop";
      "image/x-xbitmap" = "org.kde.gwenview.desktop";
      "image/svg+xml" = "org.kde.gwenview.desktop";
      "image/svg+xml-compressed" = "org.kde.gwenview.desktop";
      "image/avif" = "org.kde.gwenview.desktop";
      "image/heif" = "org.kde.gwenview.desktop";
      "image/jxl" = "org.kde.gwenview.desktop";
      "image/x-eps" = "org.kde.gwenview.desktop";
      "image/x-pcx" = "org.kde.gwenview.desktop";

      # === Media Player (mpv) ===
      # Unified audio/video player using FFmpeg decoding and PipeWire audio
      "video/mp4" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "video/x-msvideo" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/mpeg" = "mpv.desktop";
      "video/x-flv" = "mpv.desktop";
      "video/ogg" = "mpv.desktop";
      "video/3gpp" = "mpv.desktop";
      "video/3gpp2" = "mpv.desktop";
      "video/x-ms-wmv" = "mpv.desktop";
      "video/x-ogm+ogg" = "mpv.desktop";
      "video/vnd.rn-realvideo" = "mpv.desktop";
      "video/mp2t" = "mpv.desktop";
      "audio/mpeg" = "mpv.desktop";
      "audio/mp4" = "mpv.desktop";
      "audio/flac" = "mpv.desktop";
      "audio/x-flac" = "mpv.desktop";
      "audio/ogg" = "mpv.desktop";
      "audio/x-vorbis+ogg" = "mpv.desktop";
      "audio/x-opus+ogg" = "mpv.desktop";
      "audio/wav" = "mpv.desktop";
      "audio/x-wav" = "mpv.desktop";
      "audio/aac" = "mpv.desktop";
      "audio/x-aac" = "mpv.desktop";
      "audio/x-ms-wma" = "mpv.desktop";
      "audio/webm" = "mpv.desktop";
      "audio/x-matroska" = "mpv.desktop";
      "audio/x-ape" = "mpv.desktop";
      "audio/x-wavpack" = "mpv.desktop";
      "audio/mp3" = "mpv.desktop";
      "audio/aiff" = "mpv.desktop";
      "audio/x-aiff" = "mpv.desktop";
      "audio/x-musepack" = "mpv.desktop";

      # === Document Viewer (Okular) ===
      "application/pdf" = "org.kde.okular.desktop";
      "application/epub+zip" = "org.kde.okular.desktop";
      "application/x-mobipocket-ebook" = "org.kde.okular.desktop";
      "application/x-fictionbook+xml" = "org.kde.okular.desktop";
      "application/x-cbz" = "org.kde.okular.desktop";
      "application/x-cbr" = "org.kde.okular.desktop";
      "application/x-cb7" = "org.kde.okular.desktop";
      "application/x-cbt" = "org.kde.okular.desktop";
      "application/vnd.ms-xpsdocument" = "org.kde.okular.desktop";
      "application/oxps" = "org.kde.okular.desktop";
      "image/vnd.djvu" = "org.kde.okular.desktop";
      "image/vnd.djvu+multipage" = "org.kde.okular.desktop";
      "application/postscript" = "org.kde.okular.desktop";
      "application/x-dvi" = "org.kde.okular.desktop";

      # === Archive Manager (Ark) ===
      "application/zip" = "org.kde.ark.desktop";
      "application/x-tar" = "org.kde.ark.desktop";
      "application/gzip" = "org.kde.ark.desktop";
      "application/x-gzip" = "org.kde.ark.desktop";
      "application/x-bzip2" = "org.kde.ark.desktop";
      "application/x-xz" = "org.kde.ark.desktop";
      "application/zstd" = "org.kde.ark.desktop";
      "application/x-zstd" = "org.kde.ark.desktop";
      "application/x-compressed-tar" = "org.kde.ark.desktop";
      "application/x-bzip2-compressed-tar" = "org.kde.ark.desktop";
      "application/x-xz-compressed-tar" = "org.kde.ark.desktop";
      "application/x-zstd-compressed-tar" = "org.kde.ark.desktop";
      "application/x-lzma-compressed-tar" = "org.kde.ark.desktop";
      "application/x-7z-compressed" = "org.kde.ark.desktop";
      "application/x-rar" = "org.kde.ark.desktop";
      "application/vnd.rar" = "org.kde.ark.desktop";
      "application/x-rpm" = "org.kde.ark.desktop";
      "application/x-deb" = "org.kde.ark.desktop";
      "application/x-lha" = "org.kde.ark.desktop";
      "application/x-lzop" = "org.kde.ark.desktop";
      "application/x-cpio" = "org.kde.ark.desktop";
      "application/x-archive" = "org.kde.ark.desktop";
      "application/x-lz4-compressed-tar" = "org.kde.ark.desktop";
      "application/x-java-archive" = "org.kde.ark.desktop";
      "application/x-arj" = "org.kde.ark.desktop";

      # === Drawing / Digital Art (Krita) ===
      "application/x-krita" = "org.kde.krita.desktop";
      "image/openraster" = "org.kde.krita.desktop";
      "application/x-photoshop" = "org.kde.krita.desktop";
      "image/x-psd" = "org.kde.krita.desktop";
      "image/x-xcf" = "org.kde.krita.desktop";

      # === Terminal (Ghostty) ===
      "x-scheme-handler/terminal" = "com.mitchellh.ghostty.desktop";
    };
  };

  # Override mousepad desktop entry to add StartupWMClass
  # The upstream desktop file is named org.xfce.mousepad.desktop but the GTK3 app
  # reports app-id "mousepad" on Wayland, so the dock can't match without this hint.
  xdg.desktopEntries."org.xfce.mousepad" = {
    name = "Mousepad";
    comment = "Simple Text Editor";
    genericName = "Text Editor";
    exec = "mousepad %U";
    icon = "org.xfce.mousepad";
    terminal = false;
    categories = [
      "Utility"
      "TextEditor"
      "GTK"
    ];
    mimeType = [
      "text/plain"
      "application/x-zerosize"
    ];
    settings = {
      StartupNotify = "true";
      StartupWMClass = "mousepad";
    };
  };

  # Flatpak install handler desktop entry
  # Opens .flatpakref files in a small Ghostty terminal window for transparent installation
  xdg.dataFile."applications/com.github.kcalvelli.cairn.flatpak-install.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Cairn Flatpak Installer
    Comment=Install Flatpak applications from .flatpakref files
    Exec=${pkgs.ghostty}/bin/ghostty --class=com.github.kcalvelli.cairn.flatpak-install -e cairn-flatpak-install %f
    MimeType=application/vnd.flatpak.ref;application/vnd.flatpak.repo;
    NoDisplay=true
    Terminal=false
    Icon=com.mitchellh.ghostty
  '';

  systemd.user.services.kdeconnect = {
    Service.Environment = [ "XDG_MENU_PREFIX=plasma-" ];
  };

  # Configure Dolphin to use Ghostty as terminal emulator
  # Uses kwriteconfig6 to set only this key, preserving color scheme and other settings
  home.activation.configureDolphinTerminal = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file dolphinrc --group General --key TerminalApplication ghostty
  '';

  # Mask KDE Activity Manager (Cairn uses Niri workspaces, not KDE Activities)
  # This removes the "Activities" context menu item from Dolphin and other KDE apps
  systemd.user.services.plasma-kactivitymanagerd = {
    Unit.Description = "KDE Activity Manager (masked by Cairn)";
    Install = { };
    Service.ExecStart = "${pkgs.coreutils}/bin/true";
  };

  # Solaar autostart for Logitech Unifying devices (hardware-conditional)
  # Solaar is installed by the system via programs.solaar.enable
  home.file.".config/autostart/solaar.desktop" = lib.mkIf (osConfig.programs.solaar.enable or false) {
    enable = true;
    force = true;
    text = ''
      [Desktop Entry]
      Name=Solaar
      Comment=Logitech Unifying Receiver peripherals manager
      Exec=solaar --window=hide --battery-icons=solaar
      Icon=solaar
      StartupNotify=true
      Terminal=false
      Type=Application
      Keywords=logitech;unifying;receiver;mouse;keyboard;
      Categories=Utility;GTK;
    '';
  };

  # Flatpak Flathub setup
  # Add Flathub remote for user-level flatpak installations
  # Runs during home-manager activation when network is available
  home.activation.setupFlathub = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    # Add Flathub remote for user flatpak (--if-not-exists makes it idempotent)
    $DRY_RUN_CMD ${pkgs.flatpak}/bin/flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
  '';
}
