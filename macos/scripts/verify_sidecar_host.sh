#!/usr/bin/env bash
# Verify that Clawix-owned local sidecars belong to the canonical signed app
# process and do not expose bearer material through process environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
APP="/Applications/Clawix.app"
EXE="$APP/Contents/MacOS/Clawix"
SECRETS_XPC="$APP/Contents/XPCServices/ClawixSecretsXPC.xpc"
SIGNING_POLICY_SCRIPT="${CLAWIX_SIGNING_POLICY_SCRIPT:-}"
APP_PREFLIGHT_SCRIPT="${CLAWIX_APP_PREFLIGHT_SCRIPT:-}"

required_services=(
  "secrets:24103"
)
optional_services=(
  "sessions:24101"
  "database:24102"
  "drive:24104"
  "memory:24105"
  "index:24106"
  "publishing:24111"
  "audio:24151"
)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

external_pending() {
  echo "EXTERNAL PENDING: $*" >&2
  exit 2
}

command_of() {
  ps -p "$1" -o command= 2>/dev/null || true
}

ppid_of() {
  ps -p "$1" -o ppid= 2>/dev/null | tr -d '[:space:]'
}

if [[ -n "${CLAWIX_APP_PATH:-}" && "$CLAWIX_APP_PATH" != "$APP" ]]; then
  fail "CLAWIX_APP_PATH points outside the canonical app; signed-host validation must use $APP"
fi

[[ -d "$APP" ]] || fail "canonical app missing at $APP"
[[ -d "$SECRETS_XPC" ]] || fail "Secrets XPC service missing at $SECRETS_XPC"
[[ -n "$SIGNING_POLICY_SCRIPT" && -f "$SIGNING_POLICY_SCRIPT" ]] || external_pending "signing policy script is unavailable; signed-host validation is not real evidence"
# shellcheck disable=SC1090
source "$SIGNING_POLICY_SCRIPT"
declare -F clawix_assert_signed_app_identity >/dev/null || fail "signing guard cannot assert app identity"
clawix_assert_signed_app_identity "$APP" BUNDLE_ID "canonical Clawix app" || fail "canonical app signing identity is invalid"
clawix_assert_signed_artifact_team "$SECRETS_XPC" || fail "Secrets XPC signing identity is invalid"
[[ -n "$APP_PREFLIGHT_SCRIPT" && -x "$APP_PREFLIGHT_SCRIPT" ]] || external_pending "app preflight script is unavailable; signed-host validation is not real evidence"
bash "$APP_PREFLIGHT_SCRIPT" preflight-computer-use || fail "app preflight failed"

xpc_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SECRETS_XPC/Contents/Info.plist" 2>/dev/null || true)"
app_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ "$xpc_identifier" == "${app_identifier}.secrets-xpc" ]] || fail "Secrets XPC identifier $xpc_identifier does not match app identifier $app_identifier"
allowed_caller="$(/usr/libexec/PlistBuddy -c 'Print :CLXAllowedCallerIdentifier' "$SECRETS_XPC/Contents/Info.plist" 2>/dev/null || true)"
[[ "$allowed_caller" == "$app_identifier" ]] || fail "Secrets XPC allowed caller $allowed_caller does not match app identifier $app_identifier"
echo "PASS secrets-xpc bundle=signed identifier=$xpc_identifier caller=$allowed_caller"

mapfile -t app_pids < <(pgrep -x "Clawix" 2>/dev/null | while read -r pid; do
  [[ -n "$pid" ]] || continue
  cmd="$(command_of "$pid")"
  if [[ "$cmd" == "$EXE" || "$cmd" == "$EXE "* ]]; then
    echo "$pid"
  fi
done)

if [[ "${#app_pids[@]}" -ne 1 ]]; then
  fail "expected exactly one canonical Clawix process, found ${#app_pids[@]}"
fi
app_pid="${app_pids[0]}"
echo "PASS app pid=$app_pid signed=stable"

has_ancestor() {
  local pid="$1"
  local target="$2"
  local depth=0
  while [[ -n "$pid" && "$pid" != "0" && "$depth" -lt 16 ]]; do
    [[ "$pid" == "$target" ]] && return 0
    pid="$(ppid_of "$pid")"
    depth=$((depth + 1))
  done
  return 1
}

verify_service() {
  local entry="$1"
  local required="$2"
  service="${entry%%:*}"
  port="${entry##*:}"
  pid="$(/usr/sbin/lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
  if [[ -z "$pid" ]]; then
    if [[ "$required" == "1" ]]; then
      fail "$service has no listener on 127.0.0.1:$port"
    fi
    echo "SKIP $service port=$port listener=absent"
    return 0
  fi

  cmd="$(command_of "$pid")"
  if [[ "$cmd" != *"$APP/Contents/Resources/clawjs/"* ]]; then
    fail "$service listener pid=$pid is not running from $APP/Contents/Resources/clawjs"
  fi
  if ! has_ancestor "$pid" "$app_pid"; then
    fail "$service listener pid=$pid is not descended from Clawix pid=$app_pid"
  fi

  leaked="$(
    ps eww -p "$pid" 2>/dev/null \
      | tr ' ' '\n' \
      | grep -E 'CLAW_(DATABASE_ADMIN_TOKEN|DRIVE_ADMIN_TOKEN|SEARCH_ADMIN_TOKEN|AUDIO_SHARED_SECRET|SESSIONS_SHARED_SECRET|PUBLISHING_TOKEN|PUBLISHING_TOKEN_STORE|SECRETS_ADMIN_TOKEN|SECRETS_TOKEN|SECRETS_SIGNED_HOST_TOKEN|SECRETS_KEK_BASE64|SECRETS_HOST_ASSERTION_KEY_BASE64)=' \
      || true
  )"
  [[ -z "$leaked" ]] || fail "$service listener pid=$pid exposes token-bearing environment: $leaked"
  echo "PASS $service pid=$pid port=$port ancestor=$app_pid env=no-token"
}

for entry in "${required_services[@]}"; do
  verify_service "$entry" "1"
done

for entry in "${optional_services[@]}"; do
  verify_service "$entry" "0"
done

echo "PASS Clawix sidecar host verification complete"
