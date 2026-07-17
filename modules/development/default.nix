{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.development = {
    enable = lib.mkEnableOption "Development tools and environments";
  };

  config = lib.mkIf config.development.enable {
    # === System Tuning for Development ===
    # Increase file watchers for IDEs, hot-reload, and file monitoring tools
    # Default Linux limit (8192) is too low for modern development workflows
    boot.kernel.sysctl = {
      "fs.inotify.max_user_watches" = lib.mkDefault 524288; # VS Code, Rider, WebStorm, etc.
      # Note: max_user_instances already set to 524288 by NixOS default (as of recent versions)
    };

    # === Development Packages ===
    environment.systemPackages = with pkgs; [
      # === Editors & IDEs ===
      vscode
      bun # Required for VSCode material theme updates

      # === API Development & Testing ===
      mitmproxy # Interactive HTTPS proxy
      k6 # Load testing tool

      # === Nix Tools ===
      devenv
      nil # Nix LSP

      # === Shell Utilities ===
      bat # Better cat
      jq # JSON processor

      # === Database Clients ===
      pgcli # PostgreSQL CLI with auto-completion and syntax highlighting
      litecli # SQLite CLI (same UX as pgcli)

      # === API Testing ===
      httpie # Modern HTTP client (http/https commands)

      # === Diff & Diagnostics ===
      difftastic # Structural diff tool (AST-aware, language-specific)
      dog # Modern DNS client

      # === Cloudflare cli ===
      wrangler
    ];

    # === Development Services ===
    services = {
      lorri.enable = true;
    };

    # === Development Programs ===
    programs = {
      direnv.enable = true;
      nix-ld.enable = true;
      nix-ld.libraries = with pkgs; [
        # Add any missing dynamic libraries for unpackaged programs
        # here, NOT in environment.systemPackages
      ];
      # Launch Fish when interactive shell is detected
      bash = {
        interactiveShellInit = ''
          if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
          then
            shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
            exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
          fi
        '';
      };
    };
  };
}
