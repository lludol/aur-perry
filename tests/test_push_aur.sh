#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/.github/scripts/push-aur.sh"
workflow="$repo_root/.github/workflows/aur.yml"
workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

grep -Fq 'bash .github/scripts/push-aur.sh "${{ steps.tag.outputs.tag }}"' "$workflow" || \
  fail 'workflow must delegate the AUR push to the tested helper'

run_with_mock_git() {
  local scenario=$1
  local mock_bin="$workspace/mock-$scenario"
  local run_dir="$workspace/run-$scenario"
  mkdir -p "$mock_bin" "$run_dir/perry"
  printf 'pkgbuild\n' > "$run_dir/perry/PKGBUILD"
  printf 'srcinfo\n' > "$run_dir/perry/.SRCINFO"
  printf 'license\n' > "$run_dir/LICENSE"

  cat > "$mock_bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "$MOCK_GIT_LOG"
printf '\n' >> "$MOCK_GIT_LOG"
if [[ "${1:-}" == clone ]]; then
  case "$MOCK_GIT_SCENARIO" in
    maintenance)
      printf '%s\n' 'The AUR is down due to maintenance. We will be back soon.' >&2
      exit 128
      ;;
    failure)
      printf '%s\n' 'network transport error' >&2
      exit 128
      ;;
    success)
      mkdir -p "${@: -1}"
      exit 0
      ;;
  esac
fi
exit 0
MOCK
  chmod +x "$mock_bin/git"

  cat > "$mock_bin/ssh-keyscan" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' 'aur.archlinux.org ssh-ed25519 test-host-key'
MOCK
  chmod +x "$mock_bin/ssh-keyscan"

  set +e
  PATH="$mock_bin:$PATH" \
  MOCK_GIT_LOG="$run_dir/git.log" \
  MOCK_GIT_SCENARIO="$scenario" \
  GITHUB_WORKSPACE="$run_dir" \
  AUR_SSH_KEY='test-key' \
  bash "$script" 0.5.1220 >"$run_dir/out" 2>"$run_dir/err"
  RUN_STATUS=$?
  set -e
  RUN_DIR="$run_dir"
}

run_with_mock_git maintenance
[[ "$RUN_STATUS" -eq 0 ]] || fail 'maintenance must be skipped successfully'
grep -Fq 'AUR maintenance detected; skipping AUR push.' "$RUN_DIR/out" || fail 'maintenance skip was not reported'
! grep -Fq 'git add' "$RUN_DIR/git.log" || fail 'must not commit after a maintenance failure'

run_with_mock_git failure
[[ "$RUN_STATUS" -eq 128 ]] || fail 'unexpected clone errors must fail the workflow'
grep -Fq 'network transport error' "$RUN_DIR/out" || fail 'unexpected clone error must be shown'

echo 'PASS: AUR clone failures are handled safely'
