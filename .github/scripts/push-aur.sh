#!/usr/bin/env bash
set -euo pipefail

pkgver=${1:?usage: push-aur.sh <pkgver>}
repo_root=${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}

if [[ -z "${AUR_SSH_KEY:-}" ]]; then
  echo "AUR_SSH_KEY not set, skipping AUR push"
  exit 0
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
key_file="$workdir/id_rsa"
known_hosts="$workdir/known_hosts"
aur_checkout="$workdir/aur-perry"

umask 077
printf '%s\n' "$AUR_SSH_KEY" > "$key_file"
ssh-keyscan -H aur.archlinux.org > "$known_hosts"
export GIT_SSH_COMMAND="ssh -i $key_file -o IdentitiesOnly=yes -o UserKnownHostsFile=$known_hosts -o StrictHostKeyChecking=yes"

set +e
clone_output=$(git clone --depth 1 ssh://aur@aur.archlinux.org/perry.git "$aur_checkout" 2>&1)
clone_status=$?
set -e
printf '%s\n' "$clone_output"

if [[ "$clone_status" -ne 0 ]]; then
  if grep -Eqi 'AUR is down.*maintenance' <<<"$clone_output"; then
    echo "AUR maintenance detected; skipping AUR push."
    exit 0
  fi
  exit "$clone_status"
fi

cp "$repo_root/perry/PKGBUILD" "$repo_root/perry/.SRCINFO" "$repo_root/LICENSE" "$aur_checkout/"
cd "$aur_checkout"
git config user.name "${AUR_USERNAME:-github-actions[bot]}"
git config user.email "${AUR_EMAIL:-github-actions[bot]@users.noreply.github.com}"
git add PKGBUILD .SRCINFO LICENSE
if git diff --staged --quiet; then
  echo "No AUR perry changes"
  exit 0
fi
git commit -m "chore: bump to $pkgver"
git push
