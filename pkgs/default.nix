{ self, inputs, ... }:
let
  # Automatically discover all package directories in pkgs/
  # To add a new package:
  #   1. Create a new directory in pkgs/ (e.g., pkgs/my-package/)
  #   2. Add a default.nix file in that directory
  #   3. The package will be automatically added to flake outputs
  # Each directory with a default.nix will be added as a package
  lib = inputs.nixpkgs.lib;

  # Get all directories in pkgs/ that contain a default.nix
  pkgsDir = ./.;
  packageDirs = builtins.filter (
    name: name != "default.nix" && builtins.pathExists (pkgsDir + "/${name}/default.nix")
  ) (builtins.attrNames (builtins.readDir pkgsDir));

  # Convert directory names with dashes to valid attribute names
  # (they're already valid in Nix, but this makes it explicit)
  packageNames = packageDirs;

  # Extra args for specific packages that need flake-level context
  packageArgs = { };
in
{
  # Note: perSystem receives 'system' parameter from flake-parts
  # The deprecation warning "'system' has been renamed to 'stdenv.hostPlatform.system'"
  # refers to passing system around unnecessarily, but here we need it to import nixpkgs
  # with our overlays. Using pkgs.stdenv.hostPlatform.system would create circular dependency.
  perSystem =
    { system, pkgs, ... }:
    {
      # Automatically export all custom packages
      packages = lib.genAttrs packageNames (name: pkgs.${name});

      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
        overlays = [
          self.overlays.default
          # mcp-servers-nix overlay provides pre-built MCP servers
          # Warning about "github-mcp-server has been removed" is informational:
          # The package was removed from mcp-servers-nix because it's now in nixpkgs 25.11
          inputs.mcp-servers-nix.overlays.default
          # mcp-gateway overlay provides the gateway package
          inputs.mcp-gateway.overlays.default
          # cairn-companion overlay provides the companion wrapper package
          inputs.cairn-companion.overlays.default
        ];
      };
    };

  # Automatically generate overlay from all package directories
  flake.overlays.default =
    _final: prev:
    lib.genAttrs packageNames (
      name: prev.callPackage (pkgsDir + "/${name}") (packageArgs.${name} or { })
    )
    // {
      openspec = inputs.openspec.packages.${prev.stdenv.hostPlatform.system}.default;

      # deno 2.7.13: tty_reset_mode_restores_termios test fails in nix sandbox
      # (no TTY available — assertion returns -16 instead of 0)
      deno = prev.deno.overrideAttrs { doCheck = false; };

      # Broken Python package tests in current nixpkgs:
      # - cli-helpers: Pygments color code changes break style assertions
      # - fastmcp: test suite hangs indefinitely (async/network deadlock in sandbox)
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_pyFinal: pyPrev: {
          cli-helpers = pyPrev.cli-helpers.overrideAttrs { doInstallCheck = false; };
          fastmcp = pyPrev.fastmcp.overrideAttrs { doInstallCheck = false; };
        })
      ];
    };
}
