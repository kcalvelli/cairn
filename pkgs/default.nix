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
      # Upstream OpenSpec (Fission-AI/OpenSpec) hardcodes nodejs_20 and pnpm_9
      # in its flake. nixpkgs flips each to insecure once it hits upstream EOL
      # (nodejs_20) or accumulates CVEs (pnpm-9.15.9), breaking evaluation. Swap
      # them for non-insecure versions here until upstream bumps. Match by
      # pname+major-version so we never name the insecure package directly
      # (which would itself trip the insecure check).
      #
      # pnpm also feeds the pnpmDeps fixed-output derivation, so we rebuild that
      # with the swapped pnpm and pin its hash here. lockfileVersion 9.0 is read
      # by both pnpm 9 and 10, so the swap is safe. NOTE: this hash must be
      # re-pinned whenever OpenSpec bumps its pnpm-lock.yaml.
      openspec =
        let
          base = inputs.openspec.packages.${prev.stdenv.hostPlatform.system}.default;
          pnpm = prev.pnpm_10;
          swap =
            p:
            if (p.pname or null) == "nodejs" && lib.hasPrefix "20." (p.version or "") then
              prev.nodejs_22
            else if (p.pname or null) == "pnpm" && lib.hasPrefix "9." (p.version or "") then
              pnpm
            else
              p;
        in
        base.overrideAttrs (old: {
          nativeBuildInputs = map swap old.nativeBuildInputs;
          pnpmDeps = prev.fetchPnpmDeps {
            inherit (old) pname version src;
            inherit pnpm;
            fetcherVersion = 3;
            hash = "sha256-OUY6G8e6Xqi+0YCcDbpVF06V9pJc68jSSA9rtNg/Vrg=";
          };
        });

      # deno 2.7.13: tty_reset_mode_restores_termios test fails in nix sandbox
      # (no TTY available — assertion returns -16 instead of 0)
      deno = prev.deno.overrideAttrs { doCheck = false; };

      # nixpkgs' brave default.nix builds each flavor as
      #   callPackage ./make-brave.nix { } (release // flavorData)
      # That trailing application eats `.override` off the result, so
      # home-manager's programs.brave (chromium.nix) dies with
      # "attribute 'override' missing" the moment commandLineArgs is set —
      # which cairn always does. make-brave.nix *does* accept commandLineArgs;
      # the packaging just forgot to stay overridable. Rebuild the flavors the
      # way upstream should have — makeOverridable over the callPackage args —
      # so `.override { commandLineArgs = ...; }` works again. Delete this once
      # nixpkgs' default.nix stops applying the release args non-overridably.
      inherit
        (
          let
            braveDir = "${prev.path}/pkgs/applications/networking/browsers/brave";
            mk =
              release: flavorData:
              lib.makeOverridable (
                args: prev.callPackage "${braveDir}/make-brave.nix" args (release // flavorData)
              ) { };
          in
          {
            brave = mk (import "${braveDir}/packages/brave.nix") {
              optStem = "brave";
              fileStem = "brave-browser";
              appIdStem = "com.brave.Browser";
              darwinStem = "Brave Browser";
              changelogFile = "CHANGELOG_DESKTOP.md";
              homepage = "https://brave.com/";
              innerBinary = "brave";
            };
            brave-origin = mk (import "${braveDir}/packages/brave-origin.nix") {
              optStem = "brave-origin";
              fileStem = "brave-origin";
              appIdStem = "com.brave.Origin";
              darwinStem = "Brave Origin";
              changelogFile = "CHANGELOG_DESKTOP_ORIGIN.md";
              homepage = "https://brave.com/origin/";
              innerBinary = "brave";
            };
          }
        )
        brave
        brave-origin
        ;

      # claude-code: pin ahead of nixpkgs so the newest releases (Fable, etc.)
      # are available before they land upstream. nixpkgs builds claude-code from
      # a prebuilt binary keyed on a vendored manifest.json; we reuse that
      # derivation and just swap in our own manifest. The manifest is kept at the
      # latest release by .github/workflows/update-claude-code.yml (which runs
      # ./scripts/update-claude-code.sh). To bump by hand instead, run that
      # script and commit the result.
      claude-code =
        let
          manifest = lib.importJSON ./claude-code-manifest.json;
          platformKey = "${prev.stdenv.hostPlatform.node.platform}-${prev.stdenv.hostPlatform.node.arch}";
        in
        prev.claude-code.overrideAttrs (_old: {
          inherit (manifest) version;
          src = prev.fetchurl {
            url = "https://downloads.claude.ai/claude-code-releases/${manifest.version}/${platformKey}/claude";
            # checksum is the upstream-published sha256 (hex) of the binary.
            sha256 = manifest.platforms.${platformKey}.checksum;
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
