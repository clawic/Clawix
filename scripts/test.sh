#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANE="${1:-fast}"
shift || true
SCRATCH_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/clawix-test.XXXXXX")"
COORDINATION_LEASE_ID=""
COORDINATION_LEASE_IDS=""
COORDINATION_HEARTBEAT_PID=""
export CLANG_MODULE_CACHE_PATH="$SCRATCH_ROOT/clang-module-cache"

cleanup() {
  local status=$?
  stop_coordination_heartbeat || true
  release_coordination_lease "$status" || true
  rm -rf "$SCRATCH_ROOT"
}
trap cleanup EXIT

run() {
  echo "+ $*" >&2
  "$@"
}

redact_text() {
  local users_root="/Users"
  sed -E \
    -e "s#${users_root}/[^/[:space:]]+#~#g" \
    -e 's#sk-[A-Za-z0-9._-]{6,}#[REDACTED]#g' \
    -e 's#Bearer[[:space:]]+[A-Za-z0-9._-]{6,}#Bearer [REDACTED]#g'
}

actionable_failure() {
  local status="$1"
  local code="$2"
  local message="$3"
  local location="$4"
  local suggestion="$5"
  local next="$6"
  {
    printf '%s\n' "test lane failed:"
    printf -- '- [%s] %s\n' "$status" "$message"
    printf '  code: %s\n' "$code"
    printf '  location: %s\n' "$location"
    printf '  suggestion: %s\n' "$suggestion"
    printf '  next: %s\n' "$next"
  } | redact_text >&2
}

test_sh_self_test() {
  local output
  local private_path="/Users""/example"
  local secret_token="sk-test-secret-""123456"
  output="$(actionable_failure \
    "SATISFIED" \
    "clawix_test_coordination_satisfied" \
    "test lane fast already has valid matching evidence for ${private_path}/private token: ${secret_token}" \
    "scripts/test.sh:fast" \
    "Reuse the recorded coordinated evidence instead of rerunning the lane." \
    "Inspect the coordination ledger for lane fast, or rerun bash scripts/test.sh fast after evidence expires." 2>&1)"
  [[ "$output" == *"code: clawix_test_coordination_satisfied"* ]]
  [[ "$output" == *"[SATISFIED]"* ]]
  [[ "$output" == *"location: scripts/test.sh:fast"* ]]
  [[ "$output" == *"suggestion: Reuse the recorded coordinated evidence"* ]]
  [[ "$output" == *"next: Inspect the coordination ledger for lane fast"* ]]
  [[ "$output" != *"$private_path"* ]]
  [[ "$output" != *"$secret_token"* ]]
  echo "clawix test launcher self-test passed"
}

coordination_claw() {
  if [[ -n "${CLAWIX_CLAW_BIN:-}" ]]; then
    "$CLAWIX_CLAW_BIN" "$@"
    return
  fi
  if command -v claw >/dev/null 2>&1; then
    claw "$@"
    return
  fi
  if [[ -f "$ROOT_DIR/../clawjs/packages/clawjs/bin/claw.mjs" ]]; then
    node "$ROOT_DIR/../clawjs/packages/clawjs/bin/claw.mjs" "$@"
    return
  fi
  actionable_failure \
    "BLOCKED" \
    "clawix_test_coordination_broker_missing" \
    "coordination broker is unavailable for lane $LANE." \
    "scripts/test.sh:coordination_claw" \
    "Set CLAWIX_CLAW_BIN to the claw CLI or install claw on PATH." \
    "Rerun bash scripts/test.sh $LANE after the coordination broker is available."
  return 127
}

coordination_path_flags() {
  if [[ -n "${CLAW_AGENT_COORDINATION_STATE_DIR:-}" ]]; then
    printf '%s\n' --state-dir "$CLAW_AGENT_COORDINATION_STATE_DIR"
  fi
  if [[ -n "${CLAW_AGENT_COORDINATION_RUN_DIR:-}" ]]; then
    printf '%s\n' --run-dir "$CLAW_AGENT_COORDINATION_RUN_DIR"
  fi
}

json_field() {
  local expression="$1"
  node -e '
let input = "";
process.stdin.on("data", (chunk) => input += chunk);
process.stdin.on("end", () => {
  const data = JSON.parse(input);
  const value = Function("data", `return ${process.argv[1]}`)(data);
  if (value !== undefined && value !== null) process.stdout.write(String(value));
});
' "$expression"
}

