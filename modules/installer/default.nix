{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.cairn.installer;

  # Calamares ships without the Qt Wayland plugin. We add it via
  # QT_PLUGIN_PATH and run as root via sudo (live ISO = passwordless).
  # Two-stage launcher: outer captures session vars, inner runs as root.
  calamares-root-launcher = pkgs.writeShellScript "calamares-root-launcher" ''
    # This script runs AS ROOT (called via sudo).
    # Add Qt Wayland plugin so Calamares can run natively on Wayland.
    export QT_PLUGIN_PATH="${pkgs.qt6.qtwayland}/lib/qt-6/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
    export QT_QPA_PLATFORM=wayland
    export WAYLAND_DISPLAY="$1"
    export XDG_RUNTIME_DIR="$2"
    shift 2
    # Call the raw calamares binary directly (not calamares-nixos wrapper)
    # to avoid upstream calamares-nixos-extensions being prepended to XDG dirs.
    # Set XDG dirs to ONLY our extensions.
    export XDG_CONFIG_DIRS="${pkgs.calamares-cairn-extensions}/etc"
    export XDG_DATA_DIRS="${pkgs.calamares-cairn-extensions}/share"
    exec ${pkgs.calamares}/bin/calamares --xdg-config "$@"
  '';

  calamares-launcher = pkgs.writeShellScriptBin "calamares-launcher" ''
    exec sudo ${calamares-root-launcher} \
      "''${WAYLAND_DISPLAY:-wayland-1}" \
      "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
      "$@"
  '';

  calamares-autostart = pkgs.writeTextDir "etc/xdg/autostart/calamares.desktop" ''
    [Desktop Entry]
    Type=Application
    Name=Install Cairn
    Exec=${calamares-launcher}/bin/calamares-launcher
    Icon=calamares
    X-GNOME-Autostart-enabled=true
  '';
in
{
  options.cairn.installer = {
    enable = lib.mkEnableOption "Cairn graphical installer (Calamares)";
  };

  config = lib.mkIf cfg.enable {
    # ── Niri + DMS live session ───────────────────────────────
    programs.niri.enable = true;
    programs.xwayland.enable = true;
    programs.dconf.enable = true;

    # DMS system-level (no greeter — live ISO auto-logins directly)
    programs.dank-material-shell = {
      enable = true;
      quickshell.package = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
    # Live ISO auto-logins directly; keep the greeter off.
    programs.dms-greeter.enable = lib.mkForce false;

    environment.sessionVariables = {
      XDG_CURRENT_DESKTOP = "niri";
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_DESKTOP = "niri";
      NIXOS_OZONE_WL = "1";
      OZONE_PLATFORM = "wayland";
      ELECTRON_OZONE_PLATFORM_HINT = "auto";
    };

    # greetd auto-login — skip greeter entirely for live session
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "niri-session";
        user = "nixos";
      };
    };

    # Keyring and portal support
    security.pam.services.greetd.enableGnomeKeyring = true;
    services.gnome.gnome-keyring.enable = true;
    services.gvfs.enable = true;
    services.udisks2.enable = true;

    xdg.portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal-gnome
        pkgs.xdg-desktop-portal-gtk
      ];
      config.niri.default = [
        "gnome"
        "gtk"
      ];
    };

    # Niri binary cache for the ISO build
    nix.settings = {
      substituters = [ "https://niri.cachix.org" ];
      trusted-public-keys = [ "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964=" ];
    };

    # ── Home-manager for nixos live user (minimal DMS config) ─
    home-manager.users.nixos = {
      imports = [
        inputs.niri.homeModules.niri
        inputs.dankMaterialShell.homeModules.niri
        inputs.dankMaterialShell.homeModules.dank-material-shell
      ];

      home.stateVersion = "24.11";

      # DMS KDL config placeholders — niri includes these via KDL `include`
      # directives but DMS hasn't generated them yet on first boot.
      home.activation.dmsPlaceholders = inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        dms_dir="$HOME/.config/niri/dms"
        mkdir -p "$dms_dir"
        for f in alttab binds colors cursor layout outputs windowrules wpblur; do
          if [ ! -e "$dms_dir/$f.kdl" ]; then
            echo '// Placeholder' > "$dms_dir/$f.kdl"
          fi
        done
      '';

      programs.niri = {
        package = lib.mkForce pkgs.niri;
        settings = {
          prefer-no-csd = true;
          hotkey-overlay.skip-at-startup = true;
          spawn-at-startup = [
            # XWayland support for X11 apps
            { command = [ "${pkgs.xwayland-satellite}/bin/xwayland-satellite" ]; }
            {
              command = [
                "dbus-update-activation-environment"
                "--systemd"
                "DISPLAY"
                "WAYLAND_DISPLAY"
                "XDG_CURRENT_DESKTOP"
                "XDG_SESSION_TYPE"
                "XDG_SESSION_DESKTOP"
                "NIXOS_OZONE_WL"
              ];
            }
          ];
        };
      };

      programs.dank-material-shell = {
        enable = true;
        quickshell.package = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
        systemd.enable = false;
        niri = {
          enableKeybinds = true;
          enableSpawn = true;
        };
      };
    };

    # ── Calamares installer ───────────────────────────────────
    programs.partition-manager.enable = true;

    # Remove default NixOS ISO apps (firefox, etc.)
    environment.defaultPackages = lib.mkForce [ ];

    environment.systemPackages = [
      # Calamares
      calamares-launcher
      calamares-autostart
      pkgs.calamares-nixos
      pkgs.calamares-cairn-extensions
      pkgs.glibcLocales
      pkgs.xwayland-satellite

      # Icon themes (needed for app icons in DMS/taskbar)
      pkgs.colloid-icon-theme
      pkgs.adwaita-icon-theme
      pkgs.papirus-icon-theme
      pkgs.hicolor-icon-theme

      # Cairn live session apps (normie subset)
      pkgs.brave
      pkgs.kdePackages.dolphin
      pkgs.kdePackages.ark
      pkgs.kdePackages.gwenview
      pkgs.kdePackages.okular
      pkgs.ghostty
      pkgs.mousepad
      pkgs.qalculate-qt
      pkgs.fuzzel
      pkgs.pavucontrol
    ];

    # Support all locales for the installer
    i18n.supportedLocales = [ "all" ];
  };
}
