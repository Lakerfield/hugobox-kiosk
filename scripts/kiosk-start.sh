#!/usr/bin/env bash
set -euo pipefail

# Load config
if [[ -f /etc/hugobox/config.env ]]; then
  source /etc/hugobox/config.env
fi

# Default values
HUGOBOX_URL="${HUGOBOX_URL:-https://hugobox.nl}"
HUGOBOX_CHROMIUM_FLAGS="${HUGOBOX_CHROMIUM_FLAGS:---kiosk --noerrdialogs --disable-infobars --autoplay-policy=no-user-gesture-required}"

# Wayland environment setup
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# Wait for Wayland to be ready
echo "Waiting for Wayland display..."
timeout=30
while [[ ! -e "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]] && [[ $timeout -gt 0 ]]; do
  sleep 1
  ((timeout--))
done

if [[ ! -e "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]]; then
  echo "ERROR: Wayland display not available at ${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
  exit 1
fi

# Kill any existing chromium processes to prevent tab-opening loop
echo "Checking for existing Chromium processes..."
pkill -u "$(whoami)" chromium-browser 2>/dev/null || pkill -u "$(whoami)" chromium 2>/dev/null || true
sleep 1

echo "Starting Chromium in kiosk mode on ${HUGOBOX_URL}"
echo "Flags: ${HUGOBOX_CHROMIUM_FLAGS}"

# Try chromium-browser first, fallback to chromium
if command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN=chromium-browser
elif command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN=chromium
else
  echo "ERROR: chromium-browser or chromium not found"
  exit 1
fi

# Additional Wayland-specific flags
WAYLAND_FLAGS="--enable-features=UseOzonePlatform --ozone-platform=wayland"

# Disable GPU if running headless or in virtual environment
# Remove --disable-gpu if you have proper GPU support
EXTRA_FLAGS="--disable-gpu --no-sandbox --disable-dev-shm-usage"

# Use isolated user data directory to prevent conflicts with desktop chromium
USER_DATA_DIR="/var/lib/hugobox/chromium-profile"
mkdir -p "$USER_DATA_DIR"
chown "$(whoami):$(whoami)" "$USER_DATA_DIR" 2>/dev/null || true

# Start chromium
exec $CHROMIUM_BIN \
  $HUGOBOX_CHROMIUM_FLAGS \
  $WAYLAND_FLAGS \
  $EXTRA_FLAGS \
  --user-data-dir="$USER_DATA_DIR" \
  --disable-session-crashed-bubble \
  --disable-restore-session-state \
  --no-first-run \
  --check-for-update-interval=31536000 \
  "$HUGOBOX_URL"
