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
      # Upstream OpenSpec (Fission-AI/OpenSpec) hardcodes nodejs_20 in its
      # flake's nativeBuildInputs. nixpkgs flipped nodejs_20 to insecure once
      # it hit upstream EOL, breaking evaluation. Swap it for nodejs_22 here
      # until upstream bumps. Match by pname+major-version so we don't have to
      # name nodejs_20 directly (which would itself trip the insecure check).
      openspec =
        let
          base = inputs.openspec.packages.${prev.stdenv.hostPlatform.system}.default;
        in
        base.overrideAttrs (old: {
          nativeBuildInputs = map (
            p:
            if (p.pname or null) == "nodejs" && lib.hasPrefix "20." (p.version or "") then prev.nodejs_22 else p
          ) old.nativeBuildInputs;
        });

      # deno 2.7.13: tty_reset_mode_restores_termios test fails in nix sandbox
      # (no TTY available — assertion returns -16 instead of 0)
      deno = prev.deno.overrideAttrs { doCheck = false; };

      # claude-code: pin newer than nixpkgs (2.1.158 -> 2.1.170) so Fable 5 is
      # available. nixpkgs builds claude-code from a prebuilt binary keyed on a
      # vendored manifest.json; we reuse that derivation and just swap the
      # version + per-platform src checksums (from
      # https://downloads.claude.ai/claude-code-releases/<ver>/manifest.json).
      # Remove this override once nixpkgs ships >= 2.1.170.
      claude-code =
        let
          version = "2.1.170";
          platformKey = "${prev.stdenv.hostPlatform.node.platform}-${prev.stdenv.hostPlatform.node.arch}";
          # sha256 (hex) of the prebuilt `claude` binary per platform.
          checksums = {
            "darwin-arm64" = "e903646d8b7a31882a80ecd27569a27d8ac57b3708745f349709632c84117fdf";
            "darwin-x64" = "914f23a70bbed5d9ae567e3e04b86206ed9971b371bc9baca3f79c8885bfddb4";
            "linux-arm64" = "1bb9d032440a75532f7dd4cafbc687f220aaf16c63eba17e192dfbec2f04bd25";
            "linux-x64" = "849e007277a0442ab27570d3e3d6d43787507946590e8dd1947e5a39b7081f9e";
          };
        in
        prev.claude-code.overrideAttrs (_old: {
          inherit version;
          src = prev.fetchurl {
            url = "https://downloads.claude.ai/claude-code-releases/${version}/${platformKey}/claude";
            sha256 = checksums.${platformKey};
          };
        });

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