record_coordination_bypass() {
  local reason="${CLAW_AGENT_COORDINATION_BYPASS_REASON:-}"
  if [[ -z "$reason" ]]; then
    actionable_failure \
      "USAGE" \
      "clawix_test_coordination_bypass_reason_missing" \
      "CLAW_AGENT_COORDINATION_BYPASS_REASON is required when bypassing coordination." \
      "scripts/test.sh:record_coordination_bypass" \
      "Use bypass only for explicitly marked partial validation." \
      "Set CLAW_AGENT_COORDINATION_BYPASS_REASON to a concrete reason or rerun without bypass."
    exit 2
  fi
  local output status
  set +e
  output="$(coordination_claw agent-resource bypass --intent "clawix-test-bypass-$$" --resource "test-lane:clawix:${LANE}" --reason "$reason" $(coordination_path_flags) --json 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne 2 && "$status" -ne 0 ]]; then
    printf '%s\n' "$output" | redact_text >&2
    exit "$status"
  fi
  echo "WARNING: CLAW_AGENT_COORDINATION_BYPASS=1; this run is partial/degraded evidence." >&2
}

acquire_coordination_lease() {
  if [[ "${CLAW_AGENT_COORDINATION_ACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${CLAW_AGENT_COORDINATION_BYPASS:-0}" == "1" ]]; then
    record_coordination_bypass
    return 0
  fi

  local output status broker_status lease_id lease_ids
  set +e
  output="$(coordination_claw test require --repo "$ROOT_DIR" --lane "$LANE" --checks "$LANE" --pid "$$" $(coordination_path_flags) --json 2>&1)"
  status=$?
  set -e
  broker_status="$(printf '%s' "$output" | json_field 'data.data?.status' 2>/dev/null || true)"
  if [[ "$broker_status" == "SATISFIED" ]]; then
    actionable_failure \
      "SATISFIED" \
      "clawix_test_coordination_satisfied" \
      "test lane $LANE already has valid matching evidence." \
      "scripts/test.sh:$LANE" \
      "Reuse the recorded coordinated evidence instead of rerunning the lane." \
      "Inspect the coordination ledger for lane $LANE, or rerun bash scripts/test.sh $LANE after evidence expires."
    exit 0
  fi
  if [[ "$broker_status" == "PENDING" ]]; then
    printf '%s\n' "$output" | redact_text >&2
    exit 2
  fi
  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$output" | redact_text >&2
    exit "$status"
  fi
  lease_id="$(printf '%s' "$output" | json_field 'data.data?.checks?.[0]?.lease?.id' 2>/dev/null || true)"
  lease_ids="$(printf '%s' "$output" | json_field 'data.data?.checks?.[0]?.leases?.map((lease) => lease.id).join("\n")' 2>/dev/null || true)"
  if [[ -z "$lease_id" ]]; then
    actionable_failure \
      "BLOCKED" \
      "clawix_test_coordination_lease_missing" \
      "coordination broker did not return an acquired lease id for lane $LANE." \
      "scripts/test.sh:acquire_coordination_lease" \
      "Inspect the broker JSON shape and fix the lease projection before trusting this run." \
      "Rerun bash scripts/test.sh $LANE after the broker returns data.data.checks[0].lease.id."
    printf '%s\n' "$output" | redact_text >&2
    exit 2
  fi
  COORDINATION_LEASE_ID="$lease_id"
  COORDINATION_LEASE_IDS="${lease_ids:-$lease_id}"
}

start_coordination_heartbeat() {
  if [[ -z "$COORDINATION_LEASE_IDS" || -n "$COORDINATION_HEARTBEAT_PID" ]]; then
    return 0
  fi
  local parent_pid="$$"
  local interval="${CLAW_AGENT_COORDINATION_HEARTBEAT_SECONDS:-10}"
  (
    while kill -0 "$parent_pid" >/dev/null 2>&1; do
      local lease_id
      while IFS= read -r lease_id; do
        [[ -n "$lease_id" ]] || continue
        coordination_claw agent-resource heartbeat --lease "$lease_id" --status running $(coordination_path_flags) --json >/dev/null 2>&1 || true
      done <<< "$COORDINATION_LEASE_IDS"
      sleep "$interval"
    done
  ) &
  COORDINATION_HEARTBEAT_PID="$!"
}

