#!/usr/bin/env bash
set -euo pipefail

PROJECT="hugobox"
INSTALL_DIR="/opt/${PROJECT}"
ETC_DIR="/etc/${PROJECT}"
LIB_DIR="/var/lib/${PROJECT}"
SYSTEMD_DIR="/etc/systemd/system"

REPO_URL="https://kiosk.hugobox.nl"
DOTNET_VERSION="10.0"

usage() {
  cat <<EOF
Usage: $0 [install|upgrade|uninstall|status]

Examples:
  curl -fsSL ${REPO_URL}/install.sh | sudo bash
  sudo $0 install
  sudo $0 upgrade
  sudo $0 uninstall
  $0 status
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "❌ Run as root: sudo $0 install"
    exit 1
  fi
}

log() { echo "[$(date +'%F %T')] $*"; }

detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  else
    echo "unknown"
  fi
}

install_dotnet() {
  log "Installing .NET ${DOTNET_VERSION} SDK"

  # Check if dotnet is already installed
  if command -v dotnet >/dev/null 2>&1; then
    local installed_version
    installed_version=$(dotnet --version 2>/dev/null || echo "0.0.0")
    log "Found .NET version: ${installed_version}"

    # Check if it's .NET 10+
    if [[ "${installed_version}" =~ ^10\. ]]; then
      log ".NET 10 already installed, skipping"
      return 0
    fi
  fi

  # Install .NET using Microsoft's official script
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  log "Downloading .NET install script"
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o "${tmpdir}/dotnet-install.sh"
  chmod +x "${tmpdir}/dotnet-install.sh"

  # Install to /usr/local/dotnet
  "${tmpdir}/dotnet-install.sh" --channel ${DOTNET_VERSION} --install-dir /usr/local/dotnet

  # Create symlink if it doesn't exist
  if [[ ! -L /usr/local/bin/dotnet ]]; then
    ln -sf /usr/local/dotnet/dotnet /usr/local/bin/dotnet
  fi

  # Verify installation
  if ! /usr/local/bin/dotnet --version >/dev/null 2>&1; then
    log "❌ .NET installation failed"
    exit 1
  fi

  log "✅ .NET ${DOTNET_VERSION} installed successfully"
}

install_deps() {
  local pm
  pm="$(detect_pkg_mgr)"

  log "Installing system dependencies (package manager: ${pm})"
  case "$pm" in
    apt)
      apt-get update -y
      # Raspberry Pi OS packages
      apt-get install -y --no-install-recommends \
        ca-certificates curl jq tar wget unzip \
        systemd \
        chromium-browser || apt-get install -y --no-install-recommends chromium
      ;;
    dnf)
      dnf install -y ca-certificates curl jq tar wget unzip systemd chromium
      ;;
    *)
      log "⚠️ Unknown package manager. Install manually: curl jq tar wget chromium systemd"
      ;;
  esac

  # Install .NET 10
  install_dotnet
}

ensure_dirs() {
  log "Creating directories"
  mkdir -p "$INSTALL_DIR" "$ETC_DIR" "$LIB_DIR" "${INSTALL_DIR}/scripts" "${INSTALL_DIR}/systemd"
  chmod 0755 "$INSTALL_DIR" "$ETC_DIR" "$LIB_DIR"

  # Create chromium profile directory owned by the kiosk user (pi)
  mkdir -p "$LIB_DIR/chromium-profile"
  chown pi:pi "$LIB_DIR/chromium-profile" 2>/dev/null || true
}

download_files() {
  log "Downloading project files from ${REPO_URL}"

  # Download gamepad daemon
  curl -fsSL "${REPO_URL}/scripts/gamepad-daemon.cs" -o "${INSTALL_DIR}/scripts/gamepad-daemon.cs"

  # Download scripts
  curl -fsSL "${REPO_URL}/scripts/gamepad-daemon.sh" -o "${INSTALL_DIR}/scripts/gamepad-daemon.sh"
  curl -fsSL "${REPO_URL}/scripts/kiosk-start.sh" -o "${INSTALL_DIR}/scripts/kiosk-start.sh"

  # Download systemd units
  curl -fsSL "${REPO_URL}/systemd/hugobox-gamepad.service" -o "${INSTALL_DIR}/systemd/hugobox-gamepad.service"
  curl -fsSL "${REPO_URL}/systemd/hugobox-kiosk.service" -o "${INSTALL_DIR}/systemd/hugobox-kiosk.service"

  # Download config example
  curl -fsSL "${REPO_URL}/hugobox.env.example" -o "${INSTALL_DIR}/hugobox.env.example"

  # Download install.sh itself so it can be re-run for status/upgrade
  curl -fsSL "${REPO_URL}/install.sh" -o "${INSTALL_DIR}/install.sh"

  # Make scripts executable
  chmod +x "${INSTALL_DIR}/install.sh"
  chmod +x "${INSTALL_DIR}/scripts/"*.sh
  chmod +x "${INSTALL_DIR}/scripts/gamepad-daemon.cs"

  log "✅ Files downloaded"
}

