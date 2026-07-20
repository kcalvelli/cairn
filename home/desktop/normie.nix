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
    ./pwa-apps.nix
    ./mpv.nix
    ./niri-keybinds-normie.nix
    inputs.niri.homeModules.niri
    inputs.dankMaterialShell.homeModules.niri
    inputs.dankMaterialShell.homeModules.dank-material-shell
    inputs.dms-plugin-registry.homeModules.default
  ];

  # Enable PWA apps by default for desktop users
  cairn.pwa.enable = true;

  # Configure sudo to use GUI password prompt
  home.sessionVariables = {
    SUDO_ASKPASS = "${pkgs.lxqt.lxqt-openssh-askpass}/bin/lxqt-openssh-askpass";
  };

  # DankMaterialShell configuration
  programs.dank-material-shell = {
    enable = true;
    quickshell.package = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;

    systemd = {
      enable = false;
      restartIfChanged = false;
    };

    enableSystemMonitoring = true;
    enableVPN = true;
    enableDynamicTheming = true;
    enableAudioWavelength = true;
    enableCalendarEvents = true;

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

  # Niri compositor configuration for normie profile
  programs = {
    niri.package = lib.mkForce pkgs.niri;
    dank-material-shell.niri = {
      enableKeybinds = true;
      enableSpawn = true;
      includes.filesToInclude = [
        "alttab"
        "colors"
        "cursor"
        "layout"
        "outputs"
        "windowrules"
        "wpblur"
      ];
    };
    niri.settings = {
      # Enable client-side decorations (titlebars with close/minimize/maximize)
      prefer-no-csd = false;
      screenshot-path = "~/Pictures/Screenshots/Screenshot-from-%Y-%m-%d-%H-%M-%S.png";
      hotkey-overlay.skip-at-startup = true;

      spawn-at-startup = [
        {
          command = [
            "${pkgs.dbus}/bin/dbus-update-activation-environment"
            "--systemd"
            "--all"
          ];
        }
        # Overview blur: DMS-native backdrop (seeded via
        # cairn.wallpapers.overviewBlur). No swaybg.
        # No cairn-help keybinding guide at startup
        # No drop-down terminal at startup
      ];

      layout = {
        border = {
          enable = false;
        };
        focus-ring = {
          enable = true;
        };
        background-color = "transparent";
        preset-column-widths = [
          { proportion = 1.0; }
          { proportion = 0.75; }
          { proportion = 0.5; }
          { proportion = 0.25; }
        ];
        tab-indicator = {
          hide-when-single-tab = true;
          place-within-column = true;
          position = "left";
          corner-radius = 20.0;
          gap = -12.0;
          gaps-between-tabs = 10.0;
          width = 4.0;
          length.total-proportion = 0.1;
        };
      };

      input = {
        touchpad = {
          natural-scroll = false;
          tap = true;
          tap-button-map = "left-right-middle";
          middle-emulation = true;
          accel-profile = "adaptive";
        };

        focus-follows-mouse = {
          enable = true;
          max-scroll-amount = "90%";
        };
        warp-mouse-to-focus.enable = true;
        workspace-auto-back-and-forth = true;
      };

      switch-events.lid-close.action.spawn = [
        "systemctl"
        "suspend"
      ];

      # Overview wallpaper backdrop placement is supplied by DMS's
      # auto-generated dms/wpblur.kdl (namespace "dms:blurwallpaper"),
      # already pulled in via includes.filesToInclude.

      window-rules = [
        {
          geometry-corner-radius =
            let
              radius = 12.0;
            in
            {
              bottom-left = radius;
              bottom-right = radius;
              top-left = radius;
              top-right = radius;
            };
          clip-to-geometry = true;
          draw-border-with-background = false;
        }
        {
          matches = [
            { is-floating = true; }
          ];
          shadow.enable = true;
        }
        {
          matches = [
            { app-id = ".*"; }
          ];
          open-maximized = true;
        }
        # Dolphin file manager — float, centered
        {
          matches = [
            { app-id = "^org.kde.dolphin$"; }
          ];
          open-maximized = false;
          open-floating = true;
          default-column-width = {
            fixed = 1200;
          };
          default-window-height = {
            fixed = 900;
          };
        }
        # Qalculate — float, centered, small calculator size
        {
          matches = [
            { app-id = "^io.github.Qalculate.qalculate-qt$"; }
          ];
          open-maximized = false;
          open-floating = true;
          default-column-width = {
            fixed = 500;
          };
          default-window-height = {
            fixed = 700;
          };
        }
        # Brave - picture in picture
        {
          matches = [
            {
              app-id = "brave-browser$";
              title = "^Picture-in-picture$";
            }
          ];
          open-maximized = false;
          open-floating = true;
        }
        # DMS settings
        {
          matches = [
            {
              # DMS 0.0.x renamed its Quickshell window from org.quickshell
              # to com.danklinux.dms. Dots escaped per the Nautilus rule below.
              app-id = "^com\\.danklinux\\.dms$";
              title = "^Settings$";
            }
          ];
          open-maximized = false;
          open-floating = true;
        }
        # Nautilus file manager — float, centered
        {
          matches = [
            { app-id = "^org\\.gnome\\.Nautilus$"; }
          ];
          open-maximized = false;
          open-floating = true;
          default-column-width = {
            fixed = 1200;
          };
          default-window-height = {
            fixed = 900;
          };
        }
        # Google Messages PWA — float, upper left
        {
          matches = [
            { app-id = "^chrome-messages\\.google\\.com__web-Default$"; }
          ];
          open-maximized = false;
          open-floating = true;
          default-column-width = {
            fixed = 500;
          };
          default-window-height = {
            fixed = 700;
          };
          default-floating-position = {
            x = 5;
            y = 5;
            relative-to = "top-left";
          };
        }
        # Flatpak installer: small floating window
        {
          matches = [
            { app-id = "^com\\.github\\.kcalvelli\\.cairn\\.flatpak-install$"; }
          ];
          open-maximized = false;
          open-floating = true;
          default-column-width = {
            fixed = 800;
          };
          default-window-height = {
            fixed = 400;
          };
        }
        # OpenSSH passphrase prompt: float, centered, compact
        {
          matches = [
            { title = "^OpenSSH Authentication Passphrase request$"; }
          ];
          open-maximized = false;
          open-floating = true;
          default-column-width = {
            fixed = 500;
          };
          default-window-height = {
            fixed = 200;
          };
        }
      ];
    };
  };

  # DMS KDL config placeholders (same as standard)
  home.activation.dmsPlaceholders = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dms_dir="${config.xdg.configHome}/niri/dms"
    mkdir -p "$dms_dir"
    for f in alttab binds colors cursor layout outputs windowrules wpblur; do
      if [ ! -e "$dms_dir/$f.kdl" ]; then
        echo '// Placeholder — DMS will overwrite this file with actual configuration' > "$dms_dir/$f.kdl"
      fi
    done
  '';

  # Desktop services
  # NOTE: gnome-keyring is started + unlocked by PAM at login (see
  # modules/desktop: security.pam.services.{greetd,login}.enableGnomeKeyring).
  # Do NOT also enable home-manager's services.gnome-keyring here — it spawns a
  # second daemon that can't auto-unlock and races the PAM one for the Secret
  # Service. PAM or the service, never both.
  services.kdeconnect = {
    enable = true;
    indicator = false;
  };

  # Default application associations (same as standard)
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/kdeconnect" = "org.kde.dolphin.desktop";
      "application/vnd.flatpak.ref" = "com.github.kcalvelli.cairn.flatpak-install.desktop";
      "application/vnd.flatpak.repo" = "com.github.kcalvelli.cairn.flatpak-install.desktop";
      "inode/directory" = "org.kde.dolphin.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/about" = "brave-browser.desktop";
      "x-scheme-handler/unknown" = "brave-browser.desktop";
      "text/html" = "brave-browser.desktop";
      "application/xhtml+xml" = "brave-browser.desktop";
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
      "text/markdown" = "org.kde.ghostwriter.desktop";
      "text/x-markdown" = "org.kde.ghostwriter.desktop";
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
      "application/x-krita" = "org.kde.krita.desktop";
      "image/openraster" = "org.kde.krita.desktop";
      "application/x-photoshop" = "org.kde.krita.desktop";
      "image/x-psd" = "org.kde.krita.desktop";
      "image/x-xcf" = "org.kde.krita.desktop";
    };
  };

  # Mousepad desktop entry override (same as standard)
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
  home.activation.configureDolphinTerminal = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file dolphinrc --group General --key TerminalApplication ghostty
  '';

  # Mask KDE Activity Manager
  systemd.user.services.plasma-kactivitymanagerd = {
    Unit.Description = "KDE Activity Manager (masked by Cairn)";
    Install = { };
    Service.ExecStart = "${pkgs.coreutils}/bin/true";
  };

  # Solaar autostart for Logitech Unifying devices (hardware-conditional)
  home.file.".config/autostart/solaar.desktop" =
    lib.mkIf (osConfig.hardware.logitech.wireless.enableGraphical or false)
      {
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
  home.activation.setupFlathub = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.flatpak}/bin/flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
  '';
}
