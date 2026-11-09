#!/usr/bin/env bash
# cairn init - Interactive configuration generator for Cairn
# Uses gum (charmbracelet/gum) for a modern TUI experience
set -euo pipefail

# ──────────────────────────────────────────────────────────────────
# Help & early exits
# ──────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: nix run github:kcalvelli/cairn#init [OPTIONS]

Initialize or extend an Cairn NixOS configuration.

Options:
  -h, --help    Show this help message and exit

Modes:
  New configuration          Create a fresh Cairn config in ~/.config/nixos_config
  Add host to existing       Clone an existing config repo and add a new host
  AI-assisted configuration  Launch Claude Code to interactively guide setup

For more information, see: https://github.com/kcalvelli/cairn
EOF
  exit 0
fi

# ──────────────────────────────────────────────────────────────────
# Prerequisites
# ──────────────────────────────────────────────────────────────────
if ! command -v gum >/dev/null 2>&1; then
  echo "Error: gum is required but not found on PATH."
  echo "This script should be run via: nix run github:kcalvelli/cairn#init"
  exit 1
fi

# ──────────────────────────────────────────────────────────────────
# Trap: clean exit on Ctrl-C
# ──────────────────────────────────────────────────────────────────
cleanup() {
  echo ""
  gum style --foreground 208 "Cancelled."
  exit 130
}
trap cleanup INT

# ──────────────────────────────────────────────────────────────────
# Template directory
# ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${CAIRN_TEMPLATE_DIR:-${SCRIPT_DIR}/templates}"

