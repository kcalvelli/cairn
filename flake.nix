{
  description = "Cairn - A modular NixOS distribution";

  inputs = {

    #nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
    };

    flake-parts = {
      inputs.nixpkgs-lib.follows = "nixpkgs";
      url = "github:hercules-ci/flake-parts";
    };

    systems = {
      url = "github:nix-systems/x86_64-linux";
    };

    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager";
    };

    agenix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:ryantm/agenix";
    };

    devshell = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:numtide/devshell";
    };

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        rust-overlay.follows = "rust-overlay";
      };
    };

    # For dev shells
    "zig-overlay" = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niri with DMS Shell
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dankMaterialShell = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Greeter split out of DankMaterialShell into its own repo
    dank-greeter = {
      url = "github:AvengeMedia/dank-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dms-plugin-registry = {
      url = "github:AvengeMedia/dms-plugin-registry";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cairn-monitor = {
      url = "github:kcalvelli/cairn-monitor";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dsearch = {
      url = "github:AvengeMedia/danksearch";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      # Eliminate 15GB+ of duplicate packages by using unstable for stable channel too
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };

    c64term = {
      url = "github:kcalvelli/c64term";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Brave browser previews (nightly/beta)
    brave-browser-previews = {
      url = "github:kcalvelli/brave-browser-previews";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Code formatting
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Rust overlay
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Up to date google's agentic IDE
    antigravity-nix = {
      url = "github:jacopone/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # AI-powered email management
    cairn-mail = {
      url = "github:kcalvelli/cairn-mail";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # CalDAV/CardDAV sync with MCP server for calendar/contacts access
    cairn-dav = {
      url = "github:kcalvelli/cairn-dav";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MCP Gateway - Universal MCP server aggregator
    mcp-gateway = {
      url = "github:kcalvelli/mcp-gateway";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cairn-companion — persistent persona wrapper around Claude Code
    cairn-companion = {
      url = "github:kcalvelli/cairn-companion";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Binary caches (niri) are configured declaratively in
  # modules/system/nix.nix after the first rebuild. We intentionally omit
  # nixConfig here because it only works for trusted users, and on a fresh
  # NixOS install the user is not trusted — causing noisy warnings.

  outputs =
    inputs@{
      flake-parts,
      systems,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { self, ... }:
      {
        systems = import systems;

        perSystem =
          { pkgs, ... }:
          {
            # Formatter for `nix fmt`
            formatter = (
              inputs.treefmt-nix.lib.mkWrapper pkgs {
                projectRootFile = "flake.nix";
                programs.nixfmt.enable = true;
              }
            );

            # Apps - exposed as `nix run github:kcalvelli/cairn#<app>`
            apps = {
              init = {
                type = "app";
                program = toString (
                  pkgs.writeShellScript "cairn-init" ''
                    export PATH="${
                      pkgs.lib.makeBinPath [
                        pkgs.bash
                        pkgs.gum
                        pkgs.git
                        pkgs.coreutils
                        pkgs.gnugrep
                        pkgs.gnused
                        pkgs.pciutils
                        pkgs.util-linux
                        pkgs.gawk
                        pkgs.claude-code
                        pkgs.gh
                      ]
                    }:$PATH"
                    export CAIRN_TEMPLATE_DIR="${./scripts/templates}"
                    exec bash ${./scripts/init-config.sh} "$@"
                  ''
                );
                meta.description = "Initialize or extend an Cairn configuration";
              };

              download-llama-models = {
                type = "app";
                program = toString (
                  pkgs.writeShellScript "download-llama-models" ''
                    exec ${pkgs.bash}/bin/bash ${./scripts/download-llama-models.sh} "$@"
                  ''
                );
                meta.description = "Download GGUF models for llama-cpp server";
              };

              add-pwa = {
                type = "app";
                program = toString (
                  pkgs.writeShellScript "cairn-add-pwa" ''
                    export PATH="${
                      pkgs.lib.makeBinPath [
                        pkgs.bash
                        pkgs.curl
                        pkgs.jq
                        pkgs.imagemagick
                        pkgs.coreutils
                        pkgs.gnugrep
                        pkgs.gnused
                        pkgs.file
                      ]
                    }:$PATH"
                    export FETCH_SCRIPT="${./scripts/fetch-pwa-icon.sh}"
                    exec ${pkgs.bash}/bin/bash ${./scripts/add-pwa.sh} "$@"
                  ''
                );
                meta.description = "Interactive helper to add custom PWAs to your configuration";
              };

              fetch-pwa-icon = {
                type = "app";
                program = toString (
                  pkgs.writeShellScript "cairn-fetch-pwa-icon" ''
                    export PATH="${
                      pkgs.lib.makeBinPath [
                        pkgs.bash
                        pkgs.curl
                        pkgs.jq
                        pkgs.imagemagick
                        pkgs.coreutils
                        pkgs.gnugrep
                        pkgs.gnused
                        pkgs.file
                      ]
                    }:$PATH"
                    exec ${pkgs.bash}/bin/bash ${./scripts/fetch-pwa-icon.sh} "$@"
                  ''
                );
                meta.description = "Fetch PWA icon from a website";
              };
            };
          };

        imports = [
          #inputs.treefmt-nix.flakeModule
          ./pkgs
          ./modules
          ./home
          ./devshells.nix
        ];

        # Export library functions for downstream flakes
        flake.lib = import ./lib {
          inherit inputs;
          inherit self;
          lib = nixpkgs.lib;
        };

        # Cairn installer ISO — boots into a live Niri + DMS session
        flake.nixosConfigurations.iso = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-graphical-base.nix"
            inputs.dankMaterialShell.nixosModules.dank-material-shell
            inputs.dank-greeter.nixosModules.default
            inputs.home-manager.nixosModules.home-manager
            self.nixosModules.installer
            {
              nixpkgs.overlays = [ self.overlays.default ];
              cairn.installer.enable = true;
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
            }
          ];
        };
      }
    );
}
