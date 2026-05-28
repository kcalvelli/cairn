{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.desktop;
  browsers = cfg.browsers;

  # Get GPU type from hardware configuration
  gpuType = config.cairn.hardware.gpuType or null;
  isAmd = gpuType == "amd";
  isNvidia = gpuType == "nvidia";

  braveExtensionIds = [
    "ghbmnnjooekpmoecnnnilnnbdlolhkhi" # Google Docs Offline
    "nimfmkdcckklbkhjjkmbjfcpaiifgamg" # Brave Talk
    "aomjjfmjlecjafonmbhlgochhaoplhmo" # 1Password
    "fcoeoabgfenejglbffodgkkbkcdhcgfn" # Claude
  ];

  # Base arguments for all configurations
  baseArgs = [
    "--password-store=detect"
  ];

  # Common hardware acceleration flags for both AMD and NVIDIA
  commonAccelFlags = [
    "--ignore-gpu-blocklist"
    "--enable-gpu-rasterization"
    "--enable-zero-copy"
    "--enable-native-gpu-memory-buffers"
  ];

  # AMD-specific hardware acceleration flags
  # Note: Chrome 131+ renamed Vaapi* to Accelerated* but kept VaapiIgnoreDriverChecks
  amdAccelFlags = [
    "--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks,CanvasOopRasterization"
    # "--enable-unsafe-webgpu" # Commented out - produces warnings in Brave
  ];

  # NVIDIA-specific hardware acceleration flags
  # VaapiOnNvidiaGPUs enables VA-API on NVIDIA via nvidia-vaapi-driver
  nvidiaAccelFlags = [
    "--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecodeLinuxGL,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks,CanvasOopRasterization"
  ];

  # Build final argument list based on GPU type
  braveArgs =
    baseArgs
    ++ lib.optionals isAmd (commonAccelFlags ++ amdAccelFlags)
    ++ lib.optionals isNvidia (commonAccelFlags ++ nvidiaAccelFlags);

  chromeArgs =
    baseArgs
    ++ lib.optionals isAmd (commonAccelFlags ++ amdAccelFlags)
    ++ lib.optionals isNvidia (commonAccelFlags ++ nvidiaAccelFlags);
in
{
  # Import NixOS module from flake
  imports = [ inputs.brave-browser-previews.nixosModules.default ];

  options.desktop = {
    browserArgs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      readOnly = true;
      description = "Computed browser command-line arguments (GPU-aware). Read-only, consumed by PWA launcher generation.";
    };

    browsers = {
      brave = {
        enable = lib.mkEnableOption "Brave stable browser" // {
          default = true;
        };
      };
      braveNightly = {
        enable = lib.mkEnableOption "Brave Nightly browser";
      };
      braveBeta = {
        enable = lib.mkEnableOption "Brave Beta browser";
      };
      braveOriginNightly = {
        enable = lib.mkEnableOption "Brave Origin Nightly browser";
      };
      braveOriginBeta = {
        enable = lib.mkEnableOption "Brave Origin Beta browser";
      };
      chrome = {
        enable = lib.mkEnableOption "Google Chrome browser";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Always expose computed args for PWA module regardless of which browsers are enabled
      {
        desktop.browserArgs = {
          brave = braveArgs;
          chromium = chromeArgs;
          google-chrome = chromeArgs;
        };
      }

      # Brave Stable (home-manager)
      (lib.mkIf browsers.brave.enable {
        home-manager.sharedModules = [
          (
            { pkgs, ... }:
            {
              programs.brave = {
                enable = true;
                extensions = map (id: { inherit id; }) braveExtensionIds;
                commandLineArgs = braveArgs;
              };
            }
          )
        ];
      })

      # Brave Nightly (system module from brave-browser-previews flake)
      (lib.mkIf browsers.braveNightly.enable {
        programs.brave-nightly = {
          enable = true;
          extensions = braveExtensionIds;
          commandLineArgs = braveArgs;
        };
      })

      # Brave Beta (system module from brave-browser-previews flake)
      (lib.mkIf browsers.braveBeta.enable {
        programs.brave-beta = {
          enable = true;
          extensions = braveExtensionIds;
          commandLineArgs = braveArgs;
        };
      })

      # Brave Origin Nightly (system module from brave-browser-previews flake)
      (lib.mkIf browsers.braveOriginNightly.enable {
        programs.brave-origin-nightly = {
          enable = true;
          extensions = braveExtensionIds;
          commandLineArgs = braveArgs;
        };
      })

      # Brave Origin Beta (system module from brave-browser-previews flake)
      (lib.mkIf browsers.braveOriginBeta.enable {
        programs.brave-origin-beta = {
          enable = true;
          extensions = braveExtensionIds;
          commandLineArgs = braveArgs;
        };
      })

      # Google Chrome (home-manager)
      (lib.mkIf browsers.chrome.enable {
        home-manager.sharedModules = [
          (
            { pkgs, ... }:
            {
              programs.google-chrome = {
                enable = true;
                commandLineArgs = chromeArgs;
              };
            }
          )
        ];
      })

      # Chromium args (always set for PWA backend — no standalone install)
      {
        home-manager.sharedModules = [
          (
            { pkgs, ... }:
            {
              programs.chromium = {
                commandLineArgs = chromeArgs;
              };
            }
          )
        ];
      }
    ]
  );
}
