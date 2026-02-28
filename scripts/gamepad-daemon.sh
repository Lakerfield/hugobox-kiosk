#!/usr/bin/env bash
set -euo pipefail

# Load config
if [[ -f /etc/hugobox/config.env ]]; then
  source /etc/hugobox/config.env
fi

# Set environment variables for the C# script
export GP_DEVICE="${GP_DEVICE:-/dev/input/js0}"
export CHROMIUM_UNIT="${CHROMIUM_UNIT:-hugobox-kiosk.service}"
export COMBO_HOLD_MS="${COMBO_HOLD_MS:-250}"

# Ensure dotnet is in PATH
export PATH="$PATH:/usr/local/bin"

# Run the gamepad daemon using native .NET 10
cd /opt/hugobox/scripts
exec dotnet run gamepad-daemon.cs