stop_coordination_heartbeat() {
  if [[ -z "$COORDINATION_HEARTBEAT_PID" ]]; then
    return 0
  fi
  kill "$COORDINATION_HEARTBEAT_PID" >/dev/null 2>&1 || true
  wait "$COORDINATION_HEARTBEAT_PID" >/dev/null 2>&1 || true
  COORDINATION_HEARTBEAT_PID=""
}

release_coordination_lease() {
  local exit_code="$1"
  if [[ -z "$COORDINATION_LEASE_ID" ]]; then
    return 0
  fi
  local status="failed"
  [[ "$exit_code" -eq 0 ]] && status="passed"
  [[ "$exit_code" -eq 2 ]] && status="external_pending"
  local lease_id released_primary=0
  while IFS= read -r lease_id; do
    [[ -n "$lease_id" ]] || continue
    if [[ "$lease_id" == "$COORDINATION_LEASE_ID" && "$released_primary" -eq 0 ]]; then
      coordination_claw agent-resource release --lease "$lease_id" --status "$status" --repo "$ROOT_DIR" --lane "$LANE" --check "$LANE" $(coordination_path_flags) --json >/dev/null
      released_primary=1
    else
      coordination_claw agent-resource release --lease "$lease_id" --status "$status" --repo "$ROOT_DIR" --lane "$LANE" --check "$LANE" --no-result true $(coordination_path_flags) --json >/dev/null
    fi
  done <<< "${COORDINATION_LEASE_IDS:-$COORDINATION_LEASE_ID}"
}

policy_guard() {
  for required in \
    "$ROOT_DIR/docs/adr/0003-testing-architecture.md" \
    "$ROOT_DIR/docs/adr/0005-integration-qa-lab.md" \
    "$ROOT_DIR/docs/adr/0007-dual-human-programmatic-surfaces.md" \
    "$ROOT_DIR/docs/adr/TEMPLATE.md" \
    "$ROOT_DIR/playbooks/testing.md" \
    "$ROOT_DIR/playbooks/testing-matrix.md" \
    "$ROOT_DIR/qa/coverage-budgets.json" \
    "$ROOT_DIR/qa/quarantine.json" \
    "$ROOT_DIR/qa/scenarios/external-pending.md" \
    "$ROOT_DIR/qa/scenarios/signed-host-validation.md" \
    "$ROOT_DIR/qa/scenarios/telegram-integration-qa-lab.md"
  do
    if [[ ! -e "$required" ]]; then
      echo "testing policy failed: missing ${required#$ROOT_DIR/}" >&2
      exit 1
    fi
  done

  for lane_root in fast integration e2e host device fixtures live; do
    if [[ ! -d "$ROOT_DIR/tests/$lane_root" ]]; then
      echo "testing policy failed: missing tests/$lane_root" >&2
      exit 1
    fi
  done

  for ignored in 'test-results/' 'artifacts/' 'coverage/' '.tmp/'; do
    if ! grep -Fqx "$ignored" "$ROOT_DIR/.gitignore"; then
      echo "testing policy failed: .gitignore must include $ignored" >&2
      exit 1
    fi
  done

  node - "$ROOT_DIR/qa/quarantine.json" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const today = new Date().toISOString().slice(0, 10);
const quarantine = JSON.parse(fs.readFileSync(file, "utf8"));
if (!Array.isArray(quarantine.entries)) {
  console.error("testing policy failed: qa/quarantine.json must contain entries");
  process.exit(1);
}
for (const entry of quarantine.entries) {
  for (const field of ["id", "owner", "reason", "repair", "expires"]) {
    if (!entry[field]) {
      console.error(`testing policy failed: quarantine entry is missing ${field}`);
      process.exit(1);
    }
  }
  if (entry.expires < today) {
    console.error(`testing policy failed: quarantine entry ${entry.id} expired on ${entry.expires}`);
    process.exit(1);
  }
  const text = `${entry.id} ${entry.reason} ${entry.repair}`.toLowerCase();
  if (text.includes("localization") && (text.includes("unregistered ui") || text.includes("visible ui") || text.includes("localizable.xcstrings"))) {
    console.error(`testing policy failed: localization completeness cannot be quarantined (${entry.id})`);
    process.exit(1);
  }
}
console.error("testing policy passed");
NODE

  node - "$ROOT_DIR/qa/coverage-budgets.json" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const requiredBoundaries = [
  "swift-logic-packages",
  "web-surface",
  "bridge-protocol",
  "daemon-and-local-bridge",
  "macos-host-app",
  "device-clients",
  "live-integrations",
  "connector-qa-display-approval",
];
const budgets = JSON.parse(fs.readFileSync(file, "utf8"));
if (!Array.isArray(budgets.budgets)) {
  console.error("testing policy failed: qa/coverage-budgets.json must contain budgets");
  process.exit(1);
}
const seen = new Set();
for (const budget of budgets.budgets) {
  for (const field of ["boundary", "lane", "metric", "minimum"]) {
    if (budget[field] === undefined || budget[field] === "") {
      console.error(`testing policy failed: coverage budget is missing ${field}`);
      process.exit(1);
    }
  }
  if (typeof budget.minimum !== "number" || budget.minimum < 0) {
    console.error(`testing policy failed: invalid coverage minimum for ${budget.boundary || "<unknown>"}`);
    process.exit(1);
  }
  seen.add(budget.boundary);
}
for (const boundary of requiredBoundaries) {
  if (!seen.has(boundary)) {
    console.error(`testing policy failed: missing coverage budget boundary ${boundary}`);
    process.exit(1);
  }
}
NODE
}

