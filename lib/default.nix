# Cairn Library Functions
# These functions can be used by downstream flakes to build NixOS configurations
{
  inputs,
  self,
  lib,
}:
let
  # Helper to build nixos-hardware modules based on hardware configuration
  hardwareModules =
    hw:
    let
      hwMods = inputs.nixos-hardware.nixosModules;
    in
    lib.optional (hw.cpu or null == "amd") hwMods.common-cpu-amd
    ++ lib.optional (hw.cpu or null == "intel") hwMods.common-cpu-intel
    ++ lib.optional (hw.gpu or null == "amd") hwMods.common-gpu-amd
    ++ lib.optional (hw.gpu or null == "nvidia") hwMods.common-gpu-nvidia
    ++ lib.optional (hw.hasSSD or false) hwMods.common-pc-ssd
    ++ lib.optional (hw.isLaptop or false) hwMods.common-pc-laptop;

  # Helper to build module list for a host configuration
  buildModules =
    hostCfg:
    let
      # Validation module - checks configuration consistency
      validationModule = {
        config.assertions =
          let
            hw = hostCfg.hardware or { };
            cpu = hw.cpu or null;
            gpu = hw.gpu or null;
            vendor = hw.vendor or null;
            isLaptop = hw.isLaptop or false;
            formFactor = hostCfg.formFactor or null;
            modules = hostCfg.modules or { };
            homeProfile = hostCfg.homeProfile or null;
          in
          [
            # Required fields
            {
              assertion = hostCfg ? hostname;
              message = ''
                Cairn configuration error: 'hostname' is required but not specified.

                Add to your configuration:
                  hostname = "myhostname";
              '';
            }

            # Valid CPU type
            {
              assertion =
                cpu == null
                || lib.elem cpu [
                  "amd"
                  "intel"
                ];
              message = ''
                Cairn configuration error: Invalid hardware.cpu value: "${lib.generators.toPretty { } cpu}"

                Valid options: "amd", "intel", or null
                Note: Values are case-sensitive (use lowercase).
              '';
            }

            # Valid GPU type
            {
              assertion =
                gpu == null
                || lib.elem gpu [
                  "amd"
                  "nvidia"
                  "intel"
                ];
              message = ''
                Cairn configuration error: Invalid hardware.gpu value: "${lib.generators.toPretty { } gpu}"

                Valid options: "amd", "nvidia", "intel", or null
              '';
            }

            # Valid form factor
            {
              assertion =
                formFactor == null
                || lib.elem formFactor [
                  "desktop"
                  "laptop"
                ];
              message = ''
                Cairn configuration error: Invalid formFactor value: "${lib.generators.toPretty { } formFactor}"

                Valid options: "desktop", "laptop"
              '';
            }

            # Valid home profile
            {
              assertion =
                homeProfile == null
                || lib.elem homeProfile [
                  "standard"
                  "normie"
                ];
              message = ''
                Cairn configuration error: Invalid homeProfile value: "${lib.generators.toPretty { } homeProfile}"

                Valid options: "standard", "normie"
              '';
            }

            # Consistency: isLaptop vs formFactor
            {
              assertion = !isLaptop || formFactor == "laptop";
              message = ''
                Cairn configuration error: Inconsistent laptop configuration.

                You have:
                  hardware.isLaptop = true
                  formFactor = "${formFactor}"

                These must match. Fix by setting:
                  formFactor = "laptop";
                  hardware.isLaptop = true;
              '';
            }

            # Consistency: desktop formFactor shouldn't have isLaptop
            {
              assertion = formFactor != "desktop" || !isLaptop;
              message = ''
                Cairn configuration error: Inconsistent desktop configuration.

                You have:
                  formFactor = "desktop"
                  hardware.isLaptop = true

                Desktop systems should not have isLaptop = true. Fix by setting:
                  hardware.isLaptop = false;
              '';
            }

            # Vendor constraint: Cairn only supports System76 laptops
            {
              assertion = vendor != "system76" || formFactor == "laptop";
              message = ''
                Cairn configuration error: System76 vendor requires laptop form factor.

                You have:
                  hardware.vendor = "system76"
                  formFactor = "${formFactor}"

                Cairn currently only supports System76 laptop configurations.
                While System76 does make desktops (Thelio), Cairn doesn't have
                hardware modules for them yet.

                Fix by setting:
                  formFactor = "laptop";

                Or use vendor = null for generic desktop configuration.
              '';
            }

            # Vendor constraint: MSI in this context means desktop
            {
              assertion = vendor != "msi" || formFactor == "desktop";
              message = ''
                Cairn configuration error: MSI vendor requires desktop form factor.

                You have:
                  hardware.vendor = "msi"
                  formFactor = "${formFactor}"

                The MSI vendor option is for desktop motherboards. Fix by setting:
                  formFactor = "desktop";

                Note: If you have an MSI laptop, use vendor = null instead.
              '';
            }

            # Module dependency: AI module should have networking enabled
            {
              assertion = !(modules.ai or false) || (modules.networking or true);
              message = ''
                Cairn configuration error: AI module requires networking module.

                You have:
                  modules.ai = true
                  modules.networking = false

                AI services require networking. Fix by setting:
                  modules.networking = true;
              '';
            }

            # Helpful warning: AI without services module limits functionality
            # This is a warning, not an error, so we make the assertion always pass
            # and put the warning in the modules that need it

            # Consistency: gaming usually wants graphics
            {
              assertion = !(modules.gaming or false) || (modules.graphics or false);
              message = ''
                Cairn configuration error: Gaming module requires graphics module.

                You have:
                  modules.gaming = true
                  modules.graphics = false

                Gaming support requires graphics drivers. Fix by setting:
                  modules.graphics = true;
              '';
            }

            # Consistency: desktop module wants networking for services
            {
              assertion = !(modules.desktop or false) || (modules.networking or true);
              message = ''
                Cairn configuration error: Desktop module requires networking module.

                You have:
                  modules.desktop = true
                  modules.networking = false

                Desktop environment needs networking for various services. Fix by setting:
                  modules.networking = true;
              '';
            }

            # configDir is required when users list is non-empty
            {
              assertion =
                let
                  users = hostCfg.users or [ ];
                  configDir = hostCfg.configDir or null;
                in
                users == [ ] || configDir != null;
              message = ''
                Cairn configuration error: 'configDir' is required when 'users' list is non-empty.

                You have users defined but no configDir. Add to your host config:
                  configDir = self.outPath;

                This tells Cairn where to find users/<name>.nix files.
              '';
            }
          ];
      };

      baseModules = [
        validationModule # Validate configuration first
        inputs.dankMaterialShell.nixosModules.dank-material-shell
        inputs.dankMaterialShell.nixosModules.greeter
        inputs.home-manager.nixosModules.home-manager
        inputs.lanzaboote.nixosModules.lanzaboote
        # Standalone project modules (like cairn-mail pattern)
        inputs.mcp-gateway.nixosModules.default
      ];

      hwModules = hardwareModules hostCfg.hardware;

      # Core modules that are ALWAYS imported (provide options but may not be enabled)
      # Add new modules here if they should be available for configuration without a modules.X flag
      coreModules = with self.nixosModules; [
        crashDiagnostics # Always available for extraConfig.hardware.crashDiagnostics
        hardware # Parent hardware module
        services # Always available for cairn.immich (Tailscale Services integration)
      ];

      # Modules controlled by modules.X flags
      flaggedModules =
        with self.nixosModules;
        lib.optional (hostCfg.modules.system or true) system
        ++ lib.optional (hostCfg.modules.desktop or false) desktop
        ++ lib.optional (hostCfg.modules.development or false) development
        ++ lib.optional (hostCfg.modules.graphics or false) graphics
        ++ lib.optional (hostCfg.modules.networking or true) networking
        ++ lib.optional (hostCfg.modules.pim or false) pim
        ++ lib.optional (hostCfg.modules.users or true) users
        ++ lib.optional (hostCfg.modules.virt or false) virt
        ++ lib.optional (hostCfg.modules.gaming or false) gaming
        ++ lib.optional (hostCfg.modules.ai or true) ai
        ++ lib.optional (hostCfg.modules.secrets or false) secrets
        ++ lib.optional (hostCfg.modules.companion or false) companion
        ++ lib.optional (hostCfg.modules.syncthing or false) syncthing;

      # Hardware modules conditionally imported based on vendor/formFactor
      conditionalHwModules =
        with self.nixosModules;
        lib.optional (hostCfg.hardware.vendor or null == "msi") desktopHardware
        ++ lib.optional (hostCfg.hardware.vendor or null == "system76") laptopHardware
        # Generic hardware based on form factor (if no specific vendor)
        ++ lib.optional (
          (hostCfg.hardware.vendor or null == null) && (hostCfg.formFactor or "" == "desktop")
        ) desktopHardware
        ++ lib.optional (
          (hostCfg.hardware.vendor or null == null) && (hostCfg.formFactor or "" == "laptop")
        ) laptopHardware;

      ourModules = coreModules ++ flaggedModules ++ conditionalHwModules;

      hostModule =
        { lib, config, ... }:
        let
          hwVendor = hostCfg.hardware.vendor or null;
          hwCpu = hostCfg.hardware.cpu or null;
          hwGpu = hostCfg.hardware.gpu or null;
          profile = hostCfg.homeProfile or "standard";
          extraCfg = hostCfg.extraConfig or { };

          # Determine if hardware modules should be auto-enabled (matches conditionalHwModules logic)
          enableDesktopHardware =
            (hwVendor == "msi") || ((hwVendor == null) && (hostCfg.formFactor or "" == "desktop"));
          enableLaptopHardware =
            (hwVendor == "system76") || ((hwVendor == null) && (hostCfg.formFactor or "" == "laptop"));

          # Check if extraConfig should be treated as a separate module
          # (when it's a function or contains imports/options)
          extraCfgIsModule =
            (lib.isFunction extraCfg) || (lib.isAttrs extraCfg && (extraCfg ? imports || extraCfg ? options));

          # Build dynamic config based on what's defined in hostCfg
          dynamicConfig = lib.mkMerge [
            # Only merge extraConfig if it's not a module
            # (modules will be added separately to preserve imports/options)
            (if extraCfgIsModule then { } else extraCfg)
            # Pass CPU type to hardware modules (if CPU type is specified)
            (lib.optionalAttrs (hwCpu != null) {
              cairn.hardware.cpuType = hwCpu;
            })
            # Pass GPU type and form factor to graphics module (if graphics module is enabled)
            (lib.optionalAttrs ((hostCfg.modules.graphics or false) && (hwGpu != null)) {
              cairn.hardware.gpuType = hwGpu;
              cairn.hardware.isLaptop = hostCfg.hardware.isLaptop or false;
            })
            # Auto-enable desktop hardware module when conditionally imported
            (lib.optionalAttrs enableDesktopHardware {
              hardware.desktop.enable = true;
            })
            # Auto-enable laptop hardware module when conditionally imported
            (lib.optionalAttrs enableLaptopHardware {
              hardware.laptop.enable = true;
            })
            # Add virt config only if module is enabled and config exists
            (lib.optionalAttrs ((hostCfg.modules.virt or false) && (hostCfg ? virt)) {
              virt = hostCfg.virt;
            })
            # Enable AI module if specified (now defaults to true)
            (lib.optionalAttrs (hostCfg.modules.ai or true) {
              services.ai.enable = true;
            })
            # Enable desktop module if specified
            (lib.optionalAttrs (hostCfg.modules.desktop or false) {
              desktop.enable = true;
            })
            # Enable development module if specified
            (lib.optionalAttrs (hostCfg.modules.development or false) {
              development.enable = true;
            })
            # Enable PIM module if specified
            (lib.optionalAttrs (hostCfg.modules.pim or false) {
              services.pim.enable = true;
            })
            # Enable gaming module if specified
            (lib.optionalAttrs (hostCfg.modules.gaming or false) {
              gaming.enable = true;
            })
            # Enable secrets module if specified
            (lib.optionalAttrs (hostCfg.modules.secrets or false) {
              secrets.enable = true;
            })
            # Add secrets config only if module is enabled and config exists
            (lib.optionalAttrs ((hostCfg.modules.secrets or false) && (hostCfg ? secrets)) {
              secrets = hostCfg.secrets;
            })
            # Enable companion module if specified
            (lib.optionalAttrs (hostCfg.modules.companion or false) {
              services.companion.enable = true;
            })
            # Enable Syncthing module if specified
            (lib.optionalAttrs (hostCfg.modules.syncthing or false) {
              cairn.syncthing.enable = true;
            })
            # Add cairn config (immich, etc.) if module is enabled and config exists
            (lib.optionalAttrs ((hostCfg.modules.services or false) && (hostCfg ? cairn)) {
              cairn = hostCfg.cairn;
            })
          ];
        in
        lib.mkMerge [
          {
            networking.hostName = hostCfg.hostname;

            # Home-Manager integration
            home-manager = {
              # Use system nixpkgs instead of separate channel
              useGlobalPkgs = true;
              # Install packages to /etc/profiles instead of ~/.nix-profile
              useUserPackages = true;
              # Backup files that would be overwritten
              backupFileExtension = "hm-backup";

              # Universal shared modules (apply to ALL users regardless of profile)
              # Note: AI module is profile-conditional (standard only), not universal
              sharedModules =
                lib.optional (hostCfg.modules.secrets or false) self.homeModules.secrets
                ++ lib.optional (hostCfg.modules.pim or false) self.homeModules.pim
                ++ lib.optional (hostCfg.modules.services or false) self.homeModules.immich
                ++ lib.optional (hostCfg.modules.desktop or false) self.homeModules.firstBoot;
            };
          }
          dynamicConfig

          # Per-user home profile wiring
          # Each user gets profile modules based on their homeProfile (or host default)
          {
            home-manager.users = lib.mapAttrs (
              name: userDef:
              let
                resolvedProfile = if userDef.homeProfile != null then userDef.homeProfile else profile;
                profileModules =
                  if resolvedProfile == "standard" then
                    [ self.homeModules.standard ]
                  else if resolvedProfile == "normie" then
                    [ self.homeModules.normie ]
                  else
                    [ ];
                # AI home modules only for standard profile users
                aiModules =
                  if resolvedProfile == "standard" then
                    lib.optional (hostCfg.modules.ai or true) self.homeModules.ai
                  else
                    [ ];
                companionModules =
                  if resolvedProfile == "standard" then
                    lib.optional (hostCfg.modules.companion or false) self.homeModules.companion
                  else
                    [ ];
              in
              {
                imports = profileModules ++ aiModules ++ companionModules;
              }
            ) config.cairn.users.users;
          }
        ];

      # Hardware configuration module
      hardwareModule =
        if hostCfg ? hardwareConfigPath then
          hostCfg.hardwareConfigPath
        else
          {
            # Default: No hardware configuration
            imports = [ ];
          };

      # Resolve user modules from configDir + users list
      configDir = hostCfg.configDir or null;
      userNames = hostCfg.users or [ ];
      userModules =
        if configDir != null then map (name: configDir + "/users/${name}.nix") userNames else [ ];

      # Extract extraCfg and check if it's a module
      extraCfg = hostCfg.extraConfig or { };
      extraCfgIsModule =
        (lib.isFunction extraCfg) || (lib.isAttrs extraCfg && (extraCfg ? imports || extraCfg ? options));
    in
    baseModules
    ++ hwModules
    ++ ourModules
    ++ [
      hostModule
      hardwareModule
    ]
    ++ userModules
    # Add extraConfig as a module if it contains imports/options or is a function
    ++ lib.optional extraCfgIsModule extraCfg;

  # Main function to create a NixOS system configuration
  # Usage: mkSystem { hostConfig attrs }
  mkSystem =
    hostCfg:
    let
      # Merge framework inputs with user provided inputs.
      # User inputs take precedence (allowing overrides), but missing keys fall back to framework.
      finalInputs = inputs // (hostCfg.inputs or { });
    in
    inputs.nixpkgs.lib.nixosSystem {
      system = hostCfg.system or "x86_64-linux";
      specialArgs = {
        inputs = finalInputs; # Now contains BOTH sets
        inherit self;
        inherit (self) nixosModules homeModules;
      };
      modules = buildModules hostCfg;
    };
in
{
  inherit hardwareModules buildModules mkSystem;
}
