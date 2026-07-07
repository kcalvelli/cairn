{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    inputs.niri.homeModules.niri
    inputs.dankMaterialShell.homeModules.niri
  ];

  programs = {
    niri.package = lib.mkForce pkgs.niri;
    dank-material-shell = {
      niri = {
        enableKeybinds = true; # Injects DMS keybinds (media keys, launcher, etc.) via niri module
        enableSpawn = true; # DMS spawns when Niri starts (eliminates race conditions)
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
    };
    niri.settings = {
      prefer-no-csd = true;
      #xwayland-satellite.path = "${lib.getExe pkgs.xwayland-satellite}";
      screenshot-path = "~/Pictures/Screenshots/Screenshot-from-%Y-%m-%d-%H-%M-%S.png";
      hotkey-overlay.skip-at-startup = true;

      spawn-at-startup = [
        # Ensure session variables are imported into the systemd/DBus environment
        # This is critical for XDG_MENU_PREFIX and other session-wide variables
        {
          command = [
            "${pkgs.dbus}/bin/dbus-update-activation-environment"
            "--systemd"
            "--all"
          ];
        }

        # Clipboard management: Handled by DMS natively (enableSpawn=true)
        # Overview blur: DMS renders its own `dms:blurwallpaper` backdrop
        # natively (seeded via cairn.wallpapers.overviewBlur). No swaybg.
        #{command = ["qs" "-c" "DankMaterialShell"];}
        # Note: Ghostty is started via systemd user service (app-com.mitchellh.ghostty.service)
        # configured in home/terminal/ghostty.nix with singleton mode for drop-down terminal support
        # Show keybinding guide on first login (helpful for new users)
        {
          command = [ "cairn-help" ];
        }
      ];

      layout = {
        # Kill borders around all windows
        border = {
          enable = false;
        };
        focus-ring = {
          enable = true;
        };
        background-color = "transparent";
        preset-column-widths = [
          # proportions are fractions of the output width (gaps considered)
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

      overview = {
        #zoom = 0.25;
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
      # already pulled in via includes.filesToInclude. No hand-written
      # layer-rule needed.

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
            { app-id = ".*"; } # regex: all apps
          ];
          open-maximized = true;
        }

        # Specific: Google Messages PWA — float, upper right, iMessage-ish size
        {
          matches = [
            { app-id = "^chrome-messages\\.google\\.com__web-Default$"; }
          ];

          # Explicitly override the global rule:
          open-maximized = false;
          open-floating = true;

          # Size on open (pixels)
          default-column-width = {
            fixed = 500;
          };
          default-window-height = {
            fixed = 700;
          };

          # Optional: pin position instead of center (comment out if not needed)
          default-floating-position = {
            x = 5;
            y = 5;
            relative-to = "top-left";
          };
        }
        # Dolphin file manager — float, centered, comfortable size for file tasks
        {
          matches = [
            # Match Dolphin app-id (dots are literal, not regex metacharacters in Niri)
            { app-id = "^org.kde.dolphin$"; }
          ];

          # Override the global maximized rule
          open-maximized = false;
          open-floating = true; # centers by default

          # A comfortable size for quick file tasks
          default-column-width = {
            fixed = 1200;
          };
          default-window-height = {
            fixed = 900;
          };

          # Optional: pin a corner instead of center
          # default-floating-position = { x = 0; y = 0; relative-to = "top-right"; };
        }
        # Qalculate — float, centered, small calculator size
        {
          matches = [
            # Match Qalculate app-id (dots are literal, not regex metacharacters in Niri)
            { app-id = "^io.github.Qalculate.qalculate-qt$"; }
          ];

          # Explicitly override the global rule:
          open-maximized = false;
          open-floating = true;

          # Size on open (pixels)
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
          # Explicitly override the global rule:
          open-maximized = false;
          open-floating = true;
        }
        # DMS settings
        {
          matches = [
            {
              # DMS 0.0.x renamed its Quickshell window from org.quickshell
              # to com.danklinux.dms. Dots are literal here, escaped per the
              # convention used by the Nautilus/Dolphin rules below.
              app-id = "^com\\.danklinux\\.dms$";
              title = "^Settings$";
            }
          ];

          # Explicitly override the global rule:
          open-maximized = false;
          open-floating = true;

        }
        {
          matches = [
            # Match Nautilus app-id (dots are literal, not regex metacharacters in Niri)
            { app-id = "^org\\.gnome\\.Nautilus$"; }
          ];

          # Override the global maximized rule
          open-maximized = false;
          open-floating = true; # centers by default

          # A comfortable size for quick file tasks
          default-column-width = {
            fixed = 1200;
          };
          default-window-height = {
            fixed = 900;
          };

          # Optional: pin a corner instead of center
          # default-floating-position = { x = 0; y = 0; relative-to = "top-right"; };
        }
        # Drop-down Ghostty: float, matches panel width, short height, stick to the top center
        {
          matches = [ { app-id = "^com\\.github\\.kcalvelli\\.cairn\\.dropterm$"; } ];

          open-floating = true;

          # Size/position: panel width (full width minus side margins), 420px tall, tucked under bar
          default-column-width = {
            proportion = 0.97;
          };
          default-window-height = {
            fixed = 420;
          };
          default-floating-position = {
            x = 0;
            y = 4;
            relative-to = "top";
          };

          # --- Remove border/outline/shadow (per-window) ---
          border = {
            enable = false;
          };
          focus-ring = {
            enable = false;
          };
          shadow = {
            enable = false;
          };
        }

        # Normal Ghostty windows: leave as you like (example: keep maximized-by-default off)
        {
          matches = [ { app-id = "^com\\.mitchellh\\.ghostty$"; } ];
          # no open-floating here, so they tile/maximize per your global rules
        }

        # C64 Terminal: float, centered, classic 4:3 aspect
        {
          matches = [
            { app-id = "^io\\.github\\.kcalvelli\\.c64term$"; }
          ];

          # Override global maximized rule
          open-maximized = false;
          open-floating = true; # Centers by default

          # Classic 4:3 aspect ratio sized for comfortable C64 viewing
          #default-column-width = {
          #  fixed = 1024;
          #};
          #default-window-height = {
          #  fixed = 768;
          #};
        }

        # C64 Stream Viewer: float, centered, classic 4:3 aspect
        {
          matches = [
            { title = "^C64 Stream Viewer$"; } # Match by title (SDL apps often don't set app-id)
          ];

          # Override global maximized rule
          open-maximized = false;
          open-floating = true; # Centers by default

          # Classic 4:3 aspect ratio for C64 content
          default-column-width = {
            fixed = 1024;
          };
          default-window-height = {
            fixed = 768;
          };
        }

        # Flatpak installer: small floating window for transparent installation
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

        # OpenSSH passphrase prompt: float, centered, compact dialog size
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

        # Gajim XMPP client: float, right side, IM-style tall narrow window
        {
          matches = [
            { app-id = "^org\\.gajim\\.Gajim$"; }
          ];

          # Override global maximized rule
          open-maximized = false;
          open-floating = true;

          # IM-style: tall and narrow
          default-column-width = {
            fixed = 1024;
          };
          default-window-height = {
            fixed = 768;
          };

          # Pin to right side of screen
          default-floating-position = {
            x = 10;
            y = 50;
            relative-to = "top-right";
          };
        }
      ];

    };
  };
}