swift_package_tests() {
  local package
  for package in "$@"; do
    [[ -f "$package/Package.swift" ]] || continue
    [[ -d "$package/Tests" ]] || continue
    run swift test --disable-sandbox --package-path "$package" --scratch-path "$SCRATCH_ROOT/$(basename "$package")"
  done
}

fast_swift_packages() {
  printf '%s\n' \
    "$ROOT_DIR/packages/AIProviders" \
    "$ROOT_DIR/packages/ClawixArgon2" \
    "$ROOT_DIR/packages/ClawixCore" \
    "$ROOT_DIR/packages/SecretsModels" \
    "$ROOT_DIR/packages/SecretsProxyCore"
}

integration_swift_packages() {
  printf '%s\n' \
    "$ROOT_DIR/packages/SecretsCrypto" \
    "$ROOT_DIR/packages/SecretsPersistence" \
    "$ROOT_DIR/packages/SecretsVault" \
    "$ROOT_DIR/packages/ClawixEngine" \
    "$ROOT_DIR/macos"
}

web_tests() {
  if [[ -d "$ROOT_DIR/web/node_modules" ]]; then
    run npm --prefix "$ROOT_DIR/web" test -- "$@"
  else
    echo "PARTIAL web tests skipped: web/node_modules is not installed" >&2
  fi
}

android_unit_tests() {
  if [[ "${CLAWIX_SKIP_ANDROID_UNIT_TESTS:-0}" == "1" ]]; then
    echo "PARTIAL Android unit tests skipped: CLAWIX_SKIP_ANDROID_UNIT_TESTS=1" >&2
    return 0
  fi
  if [[ -x "$ROOT_DIR/android/gradlew" ]]; then
    run "$ROOT_DIR/android/gradlew" -p "$ROOT_DIR/android" testDebugUnitTest
  else
    echo "PARTIAL Android unit tests skipped: Gradle wrapper is not executable" >&2
  fi
}

bridge_fixture_tests() {
  run python3 "$ROOT_DIR/macos/scripts/compile_xcstrings.py"
  run bash "$ROOT_DIR/macos/scripts/e2e_validate.sh"
}

e2e_tests() {
  bridge_fixture_tests
}

strict_external_pending() {
  [[ "${CLAWIX_TEST_STRICT_EXTERNAL_PENDING:-0}" == "1" ]]
}

run_external_command() {
  local lane="$1"
  local command="$2"
  local output_file="$SCRATCH_ROOT/${lane}-external-command.log"
  set +e
  bash -lc "$command" > >(tee "$output_file") 2> >(tee -a "$output_file" >&2)
  local status=$?
  set -e

  if strict_external_pending && grep -q "EXTERNAL PENDING" "$output_file"; then
    echo "FAIL: strict release $lane lane blocked because command output contains EXTERNAL PENDING" >&2
    return 1
  fi
  if [[ "$status" -eq 2 ]]; then
    if strict_external_pending; then
      echo "FAIL: strict release $lane lane blocked because command exited with EXTERNAL PENDING status 2" >&2
      return 1
    fi
    echo "EXTERNAL PENDING $lane lane: command exited with status 2" >&2
    return 0
  fi
  return "$status"
}

