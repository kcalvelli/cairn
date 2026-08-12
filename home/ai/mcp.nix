# MCP Configuration for cairn
# This module imports mcp-gateway's home-manager module and configures
# the MCP servers using cairn's flake inputs.
#
# mcp-gateway owns the declarative config module and generates all config files.
# cairn provides server definitions, prompts, commands, and aliases.
{
  config,
  lib,
  pkgs,
  inputs,
  osConfig ? { },
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  gatewayPort = osConfig.services.mcp-gateway.port or 8085;

  # AI role from the parent module. The MCP gateway is an AI concept
  # (not a PIM concept), so we gate on the AI module's own role.
  # Server hosts run MCP servers as stdio children locally; client
  # hosts proxy through the remote gateway's HTTP transport.
  aiRole = osConfig.services.ai.local.role or "server";
  isAiServer = aiRole == "server";

  # Base URL of the MCP gateway, computed once in modules/ai/default.nix
  # and reused everywhere (the MCP_GATEWAY_URL session var, the home-manager
  # mcp_servers.json generator, the codex config block). Consumers that
  # need the MCP-over-HTTP transport endpoint append "/mcp".
  gatewayUrl = osConfig.services.ai.mcp.gatewayUrl or "http://127.0.0.1:${toString gatewayPort}";
  mcpEndpoint = "${gatewayUrl}/mcp";

  codexMcpBlock = pkgs.writeText "codex-mcp-block.toml" ''
    [mcp_servers.cairn-mcp-gateway]
    url = "${mcpEndpoint}"
  '';

  # PIM configuration for calendar paths
  pimCfg = osConfig.services.pim or { };
  calendarAccounts = pimCfg.calendar.accounts or { };

  # Extract unique parent directories from calendar account localPaths
  # Default to ~/.calendars, plus any custom paths like ~/.calendars-external/...
  calendarPaths =
    let
      defaultPath = "~/.calendars";
      # Collect non-null external paths
      externalPaths = lib.unique (
        lib.filter (p: p != null) (
          lib.mapAttrsToList (
            name: account:
            let
              path = account.localPath or null;
              cleanPath = if path != null then lib.removeSuffix "/" path else null;
            in
            # Check for external calendar directories
            if cleanPath != null && lib.hasPrefix "~/.calendars-external" cleanPath then
              "~/.calendars-external"
            else
              null
          ) calendarAccounts
        )
      );
    in
    lib.concatStringsSep ":" ([ defaultPath ] ++ externalPaths);

in
{
  # Import mcp-gateway's home-manager module
  imports = [
    inputs.mcp-gateway.homeManagerModules.default
  ];

  config = lib.mkIf (osConfig.services.ai.mcp.enable or false) {
    # Configure mcp-gateway with cairn's server definitions
    services.mcp-gateway = {
      enable = true;

      # Let NixOS manage the systemd service when mcp-gateway NixOS module is enabled
      # (NixOS module handles OAuth secrets via agenix)
      manageService = !(osConfig.services.mcp-gateway.enable or false);

      # Pass through gateway settings from NixOS config (if using NixOS module)
      # Otherwise use defaults
      port = gatewayPort;
      autoEnable =
        osConfig.services.mcp-gateway.autoEnable or [
          "github"
          "mcp-dav"
          "cairn-mail"
          "brave-search"
        ];

      # MCP Server Definitions
      # All servers with fully resolved paths from cairn inputs
      servers = {
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # CORE TOOLS (No setup required)
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        github = {
          enable = true;
          command = "${pkgs.github-mcp-server}/bin/github-mcp-server";
          args = [ "stdio" ];
          passwordCommand = {
            GITHUB_PERSONAL_ACCESS_TOKEN = [
              (lib.getExe config.programs.gh.package)
              "auth"
              "token"
            ];
          };
        };

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # PIM TOOLS — server role only
        # On client hosts these stdio entries are disabled and replaced by
        # the unified `cairn` HTTP entry below, which proxies to the
        # remote gateway's aggregated MCP-over-HTTP endpoint.
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        cairn-mail = {
          enable = isAiServer;
          command = "${inputs.cairn-mail.packages.${system}.default}/bin/cairn-mail";
          args = [ "mcp" ];
          env = {
            # The cairn-mail API now requires a bearer token; the MCP server
            # reads it from this file (owner keith, 0400) and attaches it to
            # every API call. Only runs where isAiServer (the mail host), which
            # is where /run/agenix/cairn-mail-token exists.
            CAIRN_MAIL_TOKEN_FILE = "/run/agenix/cairn-mail-token";
          };
        };

        mcp-dav = {
          enable = isAiServer;
          command = "${inputs.cairn-dav.packages.${system}.mcp-dav}/bin/mcp-dav";
          env = {
            # Dynamic calendar paths from services.pim.calendar.accounts
            # Supports multiple paths separated by colons (e.g., ~/.calendars:~/.calendars-external)
            MCP_DAV_CALENDARS = calendarPaths;
            MCP_DAV_CONTACTS = "~/.contacts";
          };
        };

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # REMOTE MCP GATEWAY — client role only
        # Single MCP-over-HTTP entry that proxies every tool exposed by
        # the remote cairn-mcp-gateway Tailscale Service (mail, dav,
        # sentinel, home-assistant, whatever the server host has wired
        # up). Tools come back namespaced by the gateway as
        # `<server-id>__<tool>`, which claude-code in turn exposes as
        # `mcp__cairn-mcp-gateway__<server-id>__<tool>`.
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        cairn-mcp-gateway = {
          enable = !isAiServer;
          transport = "http";
          url = mcpEndpoint;
        };

        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        # SEARCH SERVERS (Require API keys)
        # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        brave-search = {
          enable = true;
          command = "${pkgs.nodejs}/bin/npx";
          args = [
            "-y"
            "@modelcontextprotocol/server-brave-search"
          ];
          passwordCommand = {
            BRAVE_API_KEY = [
              "${pkgs.bash}/bin/bash"
              "-c"
              # Check NixOS agenix path first, then home-manager agenix, then env var
              "${pkgs.coreutils}/bin/cat /run/agenix/brave-api-key 2>/dev/null || ${pkgs.coreutils}/bin/cat /run/user/$(${pkgs.coreutils}/bin/id -u)/agenix/brave-api-key 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '\\n' || echo \${BRAVE_API_KEY}"
            ];
          };
        };
      };
    };

    # Install MCP server packages
    home.packages = [
      inputs.cairn-mail.packages.${system}.default
      inputs.cairn-dav.packages.${system}.mcp-dav
    ];

    # Codex uses ~/.codex/config.toml rather than XDG config paths.
    # Merge the cairn MCP block into the user config so model, trust, and
    # migration settings already present in the file are preserved.
    home.activation.codexMcpConfig = lib.mkIf (osConfig.services.ai.openai.enable or false) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        codex_dir="$HOME/.codex"
        codex_config="$codex_dir/config.toml"
        temp_file="$(${pkgs.coreutils}/bin/mktemp)"

        ${pkgs.coreutils}/bin/mkdir -p "$codex_dir"

        if [ -f "$codex_config" ]; then
          # Strip any prior cairn-managed mcp_servers block. Matches both
          # the legacy [mcp_servers.cairn] section name and the current
          # [mcp_servers.cairn-mcp-gateway] name so existing configs get
          # cleaned up on rebuild.
          ${pkgs.gawk}/bin/awk '
            BEGIN { skip = 0 }
            /^\[mcp_servers\.cairn(-mcp-gateway)?\]$/ { skip = 1; next }
            /^\[/ && skip == 1 { skip = 0 }
            skip == 0 { print }
          ' "$codex_config" > "$temp_file"
        fi

        if [ -s "$temp_file" ]; then
          printf "\n" >> "$temp_file"
        fi

        ${pkgs.coreutils}/bin/cat ${codexMcpBlock} >> "$temp_file"
        ${pkgs.coreutils}/bin/mv "$temp_file" "$codex_config"
        ${pkgs.coreutils}/bin/chmod 600 "$codex_config"
      ''
    );
  };
}
