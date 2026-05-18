{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.cairn.wallpapers;

  # Wallpaper change hook script for DankMaterialShell
  # This is a hook script called by Dank Hooks plugin with:
  # $1 = hook name ("onWallpaperChanged")
  # $2 = wallpaper path
  wallpaperChangedScript = ../../scripts/wallpaper-changed.sh;

  # Directory containing curated wallpapers
  wallpapersDir = ../resources/wallpapers;

  # Get list of wallpaper files
  wallpaperFiles = builtins.filter (
    name: lib.hasSuffix ".jpg" name || lib.hasSuffix ".png" name || lib.hasSuffix ".jpeg" name
  ) (builtins.attrNames (builtins.readDir wallpapersDir));

  # Generate home.file entries for each wallpaper
  wallpaperFileEntries = builtins.listToAttrs (
    map (filename: {
      name = "Pictures/Wallpapers/${filename}";
      value = {
        source = wallpapersDir + "/${filename}";
      };
    }) wallpaperFiles
  );
in
{
  options.cairn.wallpapers = {
    enable = lib.mkEnableOption "curated wallpaper collection";

    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically set a new random wallpaper when the wallpaper collection changes.
        If false, wallpaper files will still be updated, but the active wallpaper won't change.
      '';
    };

    overviewBlur = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Seed the DankMaterialShell `blurredWallpaperLayer` setting so the
        niri overview shows DMS's native blurred-wallpaper backdrop out of
        the box. Seeded at most once, only when the key is absent from
        DMS's on-disk settings; once DMS or the user (via the DMS GUI)
        owns the key it is never touched again, so the DMS GUI remains the
        runtime opt-out. This option only sets the *default* — it is not a
        reconciler and does not fight the GUI.
      '';
    };
  };

  config = lib.mkMerge [
    # Base wallpaper configuration (always enabled)
    {
      # Wallpaper management scripts for DankMaterialShell
      home.file."scripts/wallpaper-changed.sh" = {
        source = wallpaperChangedScript;
        executable = true;
      };

      # Seed DMS's native overview-blur default exactly once, then hand
      # ownership to DMS. Sentinel is a dedicated marker file, NOT the
      # presence of the `blurredWallpaperLayer` key: DMS persists every
      # settings key (defaults included) on its first save, so the key is
      # present for anyone who has ever launched DMS and a key-absent gate
      # would never fire. Mirrors the setRandomWallpaper hash-sentinel in
      # this file. Marker is written only on confirmed success, so an
      # unconfirmed attempt retries next activation. Prefer the DMS IPC
      # setter when DMS is up (applies live, persists via saveSettings, no
      # clobber race); fall back to a jq write when DMS is down.
      home.activation.seedOverviewBlur = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        SETTINGS="$HOME/.config/DankMaterialShell/settings.json"
        MARKER="$HOME/.cache/cairn-overview-blur-seeded"
        DESIRED=${lib.boolToString cfg.overviewBlur}
        JQ=${pkgs.jq}/bin/jq
        DMS=${inputs.dankMaterialShell.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/dms

        if [ ! -f "$MARKER" ]; then
          SEEDED=0
          # Best-effort IPC first; DMS performs the write itself.
          if "$DMS" ipc call settings set blurredWallpaperLayer "$DESIRED" 2>/dev/null \
            | grep -q SETTINGS_SET_SUCCESS; then
            SEEDED=1
            [ -n "''${VERBOSE:-}" ] && echo "Cairn: seeded overview blur ($DESIRED) via DMS IPC"
          elif [ ! -f "$SETTINGS" ]; then
            # DMS not running and no settings yet: write a partial file.
            $DRY_RUN_CMD mkdir -p "$(dirname "$SETTINGS")"
            $DRY_RUN_CMD echo "{\"blurredWallpaperLayer\": $DESIRED}" > "$SETTINGS"
            SEEDED=1
            [ -n "''${VERBOSE:-}" ] && echo "Cairn: seeded overview blur ($DESIRED) via new settings.json"
          elif "$JQ" empty "$SETTINGS" >/dev/null 2>&1; then
            # DMS not running, settings parseable: set the key outright
            # (this is the one-time marker-gated seed, not a merge).
            tmp=$(${pkgs.coreutils}/bin/mktemp)
            if "$JQ" --argjson v "$DESIRED" '.blurredWallpaperLayer = $v' \
              "$SETTINGS" > "$tmp" 2>/dev/null; then
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$tmp" "$SETTINGS"
              SEEDED=1
              [ -n "''${VERBOSE:-}" ] && echo "Cairn: seeded overview blur ($DESIRED) via jq"
            else
              ${pkgs.coreutils}/bin/rm -f "$tmp"
            fi
          fi
          # Unparseable settings.json with DMS down, or IPC unavailable
          # while DMS is up: SEEDED stays 0, no marker, retry next time.

          if [ "$SEEDED" = "1" ]; then
            $DRY_RUN_CMD mkdir -p "$(dirname "$MARKER")"
            $DRY_RUN_CMD touch "$MARKER"
          fi
        fi

        # Clean the orphaned baked-blur JPEG from the retired pipeline.
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$HOME/.cache/niri/overview-blur.jpg"
      '';
    }

    # Wallpaper collection (conditional)
    (lib.mkIf cfg.enable {
      # Ensure wallpapers directory exists (before linkGeneration processes home.file entries)
      home.activation.createWallpapersDir = config.lib.dag.entryBefore [ "linkGeneration" ] ''
        $DRY_RUN_CMD mkdir -p $HOME/Pictures/Wallpapers
      '';

      # Deploy curated wallpapers to ~/Pictures/Wallpapers
      home.file = wallpaperFileEntries // {
        # Tell Syncthing to ignore Wallpapers directory (managed by home-manager symlinks)
        # .stignore is per-device and never synced, so this is safe
        "Pictures/.stignore".text = "/Wallpapers\n";
      };

      # Set random wallpaper on first activation or when collection changes
      home.activation.setRandomWallpaper = lib.mkIf cfg.autoUpdate (
        config.lib.dag.entryAfter [ "writeBoundary" ] ''
          WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
          HASH_FILE="$HOME/.cache/cairn-wallpaper-collection-hash"

          # Create a hash of the wallpaper collection (sorted filenames)
          if [ -d "$WALLPAPER_DIR" ]; then
            CURRENT_HASH=$(find "$WALLPAPER_DIR" -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" \) -printf "%f\n" | sort | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d' ' -f1)

            # Read previous hash if it exists
            PREVIOUS_HASH=""
            if [ -f "$HASH_FILE" ]; then
              PREVIOUS_HASH=$(cat "$HASH_FILE")
            fi

            # If hash changed (or first run), set a new random wallpaper
            if [ "$CURRENT_HASH" != "$PREVIOUS_HASH" ]; then
              # Get list of wallpapers
              wallpapers=("$WALLPAPER_DIR"/*.{jpg,png,jpeg})

              # Check if any wallpapers exist (glob expansion check)
              if [ -f "''${wallpapers[0]}" ]; then
                # Select random wallpaper
                random_index=$((RANDOM % ''${#wallpapers[@]}))
                random_wallpaper="''${wallpapers[$random_index]}"

                # Set wallpaper using dms (may fail during activation if DMS isn't fully initialized)
                if $DRY_RUN_CMD ${
                  inputs.dankMaterialShell.packages.${pkgs.stdenv.hostPlatform.system}.default
                }/bin/dms ipc call wallpaper set "$random_wallpaper" 2>/dev/null; then
                  # Only save hash if wallpaper was successfully set
                  $DRY_RUN_CMD mkdir -p "$(dirname "$HASH_FILE")"
                  $DRY_RUN_CMD echo "$CURRENT_HASH" > "$HASH_FILE"

                  if [ -n "''${VERBOSE:-}" ]; then
                    echo "Cairn: Wallpaper collection changed, set new random wallpaper: $random_wallpaper"
                  fi
                else
                  # DMS not ready during activation, will try again on next rebuild
                  if [ -n "''${VERBOSE:-}" ]; then
                    echo "Cairn: Wallpaper collection ready at $WALLPAPER_DIR, but DMS not available during activation"
                    echo "Cairn: Wallpaper will be set on next login or rebuild"
                  fi
                fi
              fi
            fi
          fi
        ''
      );
    })
  ];
}
