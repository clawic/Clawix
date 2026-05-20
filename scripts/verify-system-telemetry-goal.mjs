#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const errors = [];

function fail(message) {
  errors.push(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(relativePath) {
  return JSON.parse(read(relativePath));
}

function requireSnippet(relativePath, snippet) {
  const text = read(relativePath);
  assert(text.includes(snippet), `${relativePath}: missing ${JSON.stringify(snippet)}`);
}

function collectTextFiles(relativePaths) {
  const allowedExtensions = new Set([".swift", ".md", ".mjs", ".js", ".ts", ".tsx", ".json", ".sh", ".yml", ".yaml"]);
  const ignoredDirectories = new Set([".git", ".build", "build", "DerivedData", "node_modules", "dist", ".tmp", ".swiftpm", "xcuserdata"]);
  const files = [];
  function walk(absolutePath) {
    if (!fs.existsSync(absolutePath)) return;
    const stat = fs.statSync(absolutePath);
    if (stat.isDirectory()) {
      if (ignoredDirectories.has(path.basename(absolutePath))) return;
      for (const entry of fs.readdirSync(absolutePath)) {
        walk(path.join(absolutePath, entry));
      }
      return;
    }
    if (stat.isFile() && allowedExtensions.has(path.extname(absolutePath))) {
      files.push(path.relative(rootDir, absolutePath));
    }
  }
  for (const relativePath of relativePaths) {
    walk(path.join(rootDir, relativePath));
  }
  return [...new Set(files)].sort();
}

function containsForbiddenExternalProductName(text, term) {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^a-z0-9])${escaped}([^a-z0-9]|$)`, "i").test(text);
}

function run(command, commandArgs, options = {}) {
  try {
    return execFileSync(command, commandArgs, {
      cwd: options.cwd ?? rootDir,
      env: { ...process.env, ...(options.env ?? {}) },
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: options.timeout ?? 120_000,
    });
  } catch (error) {
    fail(`${command} ${commandArgs.join(" ")} failed: ${error.stderr || error.message}`);
    return "";
  }
}

function resolveClawCliForSeeding() {
  if (process.env.CLAWIX_SYSTEM_TELEMETRY_SEED_COMMAND) {
    return process.env.CLAWIX_SYSTEM_TELEMETRY_SEED_COMMAND.trim().split(/\s+/);
  }
  const siblingCli = path.resolve(rootDir, "..", "..", "clawjs", "packages", "clawjs", "bin", "claw.mjs");
  if (fs.existsSync(siblingCli)) return [process.execPath, siblingCli];
  return ["claw"];
}

function appTelemetryEnvironment() {
  const supportRoot = path.join(os.homedir(), "Library", "Application Support", "Clawix", "clawjs");
  return {
    HOME: path.join(supportRoot, "home"),
    CLAW_WORKSPACE: path.join(supportRoot, "workspace"),
    CLAW_HOME: path.join(os.homedir(), ".claw"),
    CLAW_DATA_DIR: supportRoot,
    CLAW_DB_PATH: path.join(supportRoot, "clawix.sqlite"),
    CLAW_FILES_DIR: path.join(supportRoot, "files"),
  };
}

function appMonitorDatabasePath() {
  return path.join(os.homedir(), "Library", "Application Support", "Clawix", "clawjs", "monitor.sqlite");
}

function readAppMonitorMetricStats() {
  const dbPath = appMonitorDatabasePath();
  if (!fs.existsSync(dbPath)) return { count: 0, maxCapturedAt: 0 };
  try {
    const output = execFileSync("sqlite3", [
      "-separator",
      "\t",
      dbPath,
      "SELECT COUNT(*), COALESCE(MAX(captured_at), 0) FROM metric_samples;",
    ], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: 10_000,
    }).trim();
    const [count, maxCapturedAt] = output.split("\t").map((value) => Number(value));
    return {
      count: Number.isFinite(count) ? count : 0,
      maxCapturedAt: Number.isFinite(maxCapturedAt) ? maxCapturedAt : 0,
    };
  } catch {
    return { count: 0, maxCapturedAt: 0 };
  }
}

function clickCombinedMenuRefresh() {
  const refreshScript = `
set deadlineDate to (current date) + 12
tell application "System Events"
  tell process "Clawix"
    repeat while (current date) < deadlineDate
      set targetItem to missing value
      repeat with barIndex from 1 to (count of menu bars)
        repeat with candidate in menu bar items of menu bar barIndex
          try
            set candidateTitle to title of candidate as text
            if candidateTitle starts with "System" then
              set targetItem to candidate
              exit repeat
            end if
          end try
        end repeat
        if targetItem is not missing value then exit repeat
      end repeat
      if targetItem is not missing value then
        click targetItem
        delay 0.3
        click menu item "Refresh" of menu 1 of targetItem
        return
      end if
      delay 0.5
    end repeat
    error "missing system telemetry combined status item"
  end tell
end tell
`;
  run("osascript", ["-e", refreshScript], { cwd: rootDir, timeout: 30_000 });
}

function seedLocalMonitorHistory() {
  if (!args.has("--seed-local-history")) return;
  const command = resolveClawCliForSeeding();
  const [executable, ...prefixArgs] = command;
  const env = appTelemetryEnvironment();
  fs.mkdirSync(env.HOME, { recursive: true });
  fs.mkdirSync(env.CLAW_WORKSPACE, { recursive: true });
  fs.mkdirSync(env.CLAW_FILES_DIR, { recursive: true });
  for (let index = 0; index < 2; index += 1) {
    run(executable, [...prefixArgs, "system", "snapshot", "--record", "true", "--json"], {
      cwd: env.CLAW_WORKSPACE,
      env,
      timeout: 60_000,
    });
    if (index === 0) {
      run("sleep", ["1"], { timeout: 5_000 });
    }
  }
}

function assertNoForbiddenPublicNames() {
  const forbidden = [
    [105, 115, 116, 97, 116],
    [98, 106, 97, 110, 103, 111],
  ].map((chars) => String.fromCharCode(...chars).toLowerCase());
  const scanned = collectTextFiles([
    "docs",
    "macos/Sources/Clawix/SystemTelemetry",
    "macos/Tests/ClawixMeshTests/SystemTelemetryBridgeTests.swift",
    "macos/scripts/dev.sh",
    "macos/scripts/build_release_app.sh",
    "docs/system-telemetry-external-pending-validation.md",
    "scripts/verify-system-telemetry-goal.mjs",
  ]);
  for (const file of scanned) {
    const text = read(file).toLowerCase();
    for (const term of forbidden) {
      if (containsForbiddenExternalProductName(text, term)) fail(`${file}: contains a forbidden external product name`);
    }
  }
}

function assertExternalPendingLedger() {
  const text = read("docs/system-telemetry-external-pending-validation.md");
  for (const snippet of [
    "Source conversation: `019e359b-c0ab-7dc1-ba94-11a49d11dc76`",
    "Plan item: `019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan`",
    "Status: `active_goal_not_complete`",
    "`EXTERNAL PENDING` are not passes and must not be used to close the goal.",
    "`docs/system-telemetry-external-validation.manifest.json` and",
    "`docs/system-telemetry-source-qa-review.json`",
    "The source Q/A review binds the private decision audit to public-safe rows",
    "| CLX-SYS-TEL-EXT-001 | Strict native menu-bar visual validation |",
    "| CLX-SYS-TEL-EXT-002 | Live host telemetry recording through the app |",
    "| CLX-SYS-TEL-EXT-003 | Physical sensor and fan readings surfaced in the UI |",
    "| CLX-SYS-TEL-EXT-004 | Live external context provider displayed in menu-bar widgets |",
    "| CLX-SYS-TEL-EXT-005 | Dangerous controls reachable from UI only through governed plans |",
    "| CLX-SYS-TEL-EXT-006 | Native rendered graph view over retained telemetry |",
    "read-only experimental AppleSMC path",
    "missing AppleSMC service or missing compatible keys remains a valid external blocker",
    "fixture/offline context provider samples",
    "redacted location tags",
    "Framework CLI plans append redacted JSONL evidence locally",
    "Framework CLI and signed-host provider plans record redacted JSONL audit evidence",
    "provided_redacted",
    "provider `auditPlan` redaction metadata",
    "portable `auditPlan` redaction metadata",
    "redacted JSONL audit evidence for blocked signed-sensor provider plans",
    "not a provider execution receipt",
    "redacted JSONL audit evidence for unsupported/high-risk blocked controls",
    "not an execution receipt",
    "## External Validation Lanes",
    "| CLX-SYS-TEL-EXT-003 | Signed sensor provider lane:",
    "| CLX-SYS-TEL-EXT-004 | Live context provider lane:",
    "| CLX-SYS-TEL-EXT-005 | Dangerous-control lane:",
    "Rows must stay `EXTERNAL PENDING` if any approval, hardware/provider path,",
    "must not be downgraded to `EXTERNAL PENDING`",
  ]) {
    assert(text.includes(snippet), `docs/system-telemetry-external-pending-validation.md: missing ${JSON.stringify(snippet)}`);
  }

  const requiredRows = [
    "CLX-SYS-TEL-EXT-003",
    "CLX-SYS-TEL-EXT-004",
    "CLX-SYS-TEL-EXT-005",
  ];
  for (const rowId of requiredRows) {
    const rowPattern = new RegExp(`\\|\\s*${rowId}\\s*\\|[^\\n]*\\|\\s*EXTERNAL PENDING\\s*\\|`);
    assert(rowPattern.test(text), `docs/system-telemetry-external-pending-validation.md: ${rowId} must remain EXTERNAL PENDING`);
  }

  const validatedRows = [
    "CLX-SYS-TEL-EXT-001",
    "CLX-SYS-TEL-EXT-002",
    "CLX-SYS-TEL-EXT-006",
  ];
  for (const rowId of validatedRows) {
    const rowPattern = new RegExp(`\\|\\s*${rowId}\\s*\\|[^\\n]*\\|\\s*VALIDATED LOCAL\\s*\\|`);
    assert(rowPattern.test(text), `docs/system-telemetry-external-pending-validation.md: ${rowId} must remain VALIDATED LOCAL`);
  }
}

function assertExternalValidationManifest() {
  const manifest = readJson("docs/system-telemetry-external-validation.manifest.json");
  assert(manifest.schemaVersion === 1, "external validation manifest: schemaVersion must be 1");
  assert(manifest.id === "clawix-system-telemetry-external-validation-manifest", "external validation manifest: wrong id");
  assert(manifest.conversationId === "019e359b-c0ab-7dc1-ba94-11a49d11dc76", "external validation manifest: wrong conversationId");
  assert(manifest.planId === "019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan", "external validation manifest: wrong planId");
  assert(manifest.status === "active_goal_not_complete", "external validation manifest: goal must remain active");
  assert(manifest.completionPolicy?.externalPendingBlocksCompletion === true, "external validation manifest: external pending must block completion");
  assert(manifest.completionPolicy?.requiresFinalSourceAudit === true, "external validation manifest: final source audit must be required");
  assert(manifest.completionPolicy?.requiresSourceQaReview === true, "external validation manifest: source Q/A review must be required");
  assert(manifest.completionPolicy?.requiresForbiddenNameScan === true, "external validation manifest: forbidden-name scan must be required");
  assert(manifest.completionPolicy?.requiresExactRunApprovalForExternalLanes === true, "external validation manifest: exact-run approval must be required");
  assert(manifest.sourceQaReview?.required === true, "external validation manifest: source Q/A review link must be required");
  assert(manifest.sourceQaReview?.artifactId === "clawix-system-telemetry-source-qa-review", "external validation manifest: wrong source Q/A artifact");
  assert(manifest.sourceQaReview?.path === "docs/system-telemetry-source-qa-review.json", "external validation manifest: wrong source Q/A path");
  assert(manifest.sourceQaReview?.privateAuditAlias === "private-goal-audit:claw-system-telemetry-context-menubar-source-audit-2026-05-20", "external validation manifest: wrong private audit alias");
  assert(manifest.sourceQaReview?.closureRole?.includes("public-safe validation rows"), "external validation manifest: source Q/A closure role must be explicit");
  assert(Array.isArray(manifest.rows), "external validation manifest: rows must be an array");

  const rows = new Map(manifest.rows.map((row) => [row.id, row]));
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    const row = rows.get(rowId);
    assert(row?.status === "EXTERNAL PENDING", `external validation manifest: ${rowId} must remain EXTERNAL PENDING`);
    assert(Array.isArray(row.blockingPrerequisites) && row.blockingPrerequisites.length >= 4, `external validation manifest: ${rowId} must keep blocking prerequisites`);
    assert(Array.isArray(row.acceptedEvidence) && row.acceptedEvidence.length >= 4, `external validation manifest: ${rowId} must define accepted evidence`);
    assert(typeof row.reentryCommand === "string" && row.reentryCommand.includes("claw system"), `external validation manifest: ${rowId} must define a system reentry command`);
  }

  assert(rows.get("CLX-SYS-TEL-EXT-003")?.acceptedEvidence?.includes("app_or_menu_same_machine_evidence"), "external validation manifest: sensor UI lane must require same-machine app/menu evidence");
  assert(rows.get("CLX-SYS-TEL-EXT-004")?.acceptedEvidence?.includes("provider_execution_receipt"), "external validation manifest: live provider lane must require execution receipt");
  assert(rows.get("CLX-SYS-TEL-EXT-004")?.blockingPrerequisites?.includes("network_access_for_exact_run"), "external validation manifest: live provider lane must require exact network approval");
  assert(rows.get("CLX-SYS-TEL-EXT-005")?.blockingPrerequisites?.includes("physical_validation"), "external validation manifest: control lane must require physical validation");
  assert(rows.get("CLX-SYS-TEL-EXT-005")?.acceptedEvidence?.includes("rollback_or_continuity_evidence"), "external validation manifest: control lane must require rollback or continuity evidence");

  for (const rowId of ["CLX-SYS-TEL-EXT-001", "CLX-SYS-TEL-EXT-002", "CLX-SYS-TEL-EXT-006"]) {
    const row = rows.get(rowId);
    assert(row?.status === "VALIDATED LOCAL", `external validation manifest: ${rowId} must remain VALIDATED LOCAL`);
    assert(Array.isArray(row.blockingPrerequisites) && row.blockingPrerequisites.length === 0, `external validation manifest: ${rowId} must not keep external prerequisites`);
  }
}

function assertSourceQaReview() {
  const review = readJson("docs/system-telemetry-source-qa-review.json");
  assert(review.schemaVersion === 1, "source Q/A review: schemaVersion must be 1");
  assert(review.artifactId === "clawix-system-telemetry-source-qa-review", "source Q/A review: wrong artifactId");
  assert(review.discoveryTerms?.includes("system telemetry source Q/A review"), "source Q/A review: missing discovery term");
  assert(review.sourceConversationId === "019e359b-c0ab-7dc1-ba94-11a49d11dc76", "source Q/A review: wrong sourceConversationId");
  assert(review.sourcePlanId === "019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan", "source Q/A review: wrong sourcePlanId");
  assert(review.sourceSessionRef === "private-session-not-published", "source Q/A review: must not publish private source session path");
  assert(!JSON.stringify(review).includes("/Users/"), "source Q/A review: must not publish private filesystem paths");
  assert(review.status === "complete_with_external_pending", "source Q/A review: status must keep external blockers visible");
  assert(review.reviewedUserRoleMessages === 102, "source Q/A review: reviewed user-role message count drifted");
  assert(review.decisionBearingRowsReviewed === 10, "source Q/A review: decision-bearing row count drifted");
  for (const decisionId of ["D01", "D02", "D03", "D04", "D05", "D06", "D07", "D08", "D09", "D10", "D11"]) {
    assert(review.decisionIdsReviewed?.includes(decisionId), `source Q/A review: missing ${decisionId}`);
  }
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(review.externalPendingRows?.includes(rowId), `source Q/A review: missing external-pending ${rowId}`);
  }
  for (const rowId of ["CLX-SYS-TEL-EXT-001", "CLX-SYS-TEL-EXT-002", "CLX-SYS-TEL-EXT-006"]) {
    assert(review.validatedLocalRows?.includes(rowId), `source Q/A review: missing validated-local ${rowId}`);
  }
  assert(Array.isArray(review.rows) && review.rows.length === 10, "source Q/A review: must contain exactly 10 reviewed source rows");
  const rows = new Map(review.rows.map((row) => [row.qaId, row]));
  for (const [qaId, sourceRow, sourceLine] of [
    ["CLX-STQA-001", "USER_002", 6],
    ["CLX-STQA-002", "USER_004", 55],
    ["CLX-STQA-003", "USER_005", 325],
    ["CLX-STQA-004", "USER_006", 450],
    ["CLX-STQA-005", "USER_007", 462],
    ["CLX-STQA-006", "USER_008", 514],
    ["CLX-STQA-007", "USER_009", 657],
    ["CLX-STQA-008", "USER_017", 3584],
    ["CLX-STQA-009", "USER_049", 11030],
    ["CLX-STQA-010", "USER_102", 21355],
  ]) {
    const row = rows.get(qaId);
    assert(row?.sourceRow === sourceRow, `source Q/A review: ${qaId} must map to ${sourceRow}`);
    assert(row?.sourceLine === sourceLine, `source Q/A review: ${qaId} source line drifted`);
    assert(Array.isArray(row?.evidenceRefs) && row.evidenceRefs.length > 0, `source Q/A review: ${qaId} must cite evidence`);
  }
  assert(rows.get("CLX-STQA-003")?.disposition === "implemented_with_external_pending", "source Q/A review: main plan row must preserve external-pending disposition");
  assert(rows.get("CLX-STQA-006")?.disposition === "active_closure_gate", "source Q/A review: goal creation row must stay an active closure gate");
  assert(review.completionPolicy?.requiresFinalSourceSessionReread === true, "source Q/A review: final source reread must be required");
  assert(review.completionPolicy?.requiresOneByOneDecisionReview === true, "source Q/A review: one-by-one decision review must be required");
  assert(review.completionPolicy?.requiresForbiddenNameScan === true, "source Q/A review: forbidden-name scan must be required");
  assert(review.completionPolicy?.externalPendingBlocksCompletion === true, "source Q/A review: external pending must block completion");
}

function assertDecisionMatrix() {
  const text = read("docs/system-telemetry-decision-matrix.md");
  for (const snippet of [
    "Source conversation: `019e359b-c0ab-7dc1-ba94-11a49d11dc76`",
    "Plan item: `019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan`",
    "Status: `active_goal_not_complete`",
    "source session path is intentionally not published here.",
    "| D01 | Provide a first-class framework plane",
    "| D02 | Cover computer hardware with a Mac-first portable contract",
    "Bluetooth/peripheral aggregate counts",
    "| D03 | Keep weather/time as useful context",
    "| D04 | Support multiple independent menu-bar indicators",
    "| D05 | Support a combined menu-bar widget/panel",
    "| D06 | Allow broad indicator variability",
    "| D07 | Prepare host and app surfaces for real-time display",
    "| D08 | Reuse and centralize retention, charts, rules, and events in Monitor",
    "metric purge fallback to rollups",
    "operational `health_check` events stay in Monitor",
    "| D09 | Do not mention third-party monitoring product names",
    "| D10 | Pin the goal to the conversation id, plan id, source review",
    "| D11 | Do not close the goal until everything is implemented",
    "docs/system-telemetry-external-validation.manifest.json",
    "external validation manifest",
    "docs/system-telemetry-source-qa-review.json",
    "source Q/A review",
    "`CLX-SYS-TEL-EXT-003`, `CLX-SYS-TEL-EXT-004`, or",
    "`CLX-SYS-TEL-EXT-005` remain `EXTERNAL PENDING` in the ledger or structured",
    "external-validation manifest",
    "reflected in `docs/system-telemetry-source-qa-review.json`",
    "The forbidden-name scan has not been repeated",
  ]) {
    assert(text.includes(snippet), `docs/system-telemetry-decision-matrix.md: missing ${JSON.stringify(snippet)}`);
  }
  const decisionRows = text.match(/^\| D\d{2} \|/gm) ?? [];
  assert(decisionRows.length === 11, "docs/system-telemetry-decision-matrix.md: must contain exactly D01-D11 decision rows");
  assert(!text.includes("/Users/"), "docs/system-telemetry-decision-matrix.md: must not publish private filesystem paths");

  const decisionMap = read("docs/decision-map.md");
  for (const snippet of [
    "System telemetry, context widgets, Monitor-backed history, and menu-bar indicators",
    "docs/system-telemetry-decision-matrix.md",
    "docs/system-telemetry-external-pending-validation.md",
    "docs/system-telemetry-external-validation.manifest.json",
    "docs/system-telemetry-source-qa-review.json",
    "node scripts/verify-system-telemetry-goal.mjs",
  ]) {
    assert(decisionMap.includes(snippet), `docs/decision-map.md: missing ${JSON.stringify(snippet)}`);
  }

  const registry = read("docs/discoverability.registry.json");
  for (const snippet of [
    "\"id\": \"clawix-system-telemetry-decision-matrix\"",
    "\"canonicalSource\": \"docs/system-telemetry-decision-matrix.md\"",
    "\"query\": \"system telemetry decision matrix\"",
    "\"id\": \"clawix-system-telemetry-external-pending-ledger\"",
    "\"canonicalSource\": \"docs/system-telemetry-external-pending-validation.md\"",
    "\"query\": \"system telemetry external pending validation\"",
    "\"id\": \"clawix-system-telemetry-external-validation-manifest\"",
    "\"canonicalSource\": \"docs/system-telemetry-external-validation.manifest.json\"",
    "\"query\": \"system telemetry external validation manifest\"",
    "\"id\": \"clawix-system-telemetry-source-qa-review\"",
    "\"canonicalSource\": \"docs/system-telemetry-source-qa-review.json\"",
    "\"query\": \"system telemetry source Q/A review\"",
  ]) {
    assert(registry.includes(snippet), `docs/discoverability.registry.json: missing ${JSON.stringify(snippet)}`);
  }

  const router = read("docs/discoverability.md");
  for (const snippet of [
    "`clawix-system-telemetry-decision-matrix`",
    "[docs/system-telemetry-decision-matrix.md](/system-telemetry-decision-matrix)",
    "`clawix-system-telemetry-external-pending-ledger`",
    "[docs/system-telemetry-external-pending-validation.md](/system-telemetry-external-pending-validation)",
    "`clawix-system-telemetry-external-validation-manifest`",
    "[docs/system-telemetry-external-validation.manifest.json](/system-telemetry-external-validation.manifest.json)",
    "`clawix-system-telemetry-source-qa-review`",
    "[docs/system-telemetry-source-qa-review.json](/system-telemetry-source-qa-review.json)",
  ]) {
    assert(router.includes(snippet), `docs/discoverability.md: missing ${JSON.stringify(snippet)}`);
  }

  for (const snippet of [
    "requiresExactRunApprovalForExternalLanes",
    "same_machine_evidence",
    "physical_validation",
  ]) {
    requireSnippet("docs/system-telemetry-external-validation.manifest.json", snippet);
  }
}

function assertBridgeContracts() {
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "struct SystemTelemetrySample");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "struct SystemTelemetryHistoryChart");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func history(metricKey: String, range: String = \"1h\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "static func decodeHistory(");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "struct SystemTelemetryProviderPlan");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "struct SystemTelemetryProviderAdapterContract");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "var adapterContract: SystemTelemetryProviderAdapterContract?");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "private static func decodeProviderAdapterContract");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "metrics: stringArray(from: output[\"metrics\"])");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "struct SystemTelemetryPlanAuditProjection");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "var auditPlan: SystemTelemetryPlanAuditProjection?");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "private static func decodeAuditPlan");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "credentialRefRedacted: bool(from: redaction[\"credential_ref_redacted\"]) ?? bool(from: redaction[\"credentialRefRedacted\"]) ?? false");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "targetRedacted: bool(from: redaction[\"target_redacted\"]) ?? bool(from: redaction[\"targetRedacted\"]) ?? false");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "private static func redactedCredentialRef(from request: [String: Any]) -> String?");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "return \"provided_redacted\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func providerPlan(");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func controlPlan(");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "metricKeys: stringArray(from: object[\"metric_keys\"]) ?? stringArray(from: object[\"metricKeys\"]) ?? stringArray(from: object[\"metrics\"]) ?? []");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "widgets = enabledWidgets.filter");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "panelWidgets = enabledWidgets.filter");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "providers = await nextProviders");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "histories = await nextHistories");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func sparkline(for metricKey: String");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func historyGraph(for widget: SystemTelemetryWidget) -> SystemTelemetryHistory?");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func hasHistoryGraph(for widget: SystemTelemetryWidget) -> Bool");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "widget.renderMode == \"sparkline\" || widget.renderMode == \"chart\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let ticks = Array(\"▁▂▃▄▅▆▇█\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func combinedPanelTitle() -> String");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func providerStatusRows(limit: Int = 5) -> [String]");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift", "final class SystemTelemetryHistoryReader");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift", "\"history\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift", "\"--range\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift", "CommanderCore.JSONValue.from(any: payload)");
  requireSnippet("macos/scripts/bundle_clawjs.sh", "packages/clawjs-search");
}

function assertStatusItemAndRecorder() {
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func makeCombinedPanelItem() -> NSStatusItem");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func makeCombinedPanelMenu(model: SystemTelemetryMenuBarModel, title: String) -> NSMenu");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addProviderItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addWidgetConfigurationItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel) -> Bool");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addPanelItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel, currentWidgetID: String)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private let historyReader = SystemTelemetryHistoryReader()");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "case (\"history\", \"get\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "historyReader.historyPayload");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addHistoryGraphItems(");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "NSMenuItem(title: \"\\(widget.title) history graph\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "SystemTelemetryHistoryGraphView(history: history, title: widget.title)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "let refresh = NSMenuItem(title: \"Refresh\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryGraphView.swift", "final class SystemTelemetryHistoryGraphView: NSView");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryGraphView.swift", "setAccessibilityLabel(\"\\(title) history graph\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryGraphView.swift", "history.chart.points");

  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "final class SystemTelemetryMonitorRecorder");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"system\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"snapshot\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"--source\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"host\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"--record\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "reason: \"minimum_interval\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "reason: \"host_command_unavailable\"");
  requireSnippet("macos/scripts/dev.sh", "Building claw-host for system telemetry");
  requireSnippet("macos/scripts/dev.sh", "$BUNDLE/Contents/MacOS/claw-host");
  requireSnippet("macos/scripts/build_release_app.sh", "Building claw-host (release)");
  requireSnippet("macos/scripts/build_release_app.sh", "$BUNDLE_DIR/Contents/MacOS/claw-host");
}

function assertSwiftTestCoverage() {
  const testFile = "macos/Tests/ClawixMeshTests/SystemTelemetryBridgeTests.swift";
  for (const snippet of [
    "testDecodesSnapshotPolicySamplesAndUnavailableMetrics",
    "testDecodesHistoryChartPayload",
    "testHistoryReaderRunsClawSystemHistoryCommand",
    "\"24h\"",
    "testDecodesPortableCliSnapshotPayload",
    "system.peripheral.bluetooth_count",
    "testDecodesPortableCliWidgetListPayload",
    "testDecodesControlCatalogAndPlanPayloads",
    "testDecodesProviderCatalogAndPlanPayloads",
    "XCTAssertEqual(providers[0].adapterContract?.output.metrics, [\"context.weather.temperature\"])",
    "testControlPlanBridgeSendsPlanOnlyRequestArguments",
    "testProviderPlanBridgeSendsPlanOnlyRequestArguments",
    "XCTAssertEqual(plan.provider.adapterContract?.output.metrics, [\"context.weather.temperature\"])",
    "XCTAssertEqual(plan.credentialRef, \"provided_redacted\")",
    "XCTAssertEqual(plan.auditPlan?.redaction.credentialRefRedacted, true)",
    "XCTAssertEqual(plan.auditPlan?.redaction.targetRedacted, true)",
    "testMenuBarModelLoadsProviderStatusRows",
    "testMenuBarConfigurationTogglesFromDefaultWidgetCatalog",
    "testMenuBarModelIncludesPortableBothPlacement",
    "testMenuBarModelRendersStringSamplesForTextWidgets",
    "testMenuBarModelRendersSparklineFromHistoryChart",
    "SystemTelemetryHistoryGraphView",
    "CPU history graph",
    "testMenuBarModelLoadsHistoryGraphForChartWidgets",
    "testHistoryGraphViewRendersNativeBitmap",
    "Hardware Overview",
    "testMonitorRecorderRecordsHostSnapshotThroughClawCLI",
    "minimum_interval",
    "testMonitorRecorderReportsUnavailableWithoutHostCommand",
    "system.sensor.fan_speed",
    "context.weather.temperature",
    "metricKeys\": .string(\"[REDACTED]\")",
  ]) {
    requireSnippet(testFile, snippet);
  }
}

function assertOptionalPreflight() {
  if (!args.has("--preflight")) return;
  const launcher = path.resolve(rootDir, "..", "scripts-dev", "clawix-launcher.sh");
  if (!fs.existsSync(launcher)) {
    fail("--preflight requested but private launcher is unavailable");
    return;
  }
  const output = run("bash", [launcher, "preflight-computer-use"], { cwd: path.dirname(rootDir), timeout: 60_000 });
  assert(output.includes("PREFLIGHT OK"), "preflight: expected PREFLIGHT OK");
}

function assertOptionalSwiftTests() {
  if (!args.has("--swift-test")) return;
  const scratch = process.env.CLAWIX_SYSTEM_TELEMETRY_SCRATCH
    || "/tmp/clawix-system-telemetry-goal-build";
  fs.mkdirSync(scratch, { recursive: true });
  run("swift", [
    "test",
    "--package-path",
    path.join(rootDir, "macos"),
    "--scratch-path",
    scratch,
    "--filter",
    "SystemTelemetryBridgeTests",
  ], { timeout: 600_000 });
}

function assertOptionalAccessibilitySmoke() {
  if (!args.has("--accessibility-smoke")) return;
  if (args.has("--seed-local-history")) {
    run("sleep", ["4"], { timeout: 10_000 });
  }
  const titlesScript = `
tell application "System Events"
  tell process "Clawix"
    set itemTitles to {}
    repeat with barIndex from 1 to (count of menu bars)
      repeat with candidate in menu bar items of menu bar barIndex
        try
          set end of itemTitles to (title of candidate as text)
        on error
          set end of itemTitles to ""
        end try
      end repeat
    end repeat
    set AppleScript's text item delimiters to linefeed
    return itemTitles as text
  end tell
end tell
`;
  const titlesOutput = run("osascript", ["-e", titlesScript], { cwd: rootDir, timeout: 30_000 });
  const titles = titlesOutput.split(/\r?\n/).map((title) => title.trim()).filter(Boolean);
  const appMenuTitles = new Set(["Apple", "Clawix", "File", "Edit", "View", "Window", "Help"]);
  const statusTitles = titles.filter((title) => !appMenuTitles.has(title) && title !== "missing value");
  const independentIndicatorTitles = statusTitles.filter((title) => !title.startsWith("System"));
  assert(independentIndicatorTitles.length >= 2, `accessibility smoke: expected at least 2 independent status indicators, got ${independentIndicatorTitles.length}: ${JSON.stringify(statusTitles)}`);
  assert(statusTitles.some((title) => title.startsWith("System")), "accessibility smoke: missing combined System status item");

  const menuScript = `
tell application "System Events"
  tell process "Clawix"
    set targetItem to missing value
    repeat with barIndex from 1 to (count of menu bars)
      repeat with candidate in menu bar items of menu bar barIndex
        try
          set candidateTitle to title of candidate as text
          if candidateTitle starts with "System" then
            set targetItem to candidate
            exit repeat
          end if
        end try
      end repeat
      if targetItem is not missing value then exit repeat
    end repeat
    if targetItem is missing value then error "missing system telemetry combined status item"
    click targetItem
    delay 0.3
    set itemNames to {}
    repeat with menuItem in menu items of menu 1 of targetItem
      try
        set end of itemNames to (name of menuItem as text)
      on error
        set end of itemNames to ""
      end try
    end repeat
    key code 53
    return itemNames as text
  end tell
end tell
`;
  const menuOutput = run("osascript", ["-e", menuScript], { cwd: rootDir, timeout: 30_000 });
  for (const snippet of [
    "System indicators",
    "Providers",
    "Menu bar indicators",
    "Refresh",
    "Mock weather context: Ready",
    "Live weather context: External Pending",
    "Signed hardware sensor provider: External Pending",
    "CPU + Memory",
    "Disk + Network",
    "Hardware Overview",
    "Weather",
    "Build",
    "Services",
    "Agents",
    "Reminders",
    "Calendar",
    "Notifications",
    "Context",
  ]) {
    assert(menuOutput.includes(snippet), `accessibility smoke: menu missing ${JSON.stringify(snippet)}`);
  }
  if (args.has("--seed-local-history")) {
    assert(menuOutput.includes("history graph"), "accessibility smoke: seeded history graph menu item missing");
  }
}

function assertOptionalLiveRecorderSmoke() {
  if (!args.has("--live-recorder-smoke")) return;

  const before = readAppMonitorMetricStats();
  clickCombinedMenuRefresh();
  run("sleep", ["6"], { timeout: 10_000 });
  let after = readAppMonitorMetricStats();

  if (after.count <= before.count) {
    run("sleep", ["65"], { timeout: 70_000 });
    clickCombinedMenuRefresh();
    run("sleep", ["6"], { timeout: 10_000 });
    after = readAppMonitorMetricStats();
  }

  assert(after.count > before.count, `live recorder smoke: expected metric_samples to increase after menu Refresh (${before.count} -> ${after.count})`);
  assert(after.maxCapturedAt > before.maxCapturedAt, `live recorder smoke: expected captured_at to advance after menu Refresh (${before.maxCapturedAt} -> ${after.maxCapturedAt})`);
}

function main() {
  seedLocalMonitorHistory();
  assertNoForbiddenPublicNames();
  assertExternalPendingLedger();
  assertExternalValidationManifest();
  assertSourceQaReview();
  assertDecisionMatrix();
  assertBridgeContracts();
  assertStatusItemAndRecorder();
  assertSwiftTestCoverage();
  assertOptionalPreflight();
  assertOptionalSwiftTests();
  assertOptionalAccessibilitySmoke();
  assertOptionalLiveRecorderSmoke();

  if (errors.length) {
    console.error(`Clawix system telemetry goal verifier failed with ${errors.length} issue(s):`);
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.log("Clawix system telemetry goal verifier passed.");
}

main();
