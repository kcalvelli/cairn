{
  config,
  lib,
  pkgs,
  self,
  inputs,
  ...
}:
{
  options.cairn.system = {
    enable = lib.mkEnableOption "core Cairn system configuration" // {
      default = true;
    };
  };

  # Import necessary modules (must be at top level to register options)
  imports = [
    ./branding.nix
    ./locale.nix
    ./nix.nix
    ./boot.nix
    ./memory.nix
    ./printing.nix
    ./sound.nix
    ./bluetooth.nix
  ];

  config = lib.mkIf config.cairn.system.enable {
    # Apply overlays to system pkgs (makes packages available to home-manager via useGlobalPkgs)
    nixpkgs.overlays = [
      self.overlays.default
      # mcp-servers-nix overlay provides pre-built MCP servers (mcp-server-git, etc.)
      inputs.mcp-servers-nix.overlays.default
      # mcp-gateway overlay provides the gateway package
      inputs.mcp-gateway.overlays.default
    ];

    # Configure home-manager to use system pkgs (with overlays)
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;

    # NOTE: External home-manager modules (dankMaterialShell, niri) may set
    # nixpkgs.config or nixpkgs.overlays, which triggers a deprecation warning when
    # useGlobalPkgs = true. This is a known issue and will be fixed in future versions
    # of those modules. The warning is harmless and can be safely ignored.

    # === System Packages ===
    environment.systemPackages = with pkgs; [
      # Core system utilities
      killall
      wget
      curl

      # Filesystem and mount tools
      sshfs
      fuse
      ntfs3g

      # System monitoring and information
      pciutils # lspci
      usbutils # lsusb
      wirelesstools
      ethtool
      btop
      htop
      lm_sensors # sensors
      smartmontools # smartctl

      # Diagnostics and crash forensics — the stuff you want already
      # installed when a box falls over, not the stuff you go hunting
      # for after it does.
      lsof
      psmisc # pstree
      sysstat # iostat, mpstat, pidstat, sar
      dmidecode # DIMM/board/BIOS inventory
      dnsutils # dig, host, nslookup
      ncdu
      inxi
      hwinfo
      drm_info
      mcelog # decode machine-check exceptions (CPU/RAM faults)
      rasdaemon # ras-mc-ctl — ECC/memory error reporting

      # Archive and compression tools
      p7zip
      unzip
      unrar
      xarchiver

      # Security and secret management
      libsecret
      lssecret
      openssl

      # Nix ecosystem tools
      fh # Flake helper CLI
    ];

    # Build smaller systems
    documentation.enable = false;
    documentation.nixos.enable = false;
    documentation.dev.enable = false;
    programs.command-not-found.enable = false;
    programs.vim = {
      enable = true;
      package = (
        pkgs.vim.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            rm -f $out/share/applications/gvim.desktop
          '';
        })
      );
      defaultEditor = true;
    };
  };
}
