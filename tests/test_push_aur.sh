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
if [[ "${1:-}" == clone || "${1:-}" == push ]]; then
  printf '%s\t%s\n' "$1" "${GIT_SSH_COMMAND:-}" >> "$MOCK_SSH_LOG"
fi
if [[ "${1:-}" == clone ]]; then
  case "$MOCK_GIT_SCENARIO" in
    maintenance)
      printf '%s\n' 'The AUR is down due to maintenance. We will be back soon.' >&2
      exit 128
      ;;
    clone_failure)
      printf '%s\n' 'network transport error' >&2
      exit 128
      ;;
    changed|no_change|push_failure)
      mkdir -p "${@: -1}"
      exit 0
      ;;
  esac
fi
if [[ "${1:-}" == diff ]]; then
  [[ "$MOCK_GIT_SCENARIO" == no_change ]] && exit 0
  exit 1
fi
if [[ "${1:-}" == push && "$MOCK_GIT_SCENARIO" == push_failure ]]; then
  printf '%s\n' 'unrelated push transport error' >&2
  exit 42
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
  MOCK_SSH_LOG="$run_dir/ssh.log" \
  MOCK_GIT_SCENARIO="$scenario" \
  GITHUB_WORKSPACE="$run_dir" \
  AUR_SSH_KEY='test-key' \
  bash "$script" 0.5.1220 >"$run_dir/out" 2>"$run_dir/err"
  RUN_STATUS=$?
  set -e
  RUN_DIR="$run_dir"
}

assert_transport_is_shared_and_strict() {
  local clone_ssh push_ssh
  clone_ssh=$(awk -F '\t' '$1 == "clone" { print $2 }' "$RUN_DIR/ssh.log")
  push_ssh=$(awk -F '\t' '$1 == "push" { print $2 }' "$RUN_DIR/ssh.log")

  [[ -n "$clone_ssh" ]] || fail 'clone must receive GIT_SSH_COMMAND'
  [[ "$push_ssh" == "$clone_ssh" ]] || fail 'push must receive the same GIT_SSH_COMMAND as clone'
  [[ "$clone_ssh" == *'-o IdentitiesOnly=yes'* ]] || fail 'SSH transport must restrict identities'
  [[ "$clone_ssh" == *'-o UserKnownHostsFile='* ]] || fail 'SSH transport must use the temporary known_hosts file'
  [[ "$clone_ssh" == *'-o StrictHostKeyChecking=yes'* ]] || fail 'strict host verification must remain enabled'
}

assert_temporary_credentials_removed() {
  local clone_ssh key_file known_hosts
  clone_ssh=$(awk -F '\t' '$1 == "clone" { print $2 }' "$RUN_DIR/ssh.log")
  key_file=${clone_ssh#* -i }
  key_file=${key_file%% *}
  known_hosts=${clone_ssh#*UserKnownHostsFile=}
  known_hosts=${known_hosts%% *}

  [[ ! -e "$key_file" ]] || fail 'temporary SSH private key must be removed'
  [[ ! -e "$known_hosts" ]] || fail 'temporary known_hosts file must be removed'
  [[ ! -d "${key_file%/id_rsa}" ]] || fail 'temporary credential directory must be removed'
}

run_with_mock_git maintenance
[[ "$RUN_STATUS" -eq 0 ]] || fail 'maintenance must be skipped successfully'
grep -Fq 'AUR maintenance detected; skipping AUR push.' "$RUN_DIR/out" || fail 'maintenance skip was not reported'
! grep -Eq '^add ' "$RUN_DIR/git.log" || fail 'must not commit after a maintenance failure'
assert_temporary_credentials_removed

run_with_mock_git clone_failure
[[ "$RUN_STATUS" -eq 128 ]] || fail 'unexpected clone errors must fail the workflow'
grep -Fq 'network transport error' "$RUN_DIR/out" || fail 'unexpected clone error must be shown'
assert_temporary_credentials_removed

run_with_mock_git changed
[[ "$RUN_STATUS" -eq 0 ]] || fail 'changed AUR files must push successfully'
grep -Fq 'commit -m chore:\ bump\ to\ 0.5.1220 ' "$RUN_DIR/git.log" || fail 'changed files must be committed'
grep -Eq '^push ' "$RUN_DIR/git.log" || fail 'changed files must be pushed'
assert_transport_is_shared_and_strict
assert_temporary_credentials_removed

run_with_mock_git no_change
[[ "$RUN_STATUS" -eq 0 ]] || fail 'an unchanged AUR checkout must be skipped successfully'
grep -Fq 'No AUR perry changes' "$RUN_DIR/out" || fail 'no-change skip was not reported'
! grep -Eq '^commit ' "$RUN_DIR/git.log" || fail 'no-change run must not commit'
! grep -Eq '^push ' "$RUN_DIR/git.log" || fail 'no-change run must not push'
assert_temporary_credentials_removed

run_with_mock_git push_failure
[[ "$RUN_STATUS" -eq 42 ]] || fail 'an unrelated push failure must propagate'
grep -Fq 'unrelated push transport error' "$RUN_DIR/err" || fail 'push error must be shown'
assert_transport_is_shared_and_strict
assert_temporary_credentials_removed

echo 'PASS: AUR clone and push behavior is handled safely'