# ──────────────────────────────────────────────────────────────────
# Gum wrapper functions
# ──────────────────────────────────────────────────────────────────
banner() {
  gum style \
    --border double \
    --border-foreground 33 \
    --padding "1 3" \
    --align center \
    --bold \
    '   ____ __  ___(_)___  _____
  / __ `/ |/_/ / __ \/ ___/
 / /_/ />  </ / /_/ (__  )
 \__,_/_/|_/_/\____/____/

 Configuration Generator'
}

section_header() {
  echo ""
  gum style --foreground 33 --bold "$1"
}

info_box() {
  gum style \
    --border rounded \
    --border-foreground 243 \
    --padding "0 2" \
    "$@"
}

ask_input() {
  local prompt="$1"
  local default="${2:-}"
  if [ -n "$default" ]; then
    gum input --placeholder "$prompt" --value "$default" --prompt "> " --width 50
  else
    local result=""
    while [ -z "$result" ]; do
      result=$(gum input --placeholder "$prompt" --prompt "> " --width 50)
      if [ -z "$result" ]; then
        gum style --foreground 196 "This field is required."
      fi
    done
    echo "$result"
  fi
}

ask_confirm() {
  local prompt="$1"
  local default="${2:-no}"
  if [ "$default" = "yes" ]; then
    gum confirm --default=yes "$prompt"
  else
    gum confirm "$prompt"
  fi
}

ask_choose() {
  local prompt="$1"
  shift
  gum choose --header "$prompt" "$@"
}

ask_multi() {
  local prompt="$1"
  shift
  gum choose --no-limit --header "$prompt" "$@"
}

# ──────────────────────────────────────────────────────────────────
# Hardware detection
# ──────────────────────────────────────────────────────────────────
detect_hardware() {
  DETECTED_CPU=""
  DETECTED_GPU=""
  DETECTED_LAPTOP=""
  DETECTED_SSD=""
  DETECTED_TIMEZONE=""

  local lines=()

  if [ -f /etc/NIXOS ]; then
    # CPU
    if grep -q "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
      DETECTED_CPU="intel"
      lines+=("CPU: Intel")
    elif grep -q "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
      DETECTED_CPU="amd"
      lines+=("CPU: AMD")
    fi

    # GPU
    if lspci 2>/dev/null | grep -i vga | grep -qi nvidia; then
      DETECTED_GPU="nvidia"
      lines+=("GPU: NVIDIA")
    elif lspci 2>/dev/null | grep -i vga | grep -qi amd; then
      DETECTED_GPU="amd"
      lines+=("GPU: AMD")
    elif lspci 2>/dev/null | grep -i vga | grep -qi intel; then
      DETECTED_GPU="intel"
      lines+=("GPU: Intel")
    fi

    # Form factor
    if compgen -G "/sys/class/power_supply/BAT*" >/dev/null 2>&1 || [ -d /sys/class/power_supply/battery ] 2>/dev/null; then
      DETECTED_LAPTOP="true"
      lines+=("Form factor: Laptop (battery detected)")
    else
      DETECTED_LAPTOP="false"
      lines+=("Form factor: Desktop (no battery)")
    fi

    # SSD
    if lsblk -d -o name,rota 2>/dev/null | grep -q "0$"; then
      DETECTED_SSD="true"
      lines+=("Storage: SSD detected")
    else
      DETECTED_SSD="false"
      lines+=("Storage: HDD (no SSD)")
    fi

    # Timezone
    if command -v timedatectl >/dev/null 2>&1; then
      DETECTED_TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "")
      if [ -n "$DETECTED_TIMEZONE" ]; then
        lines+=("Timezone: $DETECTED_TIMEZONE")
      fi
    fi

    if [ ${#lines[@]} -gt 0 ]; then
      section_header "Detected Hardware"
      info_box "${lines[@]}"
    fi
  else
    gum style --foreground 208 "Not running on NixOS — hardware detection limited."
  fi
}

# ──────────────────────────────────────────────────────────────────
# Collect system information (shared by both modes)
# ──────────────────────────────────────────────────────────────────
collect_system_info() {
  local default_hostname
  default_hostname=$(hostname 2>/dev/null || echo "nixos")

  section_header "System Information"

  HOSTNAME=$(ask_input "Hostname" "$default_hostname")

  # Form factor
  if [ -n "$DETECTED_LAPTOP" ]; then
    if [ "$DETECTED_LAPTOP" = "true" ]; then
      FORMFACTOR="laptop"
    else
      FORMFACTOR="desktop"
    fi
  else
    FORMFACTOR=$(ask_choose "Form factor?" "desktop" "laptop")
  fi

  # CPU
  if [ -n "$DETECTED_CPU" ]; then
    CPU="$DETECTED_CPU"
  else
    CPU=$(ask_choose "CPU vendor?" "amd" "intel")
  fi

  # GPU
  if [ -n "$DETECTED_GPU" ]; then
    GPU="$DETECTED_GPU"
  else
    GPU=$(ask_choose "GPU vendor?" "amd" "nvidia" "intel")
  fi

  # SSD
  if [ -n "$DETECTED_SSD" ]; then
    HAS_SSD="$DETECTED_SSD"
  else
    if ask_confirm "Do you have an SSD?" "yes"; then
      HAS_SSD="true"
    else
      HAS_SSD="false"
    fi
  fi

  # Timezone
  if [ -n "$DETECTED_TIMEZONE" ]; then
    TIMEZONE=$(ask_input "Timezone" "$DETECTED_TIMEZONE")
  else
    TIMEZONE=$(ask_input "Timezone (e.g. America/New_York)")
  fi
}

# ──────────────────────────────────────────────────────────────────
# Collect primary user
# ──────────────────────────────────────────────────────────────────
collect_primary_user() {
  local default_user default_fullname
  default_user=$(whoami 2>/dev/null || echo "user")
  default_fullname=$(getent passwd "$(whoami 2>/dev/null || echo "$USER")" 2>/dev/null | cut -d: -f5 | cut -d, -f1 || echo "$default_user")

  section_header "Primary User (admin)"

  USERNAME=$(ask_input "Username" "$default_user")
  FULLNAME=$(ask_input "Full name" "$default_fullname")
  EMAIL=$(ask_input "Email address")
  USER_PROFILE=$(ask_choose "Desktop profile?" "standard" "normie")
}

# ──────────────────────────────────────────────────────────────────
# Collect additional users
# ──────────────────────────────────────────────────────────────────
collect_additional_users() {
  ADDITIONAL_USERS=()

  while true; do
    echo ""
    if ! ask_confirm "Add another user to this host?"; then
      break
    fi

    section_header "Additional User"
    local extra_user extra_full extra_email extra_admin
    extra_user=$(ask_input "Username")
    extra_full=$(ask_input "Full name")
    extra_email=$(ask_input "Email address (optional)" " ")
    extra_email=$(echo "$extra_email" | xargs)  # trim whitespace

    if ask_confirm "Admin access (sudo)?" "no"; then
      extra_admin="true"
    else
      extra_admin="false"
    fi
    local extra_profile
    extra_profile=$(ask_choose "Desktop profile?" "standard" "normie")

    ADDITIONAL_USERS+=("${extra_user}|${extra_full}|${extra_email}|${extra_admin}|${extra_profile}")
    gum style --foreground 42 "  Added user: ${extra_user}"
  done
}

# ──────────────────────────────────────────────────────────────────
# Collect optional features (flat multi-select)
# ──────────────────────────────────────────────────────────────────
collect_features() {
  section_header "Optional Features"

  ENABLE_AI="true"  # AI always enabled

  local selected
  selected=$(ask_multi "Select optional features (space to toggle, enter to confirm):" \
    "Gaming (Steam, GameMode, Proton)" \
    "PIM (cairn-mail email)" \
    "Immich (photo/video backup)" \
    "Local LLM (llama.cpp + OpenCode)" \
    "Secure Boot (Lanzaboote)" \
    "Secrets (age-encrypted)" \
    "Virtualization - libvirt/KVM" \
    "Virtualization - Containers (Podman)" \
    "Remote desktop (tailnet-only niri sessions)") || true

  # Parse selections
  ENABLE_GAMING="false"
  ENABLE_PIM="false"
  ENABLE_IMMICH="false"
  ENABLE_LOCAL_LLM="false"
  ENABLE_SECUREBOOT="false"
  ENABLE_SECRETS="false"
  ENABLE_LIBVIRT="false"
  ENABLE_CONTAINERS="false"
  ENABLE_REMOTE_DESKTOP="false"

  if echo "$selected" | grep -q "Gaming"; then
    ENABLE_GAMING="true"
  fi
  if echo "$selected" | grep -q "PIM"; then
    ENABLE_PIM="true"
  fi
  if echo "$selected" | grep -q "Immich"; then
    ENABLE_IMMICH="true"
  fi
  if echo "$selected" | grep -q "Local LLM"; then
    ENABLE_LOCAL_LLM="true"
  fi
  if echo "$selected" | grep -q "Secure Boot"; then
    ENABLE_SECUREBOOT="true"
  fi
  if echo "$selected" | grep -q "Secrets"; then
    ENABLE_SECRETS="true"
  fi
  if echo "$selected" | grep -q "libvirt"; then
    ENABLE_LIBVIRT="true"
  fi
  if echo "$selected" | grep -q "Containers"; then
    ENABLE_CONTAINERS="true"
  fi
  if echo "$selected" | grep -q "Remote desktop"; then
    ENABLE_REMOTE_DESKTOP="true"
  fi

  # Derive ENABLE_VIRT from sub-options
  if [ "$ENABLE_LIBVIRT" = "true" ] || [ "$ENABLE_CONTAINERS" = "true" ]; then
    ENABLE_VIRT="true"
  else
    ENABLE_VIRT="false"
  fi

  # Sub-options for features with roles
  PIM_ROLE="server"
  PIM_USER=""
  IMMICH_ROLE="server"
  LOCAL_LLM_ROLE="server"
  TAILNET_DOMAIN=""

  if [ "$ENABLE_PIM" = "true" ]; then
    echo ""
    PIM_ROLE=$(ask_choose "PIM role for this host?" "server" "server" "client")
    if [ "$PIM_ROLE" = "server" ]; then
      PIM_USER="$USERNAME"
    fi
  fi

  if [ "$ENABLE_IMMICH" = "true" ]; then
    echo ""
    IMMICH_ROLE=$(ask_choose "Immich role for this host?" "client" "server" "client")
  fi

  if [ "$ENABLE_LOCAL_LLM" = "true" ]; then
    echo ""
    LOCAL_LLM_ROLE=$(ask_choose "Local LLM role for this host?" "server" "server" "client")
  fi

  # Ask for tailnet domain if any feature needs it
  local needs_tailnet="false"
  if [ "$ENABLE_PIM" = "true" ] && [ "$PIM_ROLE" = "client" ]; then
    needs_tailnet="true"
  fi
  if [ "$ENABLE_IMMICH" = "true" ]; then
    needs_tailnet="true"
  fi
  if [ "$ENABLE_LOCAL_LLM" = "true" ] && [ "$LOCAL_LLM_ROLE" = "client" ]; then
    needs_tailnet="true"
  fi

  if [ "$needs_tailnet" = "true" ]; then
    echo ""
    TAILNET_DOMAIN=$(ask_input "Tailscale tailnet domain (e.g. tail1234.ts.net)")
  fi
}

# ──────────────────────────────────────────────────────────────────
# Compute derived values
# ──────────────────────────────────────────────────────────────────
compute_derived() {
  IS_LAPTOP=$([ "$FORMFACTOR" = "laptop" ] && echo "true" || echo "false")
  HOME_PROFILE="standard"

  HAS_SSD_TEXT=""
  if [ "$HAS_SSD" = "true" ]; then
    HAS_SSD_TEXT=", SSD"
  fi

  # Users list for host config template
  USERS_LIST="\"${USERNAME}\""
  for user_entry in "${ADDITIONAL_USERS[@]+"${ADDITIONAL_USERS[@]}"}"; do
    IFS='|' read -r u_name _u_full _u_email _u_admin _u_profile <<< "$user_entry"
    USERS_LIST="${USERS_LIST} \"${u_name}\""
  done

  DESCRIPTION="NixOS configuration for ${HOSTNAME}"
  DATE=$(date +"%Y-%m-%d")

  # Secrets config line for host template
  if [ "$ENABLE_SECRETS" = "true" ]; then
    SECRETS_CONFIG="      # Configure secrets directory for automatic discovery\\n      secrets.secretsDir = ../secrets;"
  else
    SECRETS_CONFIG=""
  fi

  # Build EXTRA_CONFIG for new features
  EXTRA_CONFIG=""

  if [ "$ENABLE_SECUREBOOT" = "true" ]; then
    EXTRA_CONFIG="${EXTRA_CONFIG}\\n      # Secure boot\\n      boot.lanzaboote.enableSecureBoot = true;"
  fi

  if [ -n "$TAILNET_DOMAIN" ]; then
    EXTRA_CONFIG="${EXTRA_CONFIG}\\n\\n      # Tailscale tailnet domain\\n      networking.tailscale.domain = \"${TAILNET_DOMAIN}\";"
  fi

  if [ "$ENABLE_PIM" = "true" ]; then
    EXTRA_CONFIG="${EXTRA_CONFIG}\\n\\n      # PIM (cairn-mail)\\n      services.pim.role = \"${PIM_ROLE}\";"
    if [ "$PIM_ROLE" = "server" ]; then
      EXTRA_CONFIG="${EXTRA_CONFIG}\\n      services.pim.user = \"${PIM_USER}\";"
    fi
  fi

  if [ "$ENABLE_IMMICH" = "true" ]; then
    EXTRA_CONFIG="${EXTRA_CONFIG}\\n\\n      # Immich photo/video backup\\n      cairn.immich.enable = true;\\n      cairn.immich.role = \"${IMMICH_ROLE}\";"
  fi

  if [ "$ENABLE_LOCAL_LLM" = "true" ]; then
    EXTRA_CONFIG="${EXTRA_CONFIG}\\n\\n      # Local LLM inference (llama.cpp)\\n      services.ai.local.enable = true;\\n      services.ai.local.role = \"${LOCAL_LLM_ROLE}\";"
    if [ "$LOCAL_LLM_ROLE" = "server" ]; then
      EXTRA_CONFIG="${EXTRA_CONFIG}\\n      # Download a GGUF model: nix run .#download-llama-models\\n      services.ai.local.model = \"/var/lib/llama-models/YOUR_MODEL.gguf\"; # FIXME: set model path"
    fi
    if [ "$LOCAL_LLM_ROLE" = "client" ] && [ -n "$TAILNET_DOMAIN" ]; then
      EXTRA_CONFIG="${EXTRA_CONFIG}\\n      services.ai.local.tailnetDomain = \"${TAILNET_DOMAIN}\";"
    fi
  fi
}

# ──────────────────────────────────────────────────────────────────
# NVIDIA kernel pre-flight check
# ──────────────────────────────────────────────────────────────────
nvidia_preflight() {
  local kernel_version kernel_major kernel_minor
  kernel_version=$(uname -r 2>/dev/null | cut -d. -f1-2 || echo "0.0")
  kernel_major=$(echo "$kernel_version" | cut -d. -f1)
  kernel_minor=$(echo "$kernel_version" | cut -d. -f2)
  if [ "$GPU" = "nvidia" ] && [ "$kernel_major" -ge 6 ] && [ "$kernel_minor" -ge 19 ] 2>/dev/null; then
    echo ""
    gum style --foreground 208 \
      "Hardware Note: NVIDIA GPU detected with kernel ${kernel_version}" \
      "NVIDIA drivers are not yet compatible with kernel 6.19+." \
      "Cairn will automatically pin your kernel to 6.18 for NVIDIA systems."
  fi
}

# ──────────────────────────────────────────────────────────────────
# Show summary and confirm
# ──────────────────────────────────────────────────────────────────
show_summary() {
  section_header "Configuration Summary"

  local lines=()
  lines+=("Hostname:      $HOSTNAME")
  lines+=("Primary user:  $USERNAME ($FULLNAME) [admin, $USER_PROFILE]")
  lines+=("Email:         $EMAIL")

  for user_entry in "${ADDITIONAL_USERS[@]+"${ADDITIONAL_USERS[@]}"}"; do
    IFS='|' read -r u_name u_full _u_email u_admin u_profile <<< "$user_entry"
    if [ "$u_admin" = "true" ]; then
      lines+=("User:          $u_name ($u_full) [admin, $u_profile]")
    else
      lines+=("User:          $u_name ($u_full) [$u_profile]")
    fi
  done

  lines+=("Timezone:      $TIMEZONE")
  lines+=("Form factor:   $FORMFACTOR")
  lines+=("Hardware:      $CPU CPU, $GPU GPU")
  lines+=("SSD:           $HAS_SSD")
  lines+=("")
  lines+=("Gaming:        $ENABLE_GAMING")
  lines+=("Remote desk:   $ENABLE_REMOTE_DESKTOP")
  if [ "$ENABLE_PIM" = "true" ]; then
    lines+=("PIM:           $ENABLE_PIM ($PIM_ROLE)")
  else
    lines+=("PIM:           $ENABLE_PIM")
  fi
  if [ "$ENABLE_IMMICH" = "true" ]; then
    lines+=("Immich:        $ENABLE_IMMICH ($IMMICH_ROLE)")
  else
    lines+=("Immich:        $ENABLE_IMMICH")
  fi
  if [ "$ENABLE_LOCAL_LLM" = "true" ]; then
    lines+=("Local LLM:     $ENABLE_LOCAL_LLM ($LOCAL_LLM_ROLE)")
  else
    lines+=("Local LLM:     $ENABLE_LOCAL_LLM")
  fi
  lines+=("Secure Boot:   $ENABLE_SECUREBOOT")
  lines+=("Secrets:       $ENABLE_SECRETS")
  lines+=("Virtualization: $ENABLE_VIRT")
  if [ "$ENABLE_VIRT" = "true" ]; then
    lines+=("  libvirt:     $ENABLE_LIBVIRT")
    lines+=("  containers:  $ENABLE_CONTAINERS")
  fi
  if [ -n "$TAILNET_DOMAIN" ]; then
    lines+=("")
    lines+=("Tailnet:       $TAILNET_DOMAIN")
  fi

  info_box "${lines[@]}"
}

# ──────────────────────────────────────────────────────────────────
# Generate user file from template
# ──────────────────────────────────────────────────────────────────
# Next free remote desktop port across every user file in the config.
# Ports live in user files and follow the user to every host, so they have
# to be unique config-wide, not just per host. Starts at 5901.
next_rd_port() {
  local target_dir="$1" max=5900 p f
  for f in "${target_dir}"/users/*.nix; do
    [ -f "$f" ] || continue
    p=$(sed -n 's/.*remoteDesktop\.port *= *\([0-9]\+\).*/\1/p' "$f" | head -1)
    if [ -n "$p" ] && [ "$p" -gt "$max" ]; then
      max=$p
    fi
  done
  echo $((max + 1))
}

generate_user_file() {
  local target_dir="$1"
  local u_name="$2"
  local u_full="$3"
  local u_email="$4"
  local u_admin="$5"
  local u_profile="${6:-standard}"

  if [ -f "${TEMPLATE_DIR}/user.nix.template" ]; then
    local u_rd_port
    u_rd_port=$(next_rd_port "$target_dir")
    sed -e "s|{{USERNAME}}|${u_name}|g" \
        -e "s|{{RD_PORT}}|${u_rd_port}|g" \
        -e "s|{{FULLNAME}}|${u_full}|g" \
        -e "s|{{EMAIL}}|${u_email}|g" \
        -e "s|{{IS_ADMIN}}|${u_admin}|g" \
        -e "s|{{HOME_PROFILE}}|${u_profile}|g" \
        "${TEMPLATE_DIR}/user.nix.template" > "${target_dir}/users/${u_name}.nix"
  fi
}

# ──────────────────────────────────────────────────────────────────
# Generate host files from templates
# ──────────────────────────────────────────────────────────────────
generate_host_files() {
  local target_dir="$1"

  mkdir -p "${target_dir}/hosts/${HOSTNAME}"

  # Host config
  if [ -f "${TEMPLATE_DIR}/host.nix.template" ]; then
    sed -e "s|{{HOSTNAME}}|${HOSTNAME}|g" \
        -e "s|{{USERNAME}}|${USERNAME}|g" \
        -e "s|{{TIMEZONE}}|${TIMEZONE}|g" \
        -e "s|{{FORMFACTOR}}|${FORMFACTOR}|g" \
        -e "s|{{CPU}}|${CPU}|g" \
        -e "s|{{GPU}}|${GPU}|g" \
        -e "s|{{HAS_SSD}}|${HAS_SSD}|g" \
        -e "s|{{IS_LAPTOP}}|${IS_LAPTOP}|g" \
        -e "s|{{HOME_PROFILE}}|${HOME_PROFILE}|g" \
        -e "s|{{ENABLE_GAMING}}|${ENABLE_GAMING}|g" \
        -e "s|{{ENABLE_REMOTE_DESKTOP}}|${ENABLE_REMOTE_DESKTOP}|g" \
        -e "s|{{ENABLE_PIM}}|${ENABLE_PIM}|g" \
        -e "s|{{ENABLE_AI}}|${ENABLE_AI}|g" \
        -e "s|{{ENABLE_SECRETS}}|${ENABLE_SECRETS}|g" \
        -e "s|{{ENABLE_VIRT}}|${ENABLE_VIRT}|g" \
        -e "s|{{ENABLE_LIBVIRT}}|${ENABLE_LIBVIRT}|g" \
        -e "s|{{ENABLE_CONTAINERS}}|${ENABLE_CONTAINERS}|g" \
        -e "s|{{USERS_LIST}}|${USERS_LIST}|g" \
        "${TEMPLATE_DIR}/host.nix.template" | \
        sed -e "s|{{SECRETS_CONFIG}}|${SECRETS_CONFIG}|g" \
            -e "s|{{EXTRA_CONFIG}}|${EXTRA_CONFIG}|g" > "${target_dir}/hosts/${HOSTNAME}.nix"
  fi

  # Hardware config
  if [ -f /etc/NIXOS ]; then
    gum spin --title "Running nixos-generate-config..." -- \
      sudo nixos-generate-config --root /etc 2>/dev/null || true

    if [ -f /etc/nixos/hardware-configuration.nix ]; then
      cp /etc/nixos/hardware-configuration.nix "${target_dir}/hosts/${HOSTNAME}/hardware.nix"
    else
      gum style --foreground 208 "Could not generate hardware-configuration.nix"
      echo "  You'll need to create hosts/${HOSTNAME}/hardware.nix manually"
    fi
  else
    gum style --foreground 208 "Not running on NixOS — cannot auto-generate hardware config"
    echo "  You'll need to create hosts/${HOSTNAME}/hardware.nix manually"
  fi
}

# ──────────────────────────────────────────────────────────────────
# Generate secrets directory
# ──────────────────────────────────────────────────────────────────
generate_secrets_dir() {
  local target_dir="$1"
  if [ "$ENABLE_SECRETS" = "true" ]; then
    mkdir -p "${target_dir}/secrets"
    cat > "${target_dir}/secrets/README.md" << 'EOF'
# Secrets Directory

This directory is for age-encrypted secrets.

## Quick Start

1. Get your host's public SSH key:
   ```bash
   sudo cat /etc/ssh/ssh_host_ed25519_key.pub
   ```

2. Create your first secret:
   ```bash
   echo "my-secret-value" | age -r "ssh-ed25519 AAAA... root@hostname" -o secrets/my-secret.age
   ```

3. Enable in your host config:
   Edit `hosts/hostname.nix` and add:
   ```nix
   extraConfig = {
     secrets.secretsDir = ../secrets;
   };
   ```

4. Rebuild and the secret will be available at `/run/agenix/my-secret`

See https://github.com/kcalvelli/cairn/blob/master/docs/SECRETS_MODULE.md for details.
EOF
  fi
}

# ──────────────────────────────────────────────────────────────────
# Show next steps
# ──────────────────────────────────────────────────────────────────
show_next_steps_new() {
  echo ""
  gum style --foreground 42 --bold "Configuration generated successfully!"
  echo ""

  section_header "Next Steps"

  local hw_status
  if [ -f "${CONFIG_DIR}/hosts/${HOSTNAME}/hardware.nix" ]; then
    hw_status="Hardware config copied from /etc/nixos/hardware-configuration.nix"
  else
    hw_status="Create hosts/${HOSTNAME}/hardware.nix (run nixos-generate-config)"
  fi

  info_box \
    "1. Review configuration:" \
    "   $hw_status" \
    "   Check hosts/${HOSTNAME}.nix for customizations" \
    "" \
    "2. Push to a git remote:" \
    "   cd ~/.config/nixos_config" \
    "   git remote add origin <your-repo-url>" \
    "   git push -u origin master"

  echo ""
  if ask_confirm "Rebuild system now as '${HOSTNAME}'?"; then
    echo ""
    gum style --foreground 33 --bold "Rebuilding system..."
    echo ""
    sudo env PATH="$PATH" nixos-rebuild switch --flake "${CONFIG_DIR}#${HOSTNAME}"
  else
    echo ""
    info_box \
      "When you're ready, rebuild with:" \
      "  sudo nixos-rebuild switch --flake ~/.config/nixos_config#${HOSTNAME}"
  fi

  echo ""
  gum style --foreground 33 "Welcome to Cairn!"
}

show_next_steps_add() {
  echo ""
  gum style --foreground 42 --bold "Host ${HOSTNAME} added successfully!"
  echo ""

  section_header "Next Steps"

  info_box \
    "1. Review the generated host config:" \
    "   hosts/${HOSTNAME}.nix" \
    "" \
    "2. Push changes:" \
    "   cd ${CONFIG_DIR}" \
    "   git push" \
    "" \
    "3. On the new machine, rebuild:" \
    "   sudo nixos-rebuild switch --flake <repo-url>#${HOSTNAME}"

  echo ""
  gum style --foreground 33 "Welcome to Cairn!"
}

# ══════════════════════════════════════════════════════════════════
# MODE A: New Configuration
# ══════════════════════════════════════════════════════════════════
new_config_flow() {
  detect_hardware
  collect_system_info
  collect_primary_user
  collect_additional_users
  collect_features
  compute_derived
  nvidia_preflight
  show_summary

  echo ""
  if ! ask_confirm "Generate configuration in ~/.config/nixos_config?"; then
    gum style --foreground 208 "Cancelled."
    exit 0
  fi

  # Create target directory
  CONFIG_DIR="${HOME}/.config/nixos_config"
  if [ -d "${CONFIG_DIR}" ] && [ "$(ls -A "${CONFIG_DIR}" 2>/dev/null | wc -l)" -gt 0 ]; then
    gum style --foreground 208 "Warning: ${CONFIG_DIR} is not empty."
    if ! ask_confirm "Continue anyway? This may overwrite files."; then
      gum style --foreground 208 "Cancelled."
      exit 1
    fi
  fi
  mkdir -p "${CONFIG_DIR}"

  gum spin --title "Generating configuration..." -- sleep 0.5

  # Directory structure
  mkdir -p "${CONFIG_DIR}/users"
  mkdir -p "${CONFIG_DIR}/hosts/${HOSTNAME}"

  # Primary user
  generate_user_file "$CONFIG_DIR" "$USERNAME" "$FULLNAME" "$EMAIL" "true" "$USER_PROFILE"

  # Additional users
  for user_entry in "${ADDITIONAL_USERS[@]+"${ADDITIONAL_USERS[@]}"}"; do
    IFS='|' read -r u_name u_full u_email u_admin u_profile <<< "$user_entry"
    generate_user_file "$CONFIG_DIR" "$u_name" "$u_full" "$u_email" "$u_admin" "$u_profile"
  done

  # flake.nix and README.md from templates
  for template in flake.nix README.md; do
    if [ -f "${TEMPLATE_DIR}/${template}.template" ]; then
      sed -e "s|{{HOSTNAME}}|${HOSTNAME}|g" \
          -e "s|{{USERNAME}}|${USERNAME}|g" \
          -e "s|{{FULLNAME}}|${FULLNAME}|g" \
          -e "s|{{EMAIL}}|${EMAIL}|g" \
          -e "s|{{TIMEZONE}}|${TIMEZONE}|g" \
          -e "s|{{FORMFACTOR}}|${FORMFACTOR}|g" \
          -e "s|{{CPU}}|${CPU}|g" \
          -e "s|{{GPU}}|${GPU}|g" \
          -e "s|{{HAS_SSD}}|${HAS_SSD}|g" \
          -e "s|{{IS_LAPTOP}}|${IS_LAPTOP}|g" \
          -e "s|{{HOME_PROFILE}}|${HOME_PROFILE}|g" \
          -e "s|{{ENABLE_GAMING}}|${ENABLE_GAMING}|g" \
          -e "s|{{ENABLE_REMOTE_DESKTOP}}|${ENABLE_REMOTE_DESKTOP}|g" \
          -e "s|{{ENABLE_PIM}}|${ENABLE_PIM}|g" \
          -e "s|{{ENABLE_AI}}|${ENABLE_AI}|g" \
          -e "s|{{ENABLE_SECRETS}}|${ENABLE_SECRETS}|g" \
          -e "s|{{ENABLE_VIRT}}|${ENABLE_VIRT}|g" \
          -e "s|{{ENABLE_LIBVIRT}}|${ENABLE_LIBVIRT}|g" \
          -e "s|{{ENABLE_CONTAINERS}}|${ENABLE_CONTAINERS}|g" \
          -e "s|{{DESCRIPTION}}|${DESCRIPTION}|g" \
          -e "s|{{DATE}}|${DATE}|g" \
          -e "s|{{HAS_SSD_TEXT}}|${HAS_SSD_TEXT}|g" \
          "${TEMPLATE_DIR}/${template}.template" > "${CONFIG_DIR}/${template}"
    fi
  done

  # Host files
  generate_host_files "$CONFIG_DIR"

  # Secrets directory
  generate_secrets_dir "$CONFIG_DIR"

  # .gitignore
  if [ -f "${TEMPLATE_DIR}/gitignore.template" ]; then
    cp "${TEMPLATE_DIR}/gitignore.template" "${CONFIG_DIR}/.gitignore"
  fi

  # Git init + commit
  (
    cd "${CONFIG_DIR}"
    git init -q
    git add .
    git commit -q -m "Initial Cairn configuration for ${HOSTNAME}"
  )

  show_next_steps_new
}

# ══════════════════════════════════════════════════════════════════
# MODE B: Add Host to Existing Configuration
# ══════════════════════════════════════════════════════════════════
add_host_flow() {
  section_header "Add Host to Existing Configuration"

  CONFIG_DIR="${HOME}/.config/nixos_config"

  if [ -d "${CONFIG_DIR}" ] && [ "$(ls -A "${CONFIG_DIR}" 2>/dev/null | wc -l)" -gt 0 ]; then
    gum style --foreground 208 "Warning: ${CONFIG_DIR} already exists."
    if ! ask_confirm "Use existing directory instead of cloning?"; then
      gum style --foreground 208 "Cancelled."
      exit 1
    fi
  else
    # Authenticate with GitHub if not already logged in
    if ! gh auth status >/dev/null 2>&1; then
      info_box \
        "GitHub authentication is required to clone your config repo." \
        "You'll be guided through login (works from any device)."
      echo ""
      gh auth login
    fi

    local git_url
    git_url=$(ask_input "Git repository URL or owner/repo (e.g. user/nixos-config)")

    gum spin --title "Cloning configuration..." -- \
      gh repo clone "$git_url" "$CONFIG_DIR"
  fi

  # Validate structure
  if [ ! -f "${CONFIG_DIR}/flake.nix" ]; then
    gum style --foreground 196 "Error: No flake.nix found in ${CONFIG_DIR}"
    echo "This does not appear to be a valid Cairn configuration."
    exit 1
  fi

  # Scan existing hosts and users
  local existing_hosts=()
  local existing_users=()

  if [ -d "${CONFIG_DIR}/hosts" ]; then
    for f in "${CONFIG_DIR}"/hosts/*.nix; do
      [ -f "$f" ] || continue
      existing_hosts+=("$(basename "$f" .nix)")
    done
  fi

  if [ -d "${CONFIG_DIR}/users" ]; then
    for f in "${CONFIG_DIR}"/users/*.nix; do
      [ -f "$f" ] || continue
      existing_users+=("$(basename "$f" .nix)")
    done
  fi

  section_header "Existing Configuration"
  local info_lines=()
  if [ ${#existing_hosts[@]} -gt 0 ]; then
    info_lines+=("Hosts: ${existing_hosts[*]}")
  else
    info_lines+=("Hosts: (none)")
  fi
  if [ ${#existing_users[@]} -gt 0 ]; then
    info_lines+=("Users: ${existing_users[*]}")
  else
    info_lines+=("Users: (none)")
  fi
  info_box "${info_lines[@]}"

  # Hardware detection
  detect_hardware

  # Collect new host info
  collect_system_info

  # Check for duplicate hostname
  for existing in "${existing_hosts[@]+"${existing_hosts[@]}"}"; do
    if [ "$existing" = "$HOSTNAME" ]; then
      gum style --foreground 196 "Error: Host '${HOSTNAME}' already exists in this configuration."
      exit 1
    fi
  done

  # User assignment
  section_header "User Assignment"

  # Let user select from existing users
  ADDITIONAL_USERS=()
  local assigned_users=()
  local primary_from_existing="false"

  if [ ${#existing_users[@]} -gt 0 ]; then
    echo "Select users to assign to this host."
    echo "The first selected user will be the primary admin."
    echo ""

    local selected_existing
    selected_existing=$(gum choose --no-limit --header "Assign existing users to ${HOSTNAME}:" \
      "${existing_users[@]}" \
      "(Create new user)") || true

    if echo "$selected_existing" | grep -q "Create new user"; then
      # Will collect below
      :
    fi

    # Process selected existing users
    local first="true"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      [ "$line" = "(Create new user)" ] && continue

      if [ "$first" = "true" ]; then
        USERNAME="$line"
        # Extract info from existing user file
        FULLNAME=$(grep -oP 'fullName\s*=\s*"\K[^"]+' "${CONFIG_DIR}/users/${line}.nix" 2>/dev/null || echo "$line")
        EMAIL=$(grep -oP 'email\s*=\s*"\K[^"]+' "${CONFIG_DIR}/users/${line}.nix" 2>/dev/null || echo "")
        primary_from_existing="true"
        first="false"
      else
        assigned_users+=("$line")
      fi
    done <<< "$selected_existing"
  fi

  # If no primary user from existing, collect new primary
  if [ "$primary_from_existing" = "false" ]; then
    collect_primary_user
    generate_user_file "$CONFIG_DIR" "$USERNAME" "$FULLNAME" "$EMAIL" "true" "$USER_PROFILE"
  fi

  # Build USERS_LIST from all assigned users
  USERS_LIST="\"${USERNAME}\""
  for u in "${assigned_users[@]+"${assigned_users[@]}"}"; do
    USERS_LIST="${USERS_LIST} \"${u}\""
  done

  # Ask to create additional new users
  while true; do
    echo ""
    if ! ask_confirm "Create a new user for this host?"; then
      break
    fi
    section_header "New User"
    local extra_user extra_full extra_email extra_admin
    extra_user=$(ask_input "Username")
    extra_full=$(ask_input "Full name")
    extra_email=$(ask_input "Email address (optional)" " ")
    extra_email=$(echo "$extra_email" | xargs)

    if ask_confirm "Admin access (sudo)?" "no"; then
      extra_admin="true"
    else
      extra_admin="false"
    fi
    local extra_profile
    extra_profile=$(ask_choose "Desktop profile?" "standard" "normie")

    generate_user_file "$CONFIG_DIR" "$extra_user" "$extra_full" "$extra_email" "$extra_admin" "$extra_profile"
    USERS_LIST="${USERS_LIST} \"${extra_user}\""
    gum style --foreground 42 "  Added user: ${extra_user}"
  done

  # Features
  collect_features
  compute_derived

  nvidia_preflight
  show_summary

  echo ""
  if ! ask_confirm "Add host ${HOSTNAME} to the configuration?"; then
    gum style --foreground 208 "Cancelled."
    exit 0
  fi

  # Generate host files
  gum spin --title "Generating host files..." -- sleep 0.3
  generate_host_files "$CONFIG_DIR"
  generate_secrets_dir "$CONFIG_DIR"

  # Insert into flake.nix
  local flake_file="${CONFIG_DIR}/flake.nix"
  if grep -q "mkHost" "$flake_file"; then
    if grep -q "\"${HOSTNAME}\"" "$flake_file"; then
      gum style --foreground 208 "Host '${HOSTNAME}' already referenced in flake.nix — skipping insertion."
    else
      local last_mkhost_line
      last_mkhost_line=$(grep -n "mkHost" "$flake_file" | tail -1 | cut -d: -f1)
      sed -i "${last_mkhost_line}a\\        ${HOSTNAME} = mkHost \"${HOSTNAME}\";" "$flake_file"
      gum style --foreground 42 "  Added ${HOSTNAME} to flake.nix"
    fi
  else
    gum style --foreground 208 "Could not find mkHost in flake.nix — add the host entry manually:"
    echo "  ${HOSTNAME} = mkHost \"${HOSTNAME}\";"
  fi

  # Commit
  (
    cd "${CONFIG_DIR}"
    git add .
    git commit -q -m "Add host: ${HOSTNAME}"
  )

  show_next_steps_add
}

# ══════════════════════════════════════════════════════════════════
# MODE C: AI-Assisted Configuration
# ══════════════════════════════════════════════════════════════════
ai_config_flow() {
  # Info box about requirements
  info_box \
    "AI-assisted configuration uses Claude Code to interactively" \
    "guide you through Cairn setup. Claude will detect your hardware," \
    "ask questions, and generate all configuration files." \
    "" \
    "Requirements:" \
    "  - A Claude account (you'll be prompted to log in if needed)" \
    "  - Internet connection"

  echo ""
  if ! ask_confirm "Launch AI-assisted configuration?"; then
    gum style --foreground 208 "Cancelled."
    exit 0
  fi

  # Run hardware detection (sets DETECTED_* vars)
  detect_hardware

  # Build display strings for the prompt template
  local cpu_display="${DETECTED_CPU:-Not detected}"
  local gpu_display="${DETECTED_GPU:-Not detected}"
  local ssd_display="Not detected"
  local formfactor_display="Not detected"
  local timezone_display="${DETECTED_TIMEZONE:-Not detected}"

  if [ -n "$DETECTED_LAPTOP" ]; then
    if [ "$DETECTED_LAPTOP" = "true" ]; then
      formfactor_display="Laptop (battery detected)"
    else
      formfactor_display="Desktop (no battery)"
    fi
  fi

  if [ -n "$DETECTED_SSD" ]; then
    if [ "$DETECTED_SSD" = "true" ]; then
      ssd_display="SSD detected"
    else
      ssd_display="HDD (no SSD detected)"
    fi
  fi

  # Read and substitute the prompt template
  local prompt_template="${TEMPLATE_DIR}/ai-install-prompt.md.template"
  if [ ! -f "$prompt_template" ]; then
    gum style --foreground 196 "Error: AI prompt template not found at ${prompt_template}"
    exit 1
  fi

  local system_prompt
  system_prompt=$(sed \
    -e "s|{{DETECTED_CPU_DISPLAY}}|${cpu_display}|g" \
    -e "s|{{DETECTED_GPU_DISPLAY}}|${gpu_display}|g" \
    -e "s|{{DETECTED_FORMFACTOR_DISPLAY}}|${formfactor_display}|g" \
    -e "s|{{DETECTED_SSD_DISPLAY}}|${ssd_display}|g" \
    -e "s|{{DETECTED_TIMEZONE_DISPLAY}}|${timezone_display}|g" \
    "$prompt_template")

  # Set up the config directory
  CONFIG_DIR="${HOME}/.config/nixos_config"
  mkdir -p "${CONFIG_DIR}"

  # Launch Claude Code with the system prompt
  echo ""
  gum style --foreground 33 --bold "Launching Claude Code..."
  echo ""

  (
    cd "${CONFIG_DIR}"
    claude --system-prompt "$system_prompt" "Help me set up my Cairn configuration."
  )

  # Post-session check
  echo ""
  if [ ! -f "${CONFIG_DIR}/flake.nix" ]; then
    gum style --foreground 208 \
      "Session ended without generating flake.nix." \
      "Re-run to try again, or use the scripted 'New configuration' mode."
    return
  fi

  gum style --foreground 42 --bold "Configuration generated at ${CONFIG_DIR}"
  echo ""

  # Collect available hosts from hosts/*.nix
  local hosts=()
  if [ -d "${CONFIG_DIR}/hosts" ]; then
    for f in "${CONFIG_DIR}"/hosts/*.nix; do
      [ -f "$f" ] || continue
      hosts+=("$(basename "$f" .nix)")
    done
  fi

  if [ ${#hosts[@]} -eq 0 ]; then
    info_box \
      "No host configs found in hosts/*.nix." \
      "Run manually: sudo nixos-rebuild switch --flake ${CONFIG_DIR}#<hostname>"
    return
  fi

  # If multiple hosts, let the user pick; if one, use it directly
  local selected_host=""
  if [ ${#hosts[@]} -eq 1 ]; then
    selected_host="${hosts[0]}"
  else
    echo ""
    selected_host=$(ask_choose "Which host do you want to rebuild?" "${hosts[0]}" "${hosts[@]}")
  fi

  if ask_confirm "Rebuild system now as '${selected_host}'?"; then
    echo ""
    gum style --foreground 33 --bold "Rebuilding system..."
    echo ""
    # Pass PATH through so nixos-rebuild can find git (needed for flakes)
    sudo env PATH="$PATH" nixos-rebuild switch --flake "${CONFIG_DIR}#${selected_host}"
  else
    echo ""
    info_box \
      "When you're ready, rebuild with:" \
      "  sudo nixos-rebuild switch --flake ${CONFIG_DIR}#${selected_host}"
  fi

  echo ""
  gum style --foreground 33 "Welcome to Cairn!"
}

# ══════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════
banner

echo ""
MODE=$(ask_choose "What would you like to do?" \
  "New configuration" \
  "Add host to existing config" \
  "AI-assisted configuration")

case "$MODE" in
  "New configuration")
    new_config_flow
    ;;
  "Add host to existing config")
    add_host_flow
    ;;
  "AI-assisted configuration")
    ai_config_flow
    ;;
esac
