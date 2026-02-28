# HugoBox Kiosk

Raspberry Pi kiosk setup for HugoBox with gamepad control support.

## Features

- **Chromium Kiosk Mode** - Full-screen browser on Wayland
- **Gamepad Control** - Native .NET 10 gamepad daemon for system control
- **Auto-start** - Systemd services for automatic startup
- **One-line Install** - Simple curl-to-bash installation

## Quick Install

On your Raspberry Pi 4 (with Wayland):

```bash
curl -fsSL https://kiosk.hugobox.nl/install.sh | sudo bash
```

## Gamepad Controls

- **Start + Select + A** - Start kiosk (hugobox.nl)
- **Start + Select + B** - Start kiosk (dev.hugobox.nl)
- **Start + Select + X** - Shutdown system
- **Start + Select + Y** - Exit to desktop

## Configuration

Edit `/etc/hugobox/config.env` to customize:

```bash
sudo nano /etc/hugobox/config.env
```

## Management

```bash
# View status
./install.sh status

# Upgrade to latest version
sudo ./install.sh upgrade

# Uninstall
sudo ./install.sh uninstall

# View logs
journalctl -u hugobox-kiosk -f
journalctl -u hugobox-gamepad -f
```

## Requirements

- Raspberry Pi 4 (or compatible)
- Raspberry Pi OS with Wayland
- Internet connection for initial install
- USB gamepad (optional, for gamepad controls)

## Technical Details

- .NET 10 SDK with native C# scripting (single-file scripts with `#:package` support)
- Chromium browser in kiosk mode
- Systemd services for process management
- Wayland display server support

## Development & Deployment

This repository uses GitHub Actions to automatically deploy to GitHub Pages.

### Automatic Deployment

Every push to the `main` branch automatically:
1. Builds the deployment package
2. Publishes to GitHub Pages
3. Makes files available at https://kiosk.hugobox.nl

### Manual Deployment

You can also trigger deployment manually:
1. Go to Actions tab in GitHub
2. Select "Deploy to GitHub Pages"
3. Click "Run workflow"

### GitHub Pages Setup

Ensure GitHub Pages is configured:
1. Go to Settings → Pages
2. Source: GitHub Actions
3. Custom domain: kiosk.hugobox.nl
4. Enforce HTTPS: ✓