signed_host_preflight() {
  local launcher="${CLAWIX_APP_PREFLIGHT_SCRIPT:-}"
  if [[ ! -x "$launcher" ]]; then
    echo "EXTERNAL PENDING host lane: app preflight script is unavailable for signed-host preflight" >&2
    return 2
  fi
  run bash "$launcher" preflight-computer-use
}

host_tests() {
  local status=0
  if [[ -n "${CLAWIX_HOST_TEST_COMMAND:-}" ]]; then
    if signed_host_preflight; then
      run_external_command host "$CLAWIX_HOST_TEST_COMMAND" || status=$?
    else
      local preflight_status=$?
      if [[ "$preflight_status" -eq 2 ]]; then
        if strict_external_pending; then
          echo "FAIL: strict release host lane blocked without private signed-host preflight" >&2
          status=1
        fi
      else
        echo "FAIL: signed-host preflight failed before host validation" >&2
        status=1
      fi
    fi
  else
    echo "EXTERNAL PENDING host lane: set CLAWIX_HOST_TEST_COMMAND for signed-host validation" >&2
    if strict_external_pending; then
      echo "FAIL: strict release host lane blocked without signed-host validation command" >&2
      status=1
    fi
  fi
  if [[ -n "${CLAWIX_LAUNCH_DEPENDENCY_EVIDENCE:-}" ]]; then
    run node "$ROOT_DIR/scripts/startup_release_contract_check.mjs" --require-launch-evidence || status=$?
  else
    echo "EXTERNAL PENDING host lane: set CLAWIX_LAUNCH_DEPENDENCY_EVIDENCE for launch dependency budget validation" >&2
    if strict_external_pending; then
      echo "FAIL: strict release host lane blocked without launch dependency evidence" >&2
      status=1
    fi
  fi
  return "$status"
}

core_ux_tests() {
  local status=0
  run node "$ROOT_DIR/scripts/core_ux_reliability_check.mjs" || status=$?
  if [[ "${CLAWIX_CORE_UX_REQUIRE_APPROVED:-0}" == "1" ]]; then
    run node "$ROOT_DIR/scripts/core_ux_reliability_check.mjs" --require-approved || status=$?
  fi

  if [[ -n "${CLAWIX_CORE_UX_GATE_COMMAND:-}" ]]; then
    run_external_command core-ux "$CLAWIX_CORE_UX_GATE_COMMAND" || status=$?
  else
    echo "EXTERNAL PENDING core-ux lane: set CLAWIX_CORE_UX_GATE_COMMAND for approved macOS real-app Core UX validation" >&2
    if strict_external_pending || [[ "${CLAWIX_CORE_UX_STRICT:-0}" == "1" ]]; then
      echo "FAIL: strict core-ux lane blocked without Core UX gate command" >&2
      status=1
    fi
  fi
  return "$status"
}

device_tests() {
  android_unit_tests
  if [[ -n "${CLAWIX_DEVICE_TEST_COMMAND:-}" ]]; then
    run_external_command device "$CLAWIX_DEVICE_TEST_COMMAND"
  else
    echo "EXTERNAL PENDING device lane: set CLAWIX_DEVICE_TEST_COMMAND for simulator/device validation" >&2
    if strict_external_pending; then
      echo "FAIL: strict release device lane blocked without simulator/device validation command" >&2
      return 1
    fi
  fi
}

live_tests() {
  if [[ "${CLAWIX_TEST_LIVE:-}" != "1" ]]; then
    echo "CLAWIX_TEST_LIVE=1 is required for the live lane." >&2
    exit 2
  fi
  if [[ -n "${CLAWIX_LIVE_TEST_COMMAND:-}" ]]; then
    run bash -lc "$CLAWIX_LIVE_TEST_COMMAND"
  else
    echo "EXTERNAL PENDING live lane: set CLAWIX_LIVE_TEST_COMMAND for approved live validation" >&2
  fi
}

