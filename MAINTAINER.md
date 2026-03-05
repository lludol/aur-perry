# Maintainer memo

Notes for updating the AUR package manually or configuring automation.

## GitHub Action

The workflow in `.github/workflows/aur.yml` keeps the PKGBUILD in sync with upstream:

- **Schedule:** runs daily at 03:00 UTC.
- **Manual:** Actions → Auto Update AUR Packages → Run workflow.
- **Test locally (no AUR push):** `act workflow_dispatch`
- Fetches the [latest Perry release](https://github.com/PerryTS/perry/releases/latest), updates `pkgver`, runs `updpkgsums`, regenerates `.SRCINFO`, commits and pushes to this repo, then pushes to the AUR.
- Only commits/pushes when a new version is detected.

## AUR account and SSH key

1. Create an account on [aur.archlinux.org](https://aur.archlinux.org).
2. In [AUR Account Settings](https://aur.archlinux.org/account/) → **SSH Public Key**, add your public key (e.g. `~/.ssh/ed25519.pub`).

## GitHub secrets and variables

In this repo: **Settings → Secrets and variables → Actions**.

### Secret

| Name | Value |
|------|-------|
| `AUR_SSH_KEY` | Your AUR **private** key (full PEM, including `-----BEGIN ... -----` and `-----END ... -----`) |

Without `AUR_SSH_KEY`, the workflow still updates this repo but skips pushing to the AUR.

### Variables (Actions → Variables tab)

| Name | Value |
|------|-------|
| `AUR_USERNAME` | Your AUR username |
| `AUR_EMAIL` | The email tied to your AUR account |

These are used as the git author when pushing to AUR (the AUR requires commits to come from a registered account).

## First push to AUR

The workflow cannot create a new AUR package. You must do the initial push manually:

```bash
git -c init.defaultBranch=master clone ssh://aur@aur.archlinux.org/perry.git /tmp/aur-perry
cp perry/PKGBUILD perry/.SRCINFO LICENSE /tmp/aur-perry/
cd /tmp/aur-perry
git config user.name "your-aur-username"
git config user.email "your-aur-email"
git add PKGBUILD .SRCINFO LICENSE
git commit -m "Initial import: perry 0.2.97"
git push
```

After this, the GitHub Action handles all future updates.

## Manual AUR update

If you need to push to the AUR by hand after the initial import:

```bash
cd perry
# After editing PKGBUILD: updpkgsums && makepkg --printsrcinfo > .SRCINFO
git clone ssh://aur@aur.archlinux.org/perry.git /tmp/aur-perry
cp PKGBUILD .SRCINFO ../LICENSE /tmp/aur-perry/
cd /tmp/aur-perry
git config user.name "your-aur-username"
git config user.email "your-aur-email"
git add PKGBUILD .SRCINFO LICENSE
git commit -m "chore: bump to X.Y.Z"
git push
```
