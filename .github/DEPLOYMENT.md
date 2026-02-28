# Deployment Guide

This repository automatically deploys to GitHub Pages using GitHub Actions.

## Automatic Deployment

Every push to the `main` branch triggers automatic deployment:

1. GitHub Actions workflow runs
2. Files are copied to `_site/` directory
3. Landing page (index.html) is generated
4. CNAME file is created for custom domain
5. Everything is deployed to GitHub Pages
6. Available at https://kiosk.hugobox.nl

## Files Published

The following files are made available:

- `install.sh` - Main installation script
- `scripts/` - All shell and C# scripts
- `systemd/` - Systemd service files
- `hugobox.env.example` - Configuration example
- `README.md` - Documentation
- `LICENSE` - License file
- `index.html` - Auto-generated landing page

## GitHub Pages Configuration

Required settings in GitHub repository:

### Pages Settings
1. Go to **Settings** → **Pages**
2. **Source**: GitHub Actions (not Deploy from a branch)
3. **Custom domain**: kiosk.hugobox.nl
4. **Enforce HTTPS**: ✓ Enabled

### DNS Configuration
Your DNS should have:
```
CNAME kiosk.hugobox.nl → lakerfield.github.io
```

Or for apex domain with A records:
```
A @ → 185.199.108.153
A @ → 185.199.109.153
A @ → 185.199.110.153
A @ → 185.199.111.153
```

## Manual Deployment

To manually trigger deployment:

1. Go to **Actions** tab
2. Select **Deploy to GitHub Pages** workflow
3. Click **Run workflow** button
4. Select `main` branch
5. Click **Run workflow**

## Workflow File

The deployment workflow is defined in:
`.github/workflows/deploy-pages.yml`

## Testing Locally

To test the deployment setup locally:

```bash
# Create the site directory
mkdir -p _site

# Copy files
cp install.sh _site/
cp hugobox.env.example _site/
cp -r scripts _site/
cp -r systemd _site/

# Serve locally with Python
cd _site
python3 -m http.server 8000
```

Then visit http://localhost:8000

## Troubleshooting

### Deployment fails
- Check Actions tab for error messages
- Verify GitHub Pages is enabled
- Ensure workflow has proper permissions

### Custom domain not working
- Verify CNAME file exists in deployed site
- Check DNS propagation (can take up to 24 hours)
- Ensure HTTPS is enforced in GitHub Pages settings

### Install script returns 404
- Verify files were deployed (check Actions logs)
- Check file permissions in workflow
- Ensure curl is using correct URL

## Permissions

The workflow requires these permissions:
- `contents: read` - Read repository files
- `pages: write` - Deploy to GitHub Pages
- `id-token: write` - Verify deployment

These are configured in the workflow file.