fast() {
  run bash "$ROOT_DIR/macos/scripts/public_hygiene_check.sh"
  run node "$ROOT_DIR/scripts/tracked-ignored-check.mjs"
  run node "$ROOT_DIR/scripts/check-clawjs-skills-sync.mjs"
  run node "$ROOT_DIR/scripts/agent-instructions-check.mjs"
  run node "$ROOT_DIR/scripts/constitution-assertions-check.mjs"
  run node "$ROOT_DIR/scripts/constitution-assertions-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/constitution-sync-check.mjs"
  run node "$ROOT_DIR/scripts/constitution-sync-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/accessibility_governance_guard.mjs"
  run node "$ROOT_DIR/scripts/accessibility_governance_guard.mjs" --self-test
  run node "$ROOT_DIR/scripts/evolution_rescue_mirror_check.mjs"
  run node "$ROOT_DIR/scripts/legal_safety_check.mjs"
  run node "$ROOT_DIR/scripts/interface_surface_guard.mjs"
  run node "$ROOT_DIR/scripts/platform_feature_parity_check.mjs"
  run node "$ROOT_DIR/scripts/platform_feature_parity_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/goal_completion_gate_check.mjs"
  run node "$ROOT_DIR/scripts/goal_completion_gate_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/attachment_lifecycle_matrix_check.mjs"
  run node "$ROOT_DIR/scripts/release_external_pending_gate.mjs" --self-test
  run node "$ROOT_DIR/scripts/release_readiness_check.mjs"
  run node "$ROOT_DIR/scripts/release_readiness_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/debt_control_baseline_check.mjs"
  run node "$ROOT_DIR/scripts/debt_control_baseline_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/supply_chain_security_check.mjs"
  run node "$ROOT_DIR/scripts/supply_chain_security_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/security-threat-model-check.mjs"
  run node "$ROOT_DIR/scripts/security-threat-model-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/incident_response_check.mjs"
  run node "$ROOT_DIR/scripts/incident_response_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/performance_governance_check.mjs"
  run node "$ROOT_DIR/scripts/performance_governance_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/core_ux_reliability_check.mjs"
  run node "$ROOT_DIR/scripts/core_ux_reliability_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/hot_path_guard.mjs"
  run node "$ROOT_DIR/scripts/hot_path_guard.mjs" --self-test
  run node "$ROOT_DIR/scripts/boundedness_guard.mjs"
  run node "$ROOT_DIR/scripts/boundedness_guard.mjs" --self-test
  run node "$ROOT_DIR/scripts/actionable-error.mjs" --self-test
  run node "$ROOT_DIR/scripts/bridge_contract_parity_check.mjs"
  run node "$ROOT_DIR/scripts/idle_quiescence_check.mjs"
  run node "$ROOT_DIR/scripts/idle_quiescence_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/problem_to_guardrail_check.mjs"
  run node "$ROOT_DIR/scripts/problem_to_guardrail_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/no-irreversible-data-loss-check.mjs"
  run node "$ROOT_DIR/scripts/no-irreversible-data-loss-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/adoption_canonicity_check.mjs"
  run node "$ROOT_DIR/scripts/adoption_canonicity_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/portable_archive_mirror_check.mjs"
  run node "$ROOT_DIR/scripts/startup_release_contract_check.mjs"
  run node "$ROOT_DIR/scripts/zero_accidental_work_check.mjs"
  run node "$ROOT_DIR/scripts/zero_accidental_work_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/open_source_canonicity_check.mjs"
  run node "$ROOT_DIR/scripts/open_source_canonicity_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/discoverability-check.mjs"
  run node "$ROOT_DIR/scripts/discoverability-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/generate-surface-route-registry.mjs" --self-test
  run node "$ROOT_DIR/scripts/generate-surface-route-registry.mjs" --check
  run node "$ROOT_DIR/scripts/adr-operational-coverage-check.mjs"
  run node "$ROOT_DIR/scripts/adr-operational-coverage-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/localization_surface_guard.mjs" --self-test
  run python3 "$ROOT_DIR/macos/scripts/compile_xcstrings.py"
  run node "$ROOT_DIR/scripts/localization_surface_guard.mjs" macos
  run node "$ROOT_DIR/scripts/cross_platform_localization_guard.mjs" --self-test
  run node "$ROOT_DIR/scripts/cross_platform_localization_guard.mjs"
  run node "$ROOT_DIR/scripts/persistent-surface-guard.mjs" --self-test
  run node "$ROOT_DIR/scripts/persistent-surface-guard.mjs" macos ios android windows web/src linux/app/src
  run node "$ROOT_DIR/scripts/surface-evidence-projection-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/surface-evidence-projection-check.mjs"
  run node "$ROOT_DIR/scripts/surface_narrative_guard.mjs" --self-test
  run node "$ROOT_DIR/scripts/surface_narrative_guard.mjs"
  run node "$ROOT_DIR/scripts/surface_resource_contract_guard.mjs" --self-test
  run node "$ROOT_DIR/scripts/surface_resource_contract_guard.mjs"
  run node "$ROOT_DIR/scripts/native_permission_broker_check.mjs"
  run node "$ROOT_DIR/scripts/native_action_broker_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/native_action_broker_check.mjs"
  run node "$ROOT_DIR/scripts/verify-sdk-first-custom-surfaces-goal.mjs"
  run node "$ROOT_DIR/scripts/verify-system-telemetry-goal.mjs"
  run node "$ROOT_DIR/scripts/clawjs_mirror_contradiction_check.mjs"
  run node "$ROOT_DIR/scripts/clawjs_mirror_contradiction_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/remote_canon_alignment_check.mjs"
  run node "$ROOT_DIR/scripts/mesh_route_classification_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/mesh_route_classification_check.mjs"
  run node "$ROOT_DIR/scripts/remote_route_port_boundary_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/remote_route_port_boundary_check.mjs" --strict
  run node "$ROOT_DIR/scripts/ui_governance_guard.mjs"
  run node "$ROOT_DIR/scripts/ui_canon_docs_check.mjs"
  run node "$ROOT_DIR/scripts/ui_canon_promotion_check.mjs"
  run node "$ROOT_DIR/scripts/ui_decision_verification_check.mjs"
  run node "$ROOT_DIR/scripts/ui_debt_report_check.mjs"
  run node "$ROOT_DIR/scripts/ui_debt_audit_manifest_check.mjs"
  run node "$ROOT_DIR/scripts/ui_critical_cleanup_queue_check.mjs"
  run node "$ROOT_DIR/scripts/ui_exception_check.mjs"
  run node "$ROOT_DIR/scripts/ui_inspiration_reference_check.mjs"
  run node "$ROOT_DIR/scripts/ui_protected_surface_check.mjs"
  run node "$ROOT_DIR/scripts/ui_approval_authority_check.mjs"
  run node "$ROOT_DIR/scripts/ui_canon_unit_check.mjs"
  run node "$ROOT_DIR/scripts/ui_geometry_contract_check.mjs"
  run node "$ROOT_DIR/scripts/ui_completion_audit_check.mjs"
  run node "$ROOT_DIR/scripts/ui_completion_source_manifest_check.mjs"
  run node "$ROOT_DIR/scripts/ui_completion_gate_check.mjs"
  run node "$ROOT_DIR/scripts/ui_state_invalidation_boundary_check.mjs"
  run node "$ROOT_DIR/scripts/markdown_render_heavy_check.mjs" --self-test
  run node "$ROOT_DIR/scripts/ui_implementation_evidence_check.mjs"
  run node "$ROOT_DIR/scripts/ui_implementation_phase_check.mjs"
  run node "$ROOT_DIR/scripts/ui_skill_contract_check.mjs"
  run node "$ROOT_DIR/scripts/ui_state_coverage_check.mjs"
  run node "$ROOT_DIR/scripts/ui_surface_reference_check.mjs"
  run node "$ROOT_DIR/scripts/ui_surface_baseline_coverage_check.mjs"
  run node "$ROOT_DIR/scripts/ui_rendered_drift_check.mjs"
  run node "$ROOT_DIR/scripts/ui_release_gate_check.mjs"
  run node "$ROOT_DIR/scripts/ui_rendered_geometry_manifest_check.mjs"
  run node "$ROOT_DIR/scripts/ui_copy_governance_check.mjs"
  run node "$ROOT_DIR/scripts/conceptual-vocabulary-guard.mjs"
  run node "$ROOT_DIR/scripts/ui_performance_budget_check.mjs"
  run node "$ROOT_DIR/scripts/ui_pattern_performance_check.mjs"
  run node "$ROOT_DIR/scripts/ui_pattern_mutation_guard.mjs"
  run node "$ROOT_DIR/scripts/ui_component_extraction_check.mjs"
  run node "$ROOT_DIR/scripts/ui_mechanical_equivalence_check.mjs"
  run node "$ROOT_DIR/scripts/ui_visual_scope_check.mjs"
  run node "$ROOT_DIR/scripts/ui_visual_detector_check.mjs"
  run node "$ROOT_DIR/scripts/ui_visual_model_allowlist_check.mjs"
  run node "$ROOT_DIR/scripts/ui_visual_guard_failure_check.mjs"
  run node "$ROOT_DIR/scripts/ui_visual_proposal_check.mjs"
  run node "$ROOT_DIR/scripts/ui_private_artifact_boundary_check.mjs"
  run node "$ROOT_DIR/scripts/ui_surface_inventory_check.mjs"
  run node "$ROOT_DIR/scripts/ui_private_baseline_manifest_check.mjs"
  run node "$ROOT_DIR/scripts/ui_private_evidence_plan_check.mjs"
  run node "$ROOT_DIR/scripts/ui_private_capture_runner_check.mjs"
  run node "$ROOT_DIR/scripts/ui_private_review_bundle_check.mjs"
  run node "$ROOT_DIR/scripts/ui_private_visual_validation_manifest_check.mjs"
  run node "$ROOT_DIR/scripts/naming-shape-check.mjs"
  run node "$ROOT_DIR/scripts/source-size-check.mjs"
  run node "$ROOT_DIR/scripts/code-hygiene-check.mjs"
  run node "$ROOT_DIR/scripts/code-hygiene-check.mjs" --self-test
  run node "$ROOT_DIR/scripts/code-hygiene-audit.mjs" --self-test
  run node "$ROOT_DIR/scripts/code-hygiene-knip.mjs" --self-test
  run node "$ROOT_DIR/scripts/code-hygiene-periphery.mjs" --self-test
  run node "$ROOT_DIR/scripts/codebase-manifest.mjs" --check
  run node "$ROOT_DIR/scripts/package_surface_guard.mjs"
  policy_guard
  packages=()
  while IFS= read -r package; do
    packages+=("$package")
  done < <(fast_swift_packages)
  swift_package_tests "${packages[@]}"
  web_tests "$@"
}