install_config() {
  if [[ ! -f "${ETC_DIR}/config.env" ]]; then
    log "Installing default config to ${ETC_DIR}/config.env"
    if [[ -f "${INSTALL_DIR}/hugobox.env.example" ]]; then
      cp "${INSTALL_DIR}/hugobox.env.example" "${ETC_DIR}/config.env"
    else
      cat > "${ETC_DIR}/config.env" <<EOF
# /etc/hugobox/config.env

# Waar je kiosk heen moet
HUGOBOX_URL="https://hugobox.nl"

# Chromium flags (kiosk)
HUGOBOX_CHROMIUM_FLAGS="--kiosk --noerrdialogs --disable-infobars --autoplay-policy=no-user-gesture-required"

# Poort voor lokale API/service (als je die hebt)
HUGOBOX_API_PORT="12345"

# Gamepad combos (voorbeeld, pas aan naar je eigen daemon)
HUGOBOX_COMBO_RESTART="START+BACK+A"
HUGOBOX_COMBO_SHUTDOWN="START+BACK+B"
HUGOBOX_COMBO_EXIT="START+BACK+X"
EOF
    fi
    chmod 0644 "${ETC_DIR}/config.env"
  else
    log "Config exists: ${ETC_DIR}/config.env (keeping existing)"
  fi
}

install_services() {
  log "Installing systemd units"

  cp "${INSTALL_DIR}/systemd/${PROJECT}-kiosk.service" "${SYSTEMD_DIR}/${PROJECT}-kiosk.service"
  cp "${INSTALL_DIR}/systemd/${PROJECT}-gamepad.service" "${SYSTEMD_DIR}/${PROJECT}-gamepad.service"

  chmod 0644 "${SYSTEMD_DIR}/${PROJECT}-kiosk.service" "${SYSTEMD_DIR}/${PROJECT}-gamepad.service"

  systemctl daemon-reload
  systemctl enable "${PROJECT}-kiosk.service" "${PROJECT}-gamepad.service"

  log "✅ Services installed and enabled"
}

restart_services() {
  log "Restarting services"
  systemctl restart "${PROJECT}-gamepad.service" || true
  systemctl restart "${PROJECT}-kiosk.service" || true
}

stop_services() {
  log "Stopping services"
  systemctl stop "${PROJECT}-kiosk.service" "${PROJECT}-gamepad.service" 2>/dev/null || true
}

disable_services() {
  log "Disabling services"
  systemctl disable "${PROJECT}-kiosk.service" "${PROJECT}-gamepad.service" 2>/dev/null || true
  rm -f "${SYSTEMD_DIR}/${PROJECT}-kiosk.service" "${SYSTEMD_DIR}/${PROJECT}-gamepad.service"
  systemctl daemon-reload
}

status() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "HugoBox Kiosk Status"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Install dir: $INSTALL_DIR"
  echo "Config:      ${ETC_DIR}/config.env"
  echo ".NET:        $(dotnet --version 2>/dev/null || echo 'not installed')"
  echo ""
  echo "━━━ Kiosk Service ━━━"
  systemctl --no-pager status "${PROJECT}-kiosk.service" 2>/dev/null || echo "Not running"
  echo ""
  echo "━━━ Gamepad Service ━━━"
  systemctl --no-pager status "${PROJECT}-gamepad.service" 2>/dev/null || echo "Not running"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

do_install_or_upgrade() {
  need_root
  log "Starting installation/upgrade"
  install_deps
  ensure_dirs
  stop_services
  download_files
  install_config
  install_services
  restart_services

  log "✅ Installation complete!"
  log ""
  log "Config:   sudo nano ${ETC_DIR}/config.env"
  log "Logs:     journalctl -u ${PROJECT}-kiosk -f"
  log "          journalctl -u ${PROJECT}-gamepad -f"
  log "Status:   ${INSTALL_DIR}/install.sh status"
  log "Upgrade:  sudo ${INSTALL_DIR}/install.sh upgrade"
}

do_uninstall() {
  need_root
  stop_services
  disable_services

  log "Removing ${INSTALL_DIR}"
  rm -rf "$INSTALL_DIR"

  log "Keeping config in ${ETC_DIR} (remove manually if desired)"
  log "✅ Uninstalled"
}

# Main execution
cmd="${1:-install}"
case "$cmd" in
  install)   do_install_or_upgrade ;;
  upgrade)   do_install_or_upgrade ;;
  uninstall) do_uninstall ;;
  status)    status ;;
  *) usage; exit 1 ;;
esac
