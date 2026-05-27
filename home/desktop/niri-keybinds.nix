{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Keybinding reference for cairn niri configuration
  # Union of Niri defaults + DMS features + cairn customizations
  keybindingGuide = pkgs.writeText "niri-keybindings.txt" ''
    ╔══════════════════════════════════════════════════════════════════╗
    ║              Cairn Niri Keybinding Reference                     ║
    ║         Niri Defaults + DMS Features + cairn Apps                ║
    ╚══════════════════════════════════════════════════════════════════╝

    ┌─ CORE ACTIONS ───────────────────────────────────────────────────┐
    │ Mod + T           Launch Terminal (Ghostty) [Niri default]       │
    │ Mod + Return      Launch Terminal (alternative)                  │
    │ Mod + Space       Application Launcher (DMS Spotlight)           │
    │ Mod + Q           Close focused window                           │
    │ Mod + Shift + E   Exit Niri                                      │
    │ Mod + Shift + /   Show this keybinding guide                     │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ APPLICATION LAUNCHERS (cairn) ──────────────────────────────────┐
    │ Mod + B           Launch Brave Browser                           │
    │ Mod + D           Launch Discord                                 │
    │ Mod + E           Launch File Manager (Dolphin)                  │
    │ Mod + G           Launch Google Messages (PWA)                   │
    │ Mod + Shift + V   Launch VS Code                                 │
    │ Mod + Shift + T   Launch Text Editor (Mousepad)                   │
    │ Mod + Shift + C   Launch Calculator (Qalculate)                  │
    │ Mod + `           Toggle Drop-down Terminal (Quake-style)        │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ DMS FEATURES ───────────────────────────────────────────────────┐
    │ Mod + N           Notification Center                            │
    │ Mod + Comma       Settings Panel                                 │
    │ Mod + P           Notepad                                        │
    │ Mod + V           Clipboard Manager                              │
    │ Mod + X           Power Menu                                     │
    │ Mod + M           Process List (System Monitor)                  │
    │ Mod + Alt + N     Toggle Night Mode                              │
    │ Super + Alt + L   Lock Screen                                    │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ WINDOW NAVIGATION ──────────────────────────────────────────────┐
    │ Mod + H/←         Focus column left                              │
    │ Mod + J/↓         Focus window down (in column)                  │
    │ Mod + K/↑         Focus window up (in column)                    │
    │ Mod + L/→         Focus column right                             │
    │ Mod + Home        Focus first column                             │
    │ Mod + End         Focus last column                              │
    │ Mod + Wheel ←/→   Focus column left/right (mouse)                │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ WINDOW & COLUMN MOVEMENT ───────────────────────────────────────┐
    │ Mod + Ctrl + H/←  Move column left                               │
    │ Mod + Ctrl + J/↓  Move window down (in column)                   │
    │ Mod + Ctrl + K/↑  Move window up (in column)                     │
    │ Mod + Ctrl + L/→  Move column right                              │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ MONITOR MANAGEMENT ─────────────────────────────────────────────┐
    │ Mod + Shift + H   Focus monitor left                             │
    │ Mod + Shift + J   Focus monitor down                             │
    │ Mod + Shift + K   Focus monitor up                               │
    │ Mod + Shift + L   Focus monitor right                            │
    │ Mod+Ctrl+Shift+H  Move column to monitor left                    │
    │ Mod+Ctrl+Shift+J  Move column to monitor down                    │
    │ Mod+Ctrl+Shift+K  Move column to monitor up                      │
    │ Mod+Ctrl+Shift+L  Move column to monitor right                   │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ WORKSPACE NAVIGATION ───────────────────────────────────────────┐
    │ Mod + 1-9         Switch to workspace 1-9                        │
    │ Mod + Tab         Toggle workspace overview                      │
    │ Mod + U           Focus workspace down                           │
    │ Mod + I           Focus workspace up                             │
    │ Mod + Page Dn/Up  Focus workspace down/up (alternative)          │
    │ Mod + Wheel ↑/↓   Focus workspace up/down (mouse)                │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ MOVE WINDOW TO WORKSPACE ───────────────────────────────────────┐
    │ Mod + Shift + 1-9 Move focused window to workspace 1-9           │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ MOVE COLUMN TO WORKSPACE ───────────────────────────────────────┐
    │ Mod + Ctrl + 1-9         Move column to workspace 1-9            │
    │ Mod + Ctrl + U           Move column to workspace down           │
    │ Mod + Ctrl + I           Move column to workspace up             │
    │ Mod + Ctrl + Page Dn/Up  Move column to workspace down/up        │
    │ Mod + Ctrl + Wheel ↑/↓   Move column to workspace up/down        │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ LAYOUT & SIZING ────────────────────────────────────────────────┐
    │ Mod + F           Maximize column                                │
    │ Mod + Shift + F   Fullscreen focused window                      │
    │ Mod + C           Center focused column                          │
    │ Mod + R           Cycle preset column widths                     │
    │ Mod + Shift + R   Cycle preset window heights                    │
    │ Mod + -           Decrease column width (-10%)                   │
    │ Mod + =           Increase column width (+10%)                   │
    │ Mod + Shift + -   Decrease window height (-10%)                  │
    │ Mod + Shift + =   Increase window height (+10%)                  │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ COLUMN WINDOW MANAGEMENT ───────────────────────────────────────┐
    │ Mod + Shift + ,   Consume window into column (from right)        │
    │ Mod + Shift + .   Expel window from column (to right)            │
    │ Mod + Period      Expel window from column (Niri default)        │
    │ Mod + [           Consume/expel window to the left               │
    │ Mod + ]           Consume/expel window to the right              │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ FLOATING WINDOWS ───────────────────────────────────────────────┐
    │ Mod + Shift + Z   Toggle window floating mode                    │
    │ Mod + Z           Switch focus between floating and tiling       │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ SCREENSHOTS ────────────────────────────────────────────────────┐
    │ Print             Interactive area selection [Niri default]      │
    │ Alt + Print       Screenshot focused window [Niri default]       │
    │ Ctrl + Print      Screenshot focused monitor [Niri default]      │
    │ Mod + Shift + S   Screenshot with area selection (alternative)   │
    │ Mod + Ctrl + S    Screenshot screen to disk (alternative)        │
    │ Mod + Alt + S     Screenshot screen to clipboard (alternative)   │
    │ Mod + Shift + Ctrl + S   Screenshot region to disk (grim+slurp) │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ SCREEN RECORDING ───────────────────────────────────────────────┐
    │ Mod + Alt + R     Toggle screen recording (start/stop)           │
    │ Mod + Ctrl + R    Record screen area (with selection)            │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ AUDIO CONTROL ──────────────────────────────────────────────────┐
    │ XF86AudioRaiseVolume    Volume up (media key) [DMS]             │
    │ XF86AudioLowerVolume    Volume down (media key) [DMS]           │
    │ XF86AudioMute           Toggle mute (media key) [DMS]           │
    │ XF86AudioMicMute        Toggle mic mute (media key) [DMS]       │
    │ Mod + Shift + Wheel ←   Volume up (+3%) (mouse)                 │
    │ Mod + Shift + Wheel →   Volume down (-3%) (mouse)               │
    │ Mod + Shift + M         Toggle mute                             │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ BRIGHTNESS CONTROL ─────────────────────────────────────────────┐
    │ XF86MonBrightnessUp     Brightness up (media key) [DMS]         │
    │ XF86MonBrightnessDown   Brightness down (media key) [DMS]       │
    └──────────────────────────────────────────────────────────────────┘

    ┌─ NOTES ──────────────────────────────────────────────────────────┐
    │ • Mod = Super (Windows key)                                      │
    │ • [Niri default] = Standard Niri compositor keybinding           │
    │ • [DMS] = DankMaterialShell feature                              │
    │ • Screenshots saved to: ~/Pictures/Screenshots/                  │
    │ • Screen recordings saved to: ~/Videos/                          │
    │                                                                  │
    │ This configuration provides the union of:                        │
    │   - Niri default keybindings (no conflicts)                      │
    │   - DMS system integration features                              │
    │   - cairn custom application launchers                           │
    └──────────────────────────────────────────────────────────────────┘
  '';

  # Script to display keybindings in a terminal with proper scrolling
  showKeybindings = pkgs.writeShellScript "show-niri-keybindings" ''
    # Center text in terminal (80 columns wide)
    center_text() {
      ${pkgs.gawk}/bin/awk '{
        width = 80
        len = length($0)
        if (len < width) {
          padding = int((width - len) / 2)
          printf "%*s%s\n", padding, "", $0
        } else {
          print $0
        }
      }'
    }

    # Display centered text with less for scrolling
    # -R: handle ANSI colors
    # -F: quit if content fits on one screen
    # -X: don't clear screen on exit
    ${pkgs.coreutils}/bin/cat ${keybindingGuide} | center_text | ${pkgs.less}/bin/less -RFX
  '';

in
{
  # Make the keybinding guide available as a command
  home.packages = [
    (pkgs.writeShellScriptBin "cairn-help" ''
      # Display in a floating terminal window sized for readability on all screens
      # Note: Window rule matches by title since Ghostty doesn't allow custom app-id
      ${pkgs.ghostty}/bin/ghostty \
        --title="Niri Keybindings - Cairn" \
        --window-width=80 \
        --window-height=40 \
        -e ${showKeybindings}
    '')
  ];

  # Add keybinding to show the guide
  programs.niri.settings.binds = {
    "Mod+Shift+Slash".action.spawn = [ "cairn-help" ];

    # --- NIRI DEFAULTS: Core Actions ---
    "Mod+T".action.spawn = "ghostty"; # Niri default terminal
    "Mod+Q".action."close-window" = [ ];
    "Mod+Shift+E".action."quit" = [ ];

    # --- CAIRN: App launches (non-conflicting keys) ---
    "Mod+B".action.spawn = [
      "brave"
      "--class=brave-browser"
    ];
    "Mod+D".action.spawn = [ "discord" ]; # OK - DMS uses Mod+Space for launcher
    "Mod+E".action.spawn = [ "dolphin" ];
    "Mod+Return".action.spawn = "ghostty"; # Alternative terminal binding
    "Mod+G".action.spawn = [ "pwa-google-messages" ];
    "Mod+Shift+V".action.spawn = [ "code" ]; # MOVED from Mod+C (was conflicting)
    "Mod+Shift+T".action.spawn = [ "mousepad" ];
    "Mod+Shift+C".action.spawn = [ "focus-or-spawn-qalculate" ];

    # --- NIRI DEFAULTS: Workspace jump directly (1..9) ---
    "Mod+1".action."focus-workspace" = [ 1 ];
    "Mod+2".action."focus-workspace" = [ 2 ];
    "Mod+3".action."focus-workspace" = [ 3 ];
    "Mod+4".action."focus-workspace" = [ 4 ];
    "Mod+5".action."focus-workspace" = [ 5 ];
    "Mod+6".action."focus-workspace" = [ 6 ];
    "Mod+7".action."focus-workspace" = [ 7 ];
    "Mod+8".action."focus-workspace" = [ 8 ];
    "Mod+9".action."focus-workspace" = [ 9 ]; # Extended to 9

    # --- NIRI DEFAULTS: Window/Column Navigation ---
    "Mod+H".action.focus-column-left = [ ];
    "Mod+J".action.focus-window-down = [ ];
    "Mod+K".action.focus-window-up = [ ];
    "Mod+L".action.focus-column-right = [ ];

    "Mod+Left".action.focus-column-left = [ ];
    "Mod+Down".action.focus-window-down = [ ];
    "Mod+Up".action.focus-window-up = [ ];
    "Mod+Right".action.focus-column-right = [ ];

    # RESTORED: Focus first/last column
    "Mod+Home".action.focus-column-first = [ ];
    "Mod+End".action.focus-column-last = [ ];

    # CAIRN: Mouse wheel focus column left/right
    "Mod+WheelScrollLeft" = {
      cooldown-ms = 150;
      action.focus-column-left = [ ];
    };
    "Mod+WheelScrollRight" = {
      cooldown-ms = 150;
      action.focus-column-right = [ ];
    };

    # --- NIRI DEFAULTS: Window/Column Movement ---
    "Mod+Ctrl+H".action.move-column-left = [ ];
    "Mod+Ctrl+J".action.move-window-down = [ ];
    "Mod+Ctrl+K".action.move-window-up = [ ];
    "Mod+Ctrl+L".action.move-column-right = [ ];

    "Mod+Ctrl+Left".action.move-column-left = [ ];
    "Mod+Ctrl+Down".action.move-window-down = [ ];
    "Mod+Ctrl+Up".action.move-window-up = [ ];
    "Mod+Ctrl+Right".action.move-column-right = [ ];

    # --- NIRI DEFAULTS: Monitor Management ---
    # RESTORED: Focus monitor in direction
    "Mod+Shift+H".action.focus-monitor-left = [ ];
    "Mod+Shift+J".action.focus-monitor-down = [ ];
    "Mod+Shift+K".action.focus-monitor-up = [ ];
    "Mod+Shift+L".action.focus-monitor-right = [ ];

    # ADDED: Move column to monitor
    "Mod+Ctrl+Shift+H".action.move-column-to-monitor-left = [ ];
    "Mod+Ctrl+Shift+J".action.move-column-to-monitor-down = [ ];
    "Mod+Ctrl+Shift+K".action.move-column-to-monitor-up = [ ];
    "Mod+Ctrl+Shift+L".action.move-column-to-monitor-right = [ ];

    # --- NIRI DEFAULTS: Move focused window to workspace N ---
    "Mod+Shift+1".action."move-window-to-workspace" = [ 1 ];
    "Mod+Shift+2".action."move-window-to-workspace" = [ 2 ];
    "Mod+Shift+3".action."move-window-to-workspace" = [ 3 ];
    "Mod+Shift+4".action."move-window-to-workspace" = [ 4 ];
    "Mod+Shift+5".action."move-window-to-workspace" = [ 5 ];
    "Mod+Shift+6".action."move-window-to-workspace" = [ 6 ];
    "Mod+Shift+7".action."move-window-to-workspace" = [ 7 ];
    "Mod+Shift+8".action."move-window-to-workspace" = [ 8 ];
    "Mod+Shift+9".action."move-window-to-workspace" = [ 9 ];

    # --- NIRI DEFAULTS: Move focused column to workspace N ---
    # CHANGED from Mod+Ctrl+Shift to Mod+Ctrl (Niri default)
    "Mod+Ctrl+1".action.move-column-to-workspace = "1";
    "Mod+Ctrl+2".action.move-column-to-workspace = "2";
    "Mod+Ctrl+3".action.move-column-to-workspace = "3";
    "Mod+Ctrl+4".action.move-column-to-workspace = "4";
    "Mod+Ctrl+5".action.move-column-to-workspace = "5";
    "Mod+Ctrl+6".action.move-column-to-workspace = "6";
    "Mod+Ctrl+7".action.move-column-to-workspace = "7";
    "Mod+Ctrl+8".action.move-column-to-workspace = "8";
    "Mod+Ctrl+9".action.move-column-to-workspace = "9";

    # --- NIRI DEFAULTS: Layout & Sizing ---
    # RESTORED: Maximize column
    "Mod+F".action.maximize-column = [ ];

    "Mod+Shift+F".action."fullscreen-window" = [ ];

    # RESTORED: Center column (was conflicting with VS Code)
    "Mod+C".action.center-column = [ ];

    # Column width adjustment
    "Mod+Minus".action.set-column-width = "-10%";
    "Mod+Equal".action.set-column-width = "+10%";

    # RESTORED: Niri default for cycling column widths (was Mod+W)
    "Mod+R".action.switch-preset-column-width = [ ];

    # RESTORED: Cycle window heights (was screen recording)
    "Mod+Shift+R".action.switch-preset-window-height = [ ];

    # RESTORED: Window height adjustment (was volume control)
    "Mod+Shift+Minus".action.set-window-height = "-10%";
    "Mod+Shift+Equal".action.set-window-height = "+10%";

    # --- NIRI DEFAULTS: Window consume/expel ---
    "Mod+Shift+Comma".action.consume-window-into-column = { };
    "Mod+Shift+Period".action.expel-window-from-column = { };

    # ADDED: Niri default expel
    "Mod+Period".action.expel-window-from-column = { };

    # Consume/expel window left/right
    "Mod+BracketLeft".action.consume-or-expel-window-left = [ ];
    "Mod+BracketRight".action.consume-or-expel-window-right = [ ];

    # --- CAIRN: Overview ---
    "Mod+Tab".action."toggle-overview" = [ ];

    # --- NIRI DEFAULTS: Floating ---
    "Mod+Shift+Z".action."toggle-window-floating" = [ ];
    "Mod+Z".action."switch-focus-between-floating-and-tiling" = [ ];

    # --- NIRI DEFAULTS: Workspace navigation ---
    # ADDED: U/I for workspace navigation (Niri default)
    "Mod+U".action.focus-workspace-down = { };
    "Mod+I".action.focus-workspace-up = { };

    # Keep Page_Up/Down as alternatives
    "Mod+Page_Down".action.focus-workspace-down = { };
    "Mod+Page_Up".action.focus-workspace-up = { };

    # CAIRN: Wheel scroll variants
    "Mod+WheelScrollDown" = {
      cooldown-ms = 150;
      action.focus-workspace-down = { };
    };
    "Mod+WheelScrollUp" = {
      cooldown-ms = 150;
      action.focus-workspace-up = { };
    };

    # --- NIRI DEFAULTS: Move column to workspace ---
    # ADDED: U/I for moving column (Niri default)
    "Mod+Ctrl+U".action.move-column-to-workspace-down = { };
    "Mod+Ctrl+I".action.move-column-to-workspace-up = { };

    # Keep Page_Up/Down as alternatives
    "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = { };
    "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = { };

    # CAIRN: Wheel scroll variants
    "Mod+Ctrl+WheelScrollDown" = {
      cooldown-ms = 150;
      action.move-column-to-workspace-down = { };
    };
    "Mod+Ctrl+WheelScrollUp" = {
      cooldown-ms = 150;
      action.move-column-to-workspace-up = { };
    };

    # --- CAIRN: Volume control (wheel only, removed keyboard) ---
    # Wheel bindings
    "Mod+Shift+WheelScrollLeft".action.spawn = [
      "dms"
      "ipc"
      "call"
      "audio"
      "increment"
      "3"
    ];
    "Mod+Shift+WheelScrollRight".action.spawn = [
      "dms"
      "ipc"
      "call"
      "audio"
      "decrement"
      "3"
    ];

    # Mute toggle
    "Mod+Shift+M".action.spawn = [
      "dms"
      "ipc"
      "call"
      "audio"
      "mute"
    ];

    # --- NIRI DEFAULTS: Screenshots ---
    # Standard Print key variants
    "Print".action.screenshot = { };
    "Alt+Print".action.screenshot-window = { };
    "Ctrl+Print".action.screenshot-screen = {
      write-to-disk = true;
    };

    # CAIRN: Alternative screenshot bindings (keep for compatibility)
    "Mod+Shift+S".action.screenshot = { };
    "Mod+Ctrl+S".action.screenshot-screen = {
      write-to-disk = true;
    };
    "Mod+Alt+S".action.screenshot-screen = { };

    # CAIRN: Region-to-disk screenshot (one-shot, no interactive UI)
    "Mod+Shift+Ctrl+S".action.spawn = [
      "${pkgs.bash}/bin/bash"
      "-c"
      ''
        mkdir -p ~/Pictures/Screenshots
        out=~/Pictures/Screenshots/Screenshot-from-$(date +%Y-%m-%d-%H-%M-%S).png
        ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" "$out" && \
          ${pkgs.libnotify}/bin/notify-send "Screenshot saved" "$out" -i image-x-generic
      ''
    ];

    # --- CAIRN: Screen Recording ---
    # MOVED from Mod+Shift+R to Mod+Alt+R (was conflicting)
    "Mod+Alt+R".action.spawn = [
      "${pkgs.bash}/bin/bash"
      "-c"
      ''
        if pgrep -x wf-recorder > /dev/null; then
          pkill -INT wf-recorder
          notify-send "Screen Recording" "Recording stopped" -i video-x-generic
        else
          mkdir -p ~/Videos
          wf-recorder -f ~/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4 &
          notify-send "Screen Recording" "Recording started" -i media-record
        fi
      ''
    ];

    # Record with area selection
    "Mod+Ctrl+R".action.spawn = [
      "${pkgs.bash}/bin/bash"
      "-c"
      ''
        mkdir -p ~/Videos
        wf-recorder -g "$(slurp)" -f ~/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4 &
        notify-send "Screen Recording" "Area recording started" -i media-record
      ''
    ];

    # --- CAIRN: Quake style drop down terminal ---
    "Mod+grave".action.spawn = [
      "${pkgs.bash}/bin/bash"
      "-c"
      ''
        # Get dropterm window ID if it exists
        dropterm_id=$(niri msg windows | ${pkgs.gnugrep}/bin/grep -B2 'App ID: "com.github.kcalvelli.cairn.dropterm"' | ${pkgs.gnugrep}/bin/grep 'Window ID' | ${pkgs.gawk}/bin/awk '{print $3}' | ${pkgs.gnused}/bin/sed 's/://')

        if [ -n "$dropterm_id" ]; then
          # Check if it's focused
          if niri msg windows | ${pkgs.gnugrep}/bin/grep -A1 "Window ID $dropterm_id:" | ${pkgs.gnugrep}/bin/grep -q "(focused)"; then
            # Close if focused
            niri msg action close-window
          else
            # Focus if not focused
            niri msg action focus-window --id "$dropterm_id"
          fi
        else
          # Spawn new window using resident daemon (instant)
          ${pkgs.ghostty}/bin/ghostty \
            --gtk-single-instance=true \
            --class=com.github.kcalvelli.cairn.dropterm \
            --window-decoration=none &
        fi
      ''
    ];
  };

  # Window rule for the keybinding reference window
  # Make it float and center on screen, sized appropriately for small displays
  programs.niri.settings.window-rules = [
    {
      matches = [
        { title = "Niri Keybindings - Cairn"; }
      ];
      open-maximized = false;
      open-floating = true;
      # Comfortable size that fits on 1366x768 displays and larger
      default-column-width = {
        fixed = 900;
      };
      default-window-height = {
        fixed = 700;
      };
    }
  ];

  # Also make the raw text file available
  xdg.configFile."niri/keybindings.txt".source = keybindingGuide;

  # DMS (dankMaterialShell) KDL config placeholders
  # Niri's config includes these files via KDL `include` directives.
  # On first boot, DMS hasn't run yet so these files don't exist.
  # We create writable placeholders so niri can start without errors.
  # DMS overwrites them with actual configuration at runtime.
  #
  # Uses activation script (not xdg.configFile) so files are real and writable.
  # AUTHORITATIVE LIST: Update this when DMS adds new KDL config files.
  # Reference: github.com/nickheal/dank-material-shell (DMS niri integration)
  home.activation.dmsPlaceholders = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dms_dir="${config.xdg.configHome}/niri/dms"
    mkdir -p "$dms_dir"
    for f in alttab binds colors cursor layout outputs windowrules wpblur; do
      if [ ! -e "$dms_dir/$f.kdl" ]; then
        echo '// Placeholder — DMS will overwrite this file with actual configuration' > "$dms_dir/$f.kdl"
      fi
    done
  '';
}