integration() {
  fast "$@"
  run python3 "$ROOT_DIR/macos/scripts/compile_xcstrings.py"
  packages=()
  while IFS= read -r package; do
    packages+=("$package")
  done < <(integration_swift_packages)
  swift_package_tests "${packages[@]}"
}

changed() {
  local base
  base="$(git -C "$ROOT_DIR" merge-base HEAD origin/main 2>/dev/null || true)"
  [[ -n "$base" ]] || base="HEAD~1"

  local changed_files
  changed_files="$(git -C "$ROOT_DIR" diff --name-only "$base" -- 2>/dev/null || true)"
  if [[ -z "$changed_files" ]]; then
    fast "$@"
    return
  fi

  if grep -Eq '^(macos/Helpers|macos/scripts/e2e_|packages/(SecretsCrypto|SecretsPersistence|SecretsVault|ClawixEngine)|macos/)' <<< "$changed_files"; then
    integration "$@"
    return
  fi

  fast "$@"
}

if [[ "$LANE" == "--self-test" ]]; then
  test_sh_self_test
  exit 0
fi

acquire_coordination_lease
start_coordination_heartbeat

case "$LANE" in
  fast)
    fast "$@"
    ;;
  changed)
    changed "$@"
    ;;
  integration)
    integration "$@"
    ;;
  e2e)
    e2e_tests
    ;;
  host)
    host_tests
    ;;
  core-ux)
    core_ux_tests
    ;;
  device)
    device_tests
    ;;
  live)
    live_tests
    ;;
  release)
    run node "$ROOT_DIR/scripts/release_readiness_check.mjs" --target "${CLAWIX_RELEASE_TARGET:-macos-release}" --phase preflight --run
    run node "$ROOT_DIR/scripts/idle_quiescence_check.mjs"
    integration "$@"
    e2e_tests
    CLAWIX_TEST_STRICT_EXTERNAL_PENDING=1 device_tests
    CLAWIX_TEST_STRICT_EXTERNAL_PENDING=1 host_tests
    CLAWIX_TEST_STRICT_EXTERNAL_PENDING=1 CLAWIX_CORE_UX_REQUIRE_APPROVED=1 core_ux_tests
    ;;
  *)
    actionable_failure \
      "USAGE" \
      "clawix_test_lane_unknown" \
      "Unknown test lane: $LANE" \
      "scripts/test.sh" \
      "Use one of: fast, changed, integration, e2e, host, core-ux, device, live, release." \
      "Rerun bash scripts/test.sh with a known lane name."
    exit 2
    ;;
esac
