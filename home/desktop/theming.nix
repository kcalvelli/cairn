{
  config,
  lib,
  pkgs,
  ...
}:

let
  codeExtDir = "${config.home.homeDirectory}/.vscode/extensions";
  base16ExtDir = "${codeExtDir}/danklinux.dms-theme-0.0.3";
in
{
  config = {
    # Basic theming for all WMs
    home.pointerCursor = {
      enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
      gtk.enable = true;
      x11.enable = true;
      dotIcons.enable = true;
    };

    # Note: GTK and Qt theming managed manually by user to avoid clobbering existing configs
    # Theming packages (papirus-icon-theme, adw-gtk3, qt5ct, qt6ct) installed in modules/desktop
    # Dynamic colors handled via dank-colors.css (GTK) and kdeglobals template (KDE/Qt apps)

    qt = {
      enable = true;
      platformTheme.name = "qt6ct";
    };

    home.sessionVariables = {
      QT_QPA_PLATFORMTHEME = "qt6ct";
      XCURSOR_THEME = "Bibata-Modern-Ice";
    };

    # Dank Colors integration
    xdg.configFile."gtk-4.0/gtk.css" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/gtk-4.0/dank-colors.css";
      force = true; # override anything the gtk module would write
    };

    xdg.configFile."gtk-3.0/gtk.css" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/gtk-3.0/dank-colors.css";
      force = true;
    };

    # Note: qt5ct/qt6ct configuration files are managed by the user via qt5ct/qt6ct GUI tools
    # The packages are installed in modules/desktop/default.nix
    # Users can configure icon themes (recommend Papirus-Dark) and color schemes via the GUI

    # Flatpak Theming
    dconf = {
      enable = true;
      settings = {
        "org/gnome/desktop/interface" = {
          "color-scheme" = "prefer-dark";
          # Pin middle-click (primary selection) paste ON for GTK apps.
          # The schema default is true, but it can get written to false in
          # dconf out-of-band (theming passes, stray gsettings writes) and
          # then silently kills middle-click paste across every GTK app.
          # Declaring it here makes it stick across rebuilds. GTK reads this
          # via xdg-desktop-portal; running apps pick it up on next launch.
          "gtk-enable-primary-paste" = true;
        };
      };
    };

    # Flatpak per-user overrides (GTK3 apps pick up your theme/cursor)
    xdg.dataFile."flatpak/overrides/global".text = ''
      [Context]
      filesystems=xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro
    '';

    # Deploy VSCode extension skeleton
    # DMS generates theme JSON files in themes/ directory, but needs the extension manifest
    home.file.".vscode/extensions/danklinux.dms-theme-0.0.3/package.json" = {
      source = ./resources/vscode-extension/package.json;
    };

    home.file.".vscode/extensions/danklinux.dms-theme-0.0.3/.vsixmanifest" = {
      source = ./resources/vscode-extension/.vsixmanifest;
    };

    home.file.".vscode/extensions/danklinux.dms-theme-0.0.3/README.md" = {
      source = ./resources/vscode-extension/README.md;
    };

    home.file.".vscode/extensions/danklinux.dms-theme-0.0.3/CHANGELOG.md" = {
      source = ./resources/vscode-extension/CHANGELOG.md;
    };

    home.file.".vscode/extensions/danklinux.dms-theme-0.0.3/LICENSE" = {
      source = ./resources/vscode-extension/LICENSE;
    };

    home.file.".vscode/extensions/danklinux.dms-theme-0.0.3/danklogo.png" = {
      source = ./resources/vscode-extension/danklogo.png;
    };

    # Also link the extension itself, as Antigravity appears to support VSCode-style extensions
    home.file.".antigravity/extensions/danklinux.dms-theme-0.0.3" = {
      source = config.lib.file.mkOutOfStoreSymlink base16ExtDir;
    };

    # Ensure VSCode extension themes directory exists (DMS will populate it)
    home.activation.createVSCodeThemesDir = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p ${config.home.homeDirectory}/.vscode/extensions/danklinux.dms-theme-0.0.3/themes
    '';

    # Matugen templates are fully managed by DMS via control panel checkboxes
    # Ensure the config directories exist for DMS to populate
    home.activation.ensureMatugenDirs = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p ${config.home.homeDirectory}/.config/matugen
      $DRY_RUN_CMD mkdir -p ${config.home.homeDirectory}/.config/matugen/templates
    '';

    # Register DMS VSCode extension so VSCode can detect it
    home.activation.registerVSCodeExtension = config.lib.dag.entryAfter [ "writeBoundary" ] ''
      if [ -d "${base16ExtDir}" ]; then
        $DRY_RUN_CMD chmod -R u+rwX "${base16ExtDir}" 2>/dev/null || true

        extJson="${codeExtDir}/extensions.json"
        extId="danklinux.dms-theme"

        # Ensure extensions.json exists
        if [ ! -f "$extJson" ]; then
          $DRY_RUN_CMD mkdir -p "${codeExtDir}"
          echo '[]' > "$extJson"
        fi

        # Remove old extension if it exists
        if grep -q "local.dynamic-base16-dankshell" "$extJson" 2>/dev/null; then
          echo "Removing old extension: local.dynamic-base16-dankshell"
          $DRY_RUN_CMD ${pkgs.jq}/bin/jq 'map(select(.identifier.id != "local.dynamic-base16-dankshell"))' "$extJson" > "$extJson.tmp" && mv "$extJson.tmp" "$extJson"
        fi

        # Only register if not already in extensions.json
        if ! grep -q "$extId" "$extJson" 2>/dev/null; then
          timestamp=$(date +%s)000

          # Add extension entry to extensions.json
          $DRY_RUN_CMD ${pkgs.jq}/bin/jq '. += [{
            "identifier": {"id": "'"$extId"'"},
            "version": "0.0.3",
            "location": {
              "$mid": 1,
              "path": "'"${base16ExtDir}"'",
              "scheme": "file"
            },
            "relativeLocation": "danklinux.dms-theme-0.0.3",
            "metadata": {
              "installedTimestamp": '"$timestamp"',
              "pinned": false,
              "source": "gallery",
              "targetPlatform": "undefined",
              "updated": false,
              "private": false,
              "isPreReleaseVersion": false,
              "hasPreReleaseVersion": false
            }
          }]' "$extJson" > "$extJson.tmp" && mv "$extJson.tmp" "$extJson"
        fi
      fi
    '';
  };
}
