# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HugoBox Kiosk is a Raspberry Pi kiosk system with gamepad control. It consists of:
- An installation script that deploys to Raspberry Pi devices via `curl | bash`
- A .NET 10 C# gamepad daemon for system control
- A Chromium kiosk launcher for Wayland
- Systemd service configurations
- GitHub Pages deployment for hosting installation files

**Target Platform**: Raspberry Pi 4 with Wayland (Raspberry Pi OS)

## Architecture

### Installation Flow
```
User runs: curl -fsSL https://kiosk.hugobox.nl/install.sh | sudo bash
    ↓
install.sh downloads all files from GitHub Pages
    ↓
Installs .NET 10 SDK + dotnet-script globally
    ↓
Sets up systemd services (gamepad daemon + chromium kiosk)
    ↓
Services auto-start on boot
```

### Runtime Architecture
```
[hugobox-gamepad.service] (root)
    → scripts/gamepad-daemon.sh
        → dotnet-script scripts/gamepad-daemon.cs
            → Listens to /dev/input/js0
            → Executes systemctl commands on button combos

[hugobox-kiosk.service] (user: pi)
    → scripts/kiosk-start.sh
        → Starts chromium in kiosk mode on Wayland
```

### Key Components

**install.sh**
- Idempotent installation script (safe to re-run for upgrades)
- Installs .NET 10 SDK via Microsoft's official dotnet-install.sh
- Downloads files from kiosk.hugobox.nl
- Restores NuGet packages with `dotnet restore`
- Configures systemd services
- Uses `/opt/hugobox` for binaries, `/etc/hugobox` for config

**scripts/gamepad-daemon.cs**
- Single C# script file with shebang (`#!/usr/bin/env -S dotnet run`)
- Uses native .NET 10 scripting (no dotnet-script tool needed)
- Companion gamepad-daemon.csproj for NuGet package dependencies
- Reads gamepad input via nahueltaibo/gamepad NuGet package (v1.1.0)
- Button combos (Start+Select+A/B/X) trigger systemctl commands
- Runs as root to execute system commands
- Environment variables: `GP_DEVICE`, `CHROMIUM_UNIT`, `COMBO_HOLD_MS`
- Can be run directly: `dotnet run gamepad-daemon.cs` or `./gamepad-daemon.cs`

**scripts/kiosk-start.sh**
- Waits for Wayland display to be ready
- Launches Chromium with kiosk flags and Wayland-specific options
- Runs as user 'pi' (not root)
- Sources `/etc/hugobox/config.env` for configuration

**systemd/*.service**
- Services are installed to `/etc/systemd/system/`
- Both services use `EnvironmentFile=/etc/hugobox/config.env`
- Gamepad service runs as root (needs systemctl access)
- Kiosk service runs as pi (needs Wayland session access)

## Development Workflow

### Testing Locally
Since this is a deployment system for Raspberry Pi, local testing is limited:

```bash
# Syntax check the install script
bash -n install.sh

# Test script execution logic (won't install on non-Linux)
sudo bash -x install.sh status

# Validate systemd units
systemd-analyze verify systemd/*.service
```

### Testing on Raspberry Pi

```bash
# Install from local files (for development)
sudo ./install.sh install

# Check service status
./install.sh status

# View logs
journalctl -u hugobox-kiosk -f
journalctl -u hugobox-gamepad -f

# Manually test gamepad daemon
cd scripts
dotnet run gamepad-daemon.cs
# Or make it executable and run directly:
./gamepad-daemon.cs

# Manually test kiosk launcher
sudo -u pi scripts/kiosk-start.sh

# After modifying gamepad-daemon.cs, just run it:
cd scripts
dotnet run gamepad-daemon.cs
```

### Deployment

Files are automatically deployed to GitHub Pages on push to `main`:

```bash
git add .
git commit -m "Description"
git push origin main
# GitHub Actions deploys to kiosk.hugobox.nl
```

Manual deployment trigger:
- Go to Actions → "Deploy to GitHub Pages" → Run workflow

See `.github/DEPLOYMENT.md` for full deployment documentation.

## Configuration

**hugobox.env.example** → installed as `/etc/hugobox/config.env`

Key variables:
- `HUGOBOX_URL` - Target URL for kiosk browser
- `HUGOBOX_CHROMIUM_FLAGS` - Browser launch flags
- `GP_DEVICE` - Gamepad input device path
- `CHROMIUM_UNIT` - Systemd unit name for gamepad to control

## File Locations (on deployed system)

```
/opt/hugobox/              - Installation directory
  scripts/
    gamepad-daemon.cs      - Executable C# script with shebang
    gamepad-daemon.csproj  - Project file for NuGet dependencies
    gamepad-daemon.sh      - Service wrapper
    kiosk-start.sh         - Kiosk launcher
    bin/                   - .NET build cache (auto-generated)
    obj/                   - .NET build cache (auto-generated)
  systemd/                 - Service unit templates
  hugobox.env.example      - Config template

/etc/hugobox/
  config.env               - Active configuration

/etc/systemd/system/
  hugobox-kiosk.service    - Chromium kiosk service
  hugobox-gamepad.service  - Gamepad daemon service
```

## Important Notes

### Gamepad Button Mappings
Button numbers are controller-specific. Current mappings (Xbox-style controller):
- Button 0 = A
- Button 1 = X
- Button 2 = B
- Button 6 = Select/Back
- Button 7 = Start

Different controllers may use different button numbers. Test with actual hardware.

### .NET 10 Native Scripting
The gamepad daemon uses .NET 10's native scripting capabilities:
- Single gamepad-daemon.cs file with shebang: `#!/usr/bin/env -S dotnet run`
- Companion gamepad-daemon.csproj in same directory for PackageReference
- Top-level statements (no Main method or class needed)
- Can be run with `dotnet run gamepad-daemon.cs` or `./gamepad-daemon.cs`
- No need for dotnet-script tool - pure .NET 10 SDK
- NuGet packages restored during installation with `dotnet restore`

### Wayland-Specific Behavior
- Chromium requires `--enable-features=UseOzonePlatform --ozone-platform=wayland`
- Service must wait for `graphical.target` and Wayland socket
- XDG_RUNTIME_DIR and WAYLAND_DISPLAY must be set correctly
- User running Chromium must have access to Wayland session (typically 'pi')

### Idempotent Installation
The install.sh script:
- Detects if .NET 10 is already installed
- Preserves existing `/etc/hugobox/config.env`
- Stops services before updating files
- Can be safely re-run to upgrade to latest version

### Chromium User Account
The kiosk service runs as user `pi` by default. If your Raspberry Pi uses a different username:
- Edit `systemd/hugobox-kiosk.service`
- Change `User=pi` to your username
- Redeploy or manually update the service file

## GitHub Pages Deployment

The `.github/workflows/deploy-pages.yml` workflow:
1. Copies all installation files to `_site/`
2. Generates an HTML landing page
3. Creates CNAME file for custom domain
4. Deploys to GitHub Pages

Published URLs:
- Landing page: https://kiosk.hugobox.nl
- Install script: https://kiosk.hugobox.nl/install.sh
- All scripts/configs available at https://kiosk.hugobox.nl/scripts/ etc.
