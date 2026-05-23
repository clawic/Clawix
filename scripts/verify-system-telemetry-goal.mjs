#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(import.meta.url);
const Ajv2020Module = require("ajv/dist/2020");
const Ajv2020 = Ajv2020Module.default ?? Ajv2020Module;
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

function publicSafetyErrors(value) {
  const serialized = JSON.stringify(value);
  const checks = [
    ["/Users/", "contains private filesystem path"],
    ["file://", "contains file URL"],
    ["secret://", "contains raw secret reference"],
    ["-----BEGIN", "contains key material marker"],
    ["sk-", "contains raw API key marker"],
    ["AKIA", "contains raw access key marker"],
  ];
  return checks
    .filter(([pattern]) => serialized.includes(pattern))
    .map(([, message]) => message);
}

function assertPublicCredentialLeaseRefSchema(schema, label) {
  const definition = schema.$defs?.publicCredentialLeaseRef;
  const patterns = definition?.not?.anyOf?.map((rule) => rule.pattern) ?? [];
  assert(definition?.type === "string", `${label}: publicCredentialLeaseRef must be a string`);
  assert(definition?.minLength === 1, `${label}: publicCredentialLeaseRef must be non-empty`);
  for (const pattern of ["secret://", "file://", "[/\\\\][Uu]sers[/\\\\]", "-----BEGIN", "\\bsk-[A-Za-z0-9_-]+", "\\bAKIA[A-Z0-9]+"]) {
    assert(patterns.includes(pattern), `${label}: publicCredentialLeaseRef must reject ${pattern}`);
  }
  return "#/$defs/publicCredentialLeaseRef";
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

function runClawJson(commandArgs, options = {}) {
  const output = run("claw", commandArgs, options);
  try {
    return JSON.parse(output);
  } catch (error) {
    fail(`claw ${commandArgs.join(" ")} did not return JSON: ${error.message}`);
    return {};
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

const persistentSurfacePathCache = new Map();

function expandPersistentSurfacePath(value) {
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

function persistentSurfaceNodePath(nodeId) {
  if (persistentSurfacePathCache.has(nodeId)) return persistentSurfacePathCache.get(nodeId);
  try {
    const manifest = readJson("docs/persistent-surface-clawix.manifest.json");
    const node = manifest.nodes?.find((entry) => entry.id === nodeId);
    assert(node && typeof node.path === "string", `persistent surface manifest: missing ${nodeId} path`);
    const resolved = node?.path ? expandPersistentSurfacePath(node.path) : path.join(os.tmpdir(), "clawix-missing-persistent-surface", nodeId);
    persistentSurfacePathCache.set(nodeId, resolved);
    return resolved;
  } catch (error) {
    fail(`persistent surface manifest: failed to resolve ${nodeId}: ${error.message}`);
    const unresolved = path.join(os.tmpdir(), "clawix-missing-persistent-surface", nodeId);
    persistentSurfacePathCache.set(nodeId, unresolved);
    return unresolved;
  }
}

function appTelemetrySupportRoot() {
  return persistentSurfaceNodePath("clawix.embeddedRuntimeDistribution");
}

function appTelemetryEnvironment() {
  const supportRoot = appTelemetrySupportRoot();
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
  return path.join(appTelemetrySupportRoot(), "monitor.sqlite");
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

function assertSameStringSet(actual, expected, label) {
  assert(Array.isArray(actual), `${label}: must be an array`);
  if (!Array.isArray(actual)) return;
  const normalizedActual = [...actual].sort();
  const normalizedExpected = [...expected].sort();
  assert(normalizedActual.length === normalizedExpected.length, `${label}: must contain exactly ${normalizedExpected.length} entries`);
  for (let index = 0; index < normalizedExpected.length; index += 1) {
    assert(normalizedActual[index] === normalizedExpected[index], `${label}: expected exact set ${normalizedExpected.join(", ")}`);
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
    "docs/governance/system-telemetry/external-pending.md",
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
  const text = read("docs/governance/system-telemetry/external-pending.md");
  for (const snippet of [
    "Source conversation: `source:system-telemetry`",
    "Plan item: `plan:system-telemetry`",
    "Status: `active_goal_not_complete`",
    "`EXTERNAL PENDING` are not passes and must not be used to close the goal.",
    "`docs/governance/system-telemetry/external-validation.manifest.json` and",
    "`docs/governance/system-telemetry/source-review.json`",
    "status in `docs/governance/system-telemetry/completion.md`",
    "external run steps in",
    "`docs/governance/system-telemetry/external-validation-runbook.md`",
    "`docs/governance/system-telemetry/external-approval.schema.json`",
    "Accepted external",
    "`docs/governance/system-telemetry/external-evidence.schema.json`",
    "`docs/governance/system-telemetry/external-validation.manifest.schema.json`",
    "`docs/governance/system-telemetry/external-validation.manifest.fixtures.json`",
    "accidental completion or lane-clear mutations fail validation",
    "`node scripts/validate-system-telemetry-external-evidence.mjs <packet.json>`",
    "before any row is updated",
    "`node scripts/verify-system-telemetry-goal.mjs --safe-external-preflight-smoke`",
    "that smoke test is local evidence only and does not close any external row",
    "`docs/governance/system-telemetry/external-approval.fixtures.json`",
    "not real approval",
    "`node scripts/validate-system-telemetry-external-approval.mjs <packet.json>`",
    "before any external execution starts",
    "`docs/governance/system-telemetry/external-closure.fixtures.json`",
    "`node scripts/validate-system-telemetry-external-closure.mjs <bundle.json>`",
    "same-lane approval and evidence",
    "public-safe rows, the completion audit binds each goal requirement",
    "runbook binds each remaining external lane to preflight, approval, evidence,",
    "update target, fail-rule, and evidence-packet checks",
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
    "On 2026-05-20, the safe preflight `claw system providers plan system.sensors.signed --json` returned `willConnect=false`, `externalPending=true`",
    "visible sensor metric keys, `receipt.status=not_issued`, and a blocked redacted audit plan",
    "not a provider execution receipt",
    "redacted JSONL audit evidence for unsupported/high-risk blocked controls",
    "On 2026-05-20, the safe preflight `claw system providers plan context.weather.live --json` returned `willConnect=false`, `externalPending=true`",
    "`networkAccess=blocked_until_granted`, `receipt.status=not_issued`, and a blocked redacted audit plan",
    "On 2026-05-20, `claw system controls list --json` exposed governed controls without mutation",
    "the safe preflight `claw system controls plan system.power.sleep --json` returned `willExecute=false`, `externalPending=true`",
    "not an execution receipt",
    "## External Validation Lanes",
    "[System Telemetry External Validation Runbook](./external-validation-runbook.md)",
    "[`docs/governance/system-telemetry/external-evidence.schema.json`](./external-evidence.schema.json)",
    "[`docs/governance/system-telemetry/external-approval.schema.json`](./external-approval.schema.json)",
    "[`docs/governance/system-telemetry/external-approval.fixtures.json`](./external-approval.fixtures.json)",
    "Approval packets are checked with",
    "| CLX-SYS-TEL-EXT-003 | Signed sensor provider lane:",
    "| CLX-SYS-TEL-EXT-004 | Live context provider lane:",
    "| CLX-SYS-TEL-EXT-005 | Dangerous-control lane:",
    "Rows must stay `EXTERNAL PENDING` if any approval, hardware/provider path,",
    "must not be downgraded to `EXTERNAL PENDING`",
  ]) {
    assert(text.includes(snippet), `docs/governance/system-telemetry/external-pending.md: missing ${JSON.stringify(snippet)}`);
  }

  const requiredRows = [
    "CLX-SYS-TEL-EXT-003",
    "CLX-SYS-TEL-EXT-004",
    "CLX-SYS-TEL-EXT-005",
  ];
  for (const rowId of requiredRows) {
    const rowPattern = new RegExp(`\\|\\s*${rowId}\\s*\\|[^\\n]*\\|\\s*EXTERNAL PENDING\\s*\\|`);
    assert(rowPattern.test(text), `docs/governance/system-telemetry/external-pending.md: ${rowId} must remain EXTERNAL PENDING`);
  }

  const validatedRows = [
    "CLX-SYS-TEL-EXT-001",
    "CLX-SYS-TEL-EXT-002",
    "CLX-SYS-TEL-EXT-006",
  ];
  for (const rowId of validatedRows) {
    const rowPattern = new RegExp(`\\|\\s*${rowId}\\s*\\|[^\\n]*\\|\\s*VALIDATED LOCAL\\s*\\|`);
    assert(rowPattern.test(text), `docs/governance/system-telemetry/external-pending.md: ${rowId} must remain VALIDATED LOCAL`);
  }
}

function assertExternalValidationManifest() {
  const manifest = readJson("docs/governance/system-telemetry/external-validation.manifest.json");
  assert(manifest.$schema === "docs/governance/system-telemetry/external-validation.manifest.schema.json", "external validation manifest: wrong schema ref");
  assert(manifest.schemaVersion === 1, "external validation manifest: schemaVersion must be 1");
  assert(manifest.id === "clawix-system-telemetry-external-validation-manifest", "external validation manifest: wrong id");
  assert(manifest.conversationId === "source:system-telemetry", "external validation manifest: wrong conversationId");
  assert(manifest.planId === "plan:system-telemetry", "external validation manifest: wrong planId");
  assert(manifest.status === "active_goal_not_complete", "external validation manifest: goal must remain active");
  assert(manifest.completionPolicy?.externalPendingBlocksCompletion === true, "external validation manifest: external pending must block completion");
  assert(manifest.completionPolicy?.requiresFinalSourceAudit === true, "external validation manifest: final source audit must be required");
  assert(manifest.completionPolicy?.requiresSourceQaReview === true, "external validation manifest: source Q/A review must be required");
  assert(manifest.completionPolicy?.requiresCompletionAudit === true, "external validation manifest: completion audit must be required");
  assert(manifest.completionPolicy?.requiresExternalValidationRunbook === true, "external validation manifest: external validation runbook must be required");
  assert(manifest.completionPolicy?.requiresExternalEvidenceSchema === true, "external validation manifest: external evidence schema must be required");
  assert(manifest.completionPolicy?.requiresForbiddenNameScan === true, "external validation manifest: forbidden-name scan must be required");
  assert(manifest.completionPolicy?.requiresExactRunApprovalForExternalLanes === true, "external validation manifest: exact-run approval must be required");
  assert(manifest.sourceQaReview?.required === true, "external validation manifest: source Q/A review link must be required");
  assert(manifest.sourceQaReview?.artifactId === "clawix-system-telemetry-source-qa-review", "external validation manifest: wrong source Q/A artifact");
  assert(manifest.sourceQaReview?.path === "docs/governance/system-telemetry/source-review.json", "external validation manifest: wrong source Q/A path");
  assert(manifest.sourceQaReview?.privateAuditAlias === "private-goal-audit:claw-system-telemetry-context-menubar-source-audit-2026-05-20", "external validation manifest: wrong private audit alias");
  assert(manifest.sourceQaReview?.closureRole?.includes("public-safe validation rows"), "external validation manifest: source Q/A closure role must be explicit");
  assert(manifest.completionAudit?.required === true, "external validation manifest: completion audit link must be required");
  assert(manifest.completionAudit?.artifactId === "clawix-system-telemetry-completion-audit", "external validation manifest: wrong completion audit artifact");
  assert(manifest.completionAudit?.path === "docs/governance/system-telemetry/completion.md", "external validation manifest: wrong completion audit path");
  assert(manifest.completionAudit?.requiredRowPrefix === "CLX-STA", "external validation manifest: wrong completion audit row prefix");
  assert(manifest.completionAudit?.requiredRowCount === 16, "external validation manifest: wrong completion audit row count");
  assert(manifest.completionAudit?.statusSummary?.validatedLocalRows === 12, "external validation manifest: wrong completion audit validated-local count");
  assert(manifest.completionAudit?.statusSummary?.activeClosureGateRows === 1, "external validation manifest: wrong completion audit active-closure-gate count");
  assert(manifest.completionAudit?.statusSummary?.externalPendingRows === 3, "external validation manifest: wrong completion audit external-pending count");
  for (const rowId of ["CLX-STA-014", "CLX-STA-015", "CLX-STA-016"]) {
    assert(manifest.completionAudit?.statusSummary?.externalPendingRowIds?.includes(rowId), `external validation manifest: completion audit status summary missing ${rowId}`);
  }
  assert(manifest.completionAudit?.closureRole?.includes("requirement by requirement"), "external validation manifest: completion audit closure role must be explicit");
  assert(manifest.externalValidationRunbook?.required === true, "external validation manifest: external validation runbook link must be required");
  assert(manifest.externalValidationRunbook?.artifactId === "clawix-system-telemetry-external-validation-runbook", "external validation manifest: wrong external validation runbook artifact");
  assert(manifest.externalValidationRunbook?.path === "docs/governance/system-telemetry/external-validation-runbook.md", "external validation manifest: wrong external validation runbook path");
  assert(manifest.externalValidationRunbook?.laneCount === 3, "external validation manifest: wrong external validation runbook lane count");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(manifest.externalValidationRunbook?.externalPendingRowIds?.includes(rowId), `external validation manifest: external validation runbook missing ${rowId}`);
  }
  assert(manifest.externalValidationRunbook?.closureRole?.includes("safe preflight"), "external validation manifest: external validation runbook closure role must be explicit");
  assert(manifest.externalApprovalPacketSchema?.required === true, "external validation manifest: external approval packet schema link must be required");
  assert(manifest.externalApprovalPacketSchema?.artifactId === "clawix-system-telemetry-external-approval-schema", "external validation manifest: wrong external approval schema artifact");
  assert(manifest.externalApprovalPacketSchema?.path === "docs/governance/system-telemetry/external-approval.schema.json", "external validation manifest: wrong external approval schema path");
  assert(manifest.externalApprovalPacketSchema?.laneCount === 3, "external validation manifest: wrong external approval schema lane count");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(manifest.externalApprovalPacketSchema?.externalPendingRowIds?.includes(rowId), `external validation manifest: external approval schema missing ${rowId}`);
  }
  assert(manifest.externalApprovalPacketSchema?.closureRole?.includes("exact-run approval packet"), "external validation manifest: external approval schema closure role must be explicit");
  assert(manifest.externalApprovalFixtures?.required === true, "external validation manifest: external approval fixtures link must be required");
  assert(manifest.externalApprovalFixtures?.artifactId === "clawix-system-telemetry-external-approval-fixtures", "external validation manifest: wrong external approval fixtures artifact");
  assert(manifest.externalApprovalFixtures?.path === "docs/governance/system-telemetry/external-approval.fixtures.json", "external validation manifest: wrong external approval fixtures path");
  assert(manifest.externalApprovalFixtures?.status === "synthetic_templates_not_approval", "external validation manifest: external approval fixtures must be marked synthetic");
  assert(manifest.externalApprovalFixtures?.validTemplateCount === 3, "external validation manifest: wrong external approval valid fixture count");
  assert(manifest.externalApprovalFixtures?.invalidTemplateCount === 10, "external validation manifest: wrong external approval invalid fixture count");
  assert(manifest.externalApprovalFixtures?.closureRole?.includes("without representing real approval"), "external validation manifest: external approval fixtures closure role must be explicit");
  assert(manifest.externalApprovalPacketValidator?.required === true, "external validation manifest: external approval validator link must be required");
  assert(manifest.externalApprovalPacketValidator?.artifactId === "clawix-system-telemetry-external-approval-validator", "external validation manifest: wrong external approval validator artifact");
  assert(manifest.externalApprovalPacketValidator?.path === "scripts/validate-system-telemetry-external-approval.mjs", "external validation manifest: wrong external approval validator path");
  assert(manifest.externalApprovalPacketValidator?.fixtureCommand === "node scripts/validate-system-telemetry-external-approval.mjs --fixtures", "external validation manifest: wrong external approval validator fixture command");
  assert(manifest.externalApprovalPacketValidator?.packetCommand === "node scripts/validate-system-telemetry-external-approval.mjs <packet.json>", "external validation manifest: wrong external approval validator packet command");
  assert(manifest.externalApprovalPacketValidator?.closureRole?.includes("validates any future exact-run app approval packet"), "external validation manifest: external approval validator closure role must be explicit");
  assert(manifest.externalEvidencePacketSchema?.required === true, "external validation manifest: external evidence packet schema link must be required");
  assert(manifest.externalEvidencePacketSchema?.artifactId === "clawix-system-telemetry-external-evidence-schema", "external validation manifest: wrong external evidence schema artifact");
  assert(manifest.externalEvidencePacketSchema?.path === "docs/governance/system-telemetry/external-evidence.schema.json", "external validation manifest: wrong external evidence schema path");
  assert(manifest.externalEvidencePacketSchema?.laneCount === 3, "external validation manifest: wrong external evidence schema lane count");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(manifest.externalEvidencePacketSchema?.externalPendingRowIds?.includes(rowId), `external validation manifest: external evidence schema missing ${rowId}`);
  }
  assert(manifest.externalEvidencePacketSchema?.closureRole?.includes("redacted receipt"), "external validation manifest: external evidence schema closure role must be explicit");
  assert(manifest.externalEvidenceFixtures?.required === true, "external validation manifest: external evidence fixtures link must be required");
  assert(manifest.externalEvidenceFixtures?.artifactId === "clawix-system-telemetry-external-evidence-fixtures", "external validation manifest: wrong external evidence fixtures artifact");
  assert(manifest.externalEvidenceFixtures?.path === "docs/governance/system-telemetry/external-evidence.fixtures.json", "external validation manifest: wrong external evidence fixtures path");
  assert(manifest.externalEvidenceFixtures?.status === "synthetic_templates_not_evidence", "external validation manifest: external evidence fixtures must be marked synthetic");
  assert(manifest.externalEvidenceFixtures?.validTemplateCount === 3, "external validation manifest: wrong valid fixture count");
  assert(manifest.externalEvidenceFixtures?.invalidTemplateCount === 15, "external validation manifest: wrong invalid fixture count");
  assert(manifest.externalEvidenceFixtures?.closureRole?.includes("without representing real external evidence"), "external validation manifest: external evidence fixtures closure role must be explicit");
  assert(manifest.externalEvidencePacketValidator?.required === true, "external validation manifest: external evidence validator link must be required");
  assert(manifest.externalEvidencePacketValidator?.artifactId === "clawix-system-telemetry-external-evidence-validator", "external validation manifest: wrong external evidence validator artifact");
  assert(manifest.externalEvidencePacketValidator?.path === "scripts/validate-system-telemetry-external-evidence.mjs", "external validation manifest: wrong external evidence validator path");
  assert(manifest.externalEvidencePacketValidator?.fixtureCommand === "node scripts/validate-system-telemetry-external-evidence.mjs --fixtures", "external validation manifest: wrong external evidence validator fixture command");
  assert(manifest.externalEvidencePacketValidator?.packetCommand === "node scripts/validate-system-telemetry-external-evidence.mjs <packet.json>", "external validation manifest: wrong external evidence validator packet command");
  assert(manifest.externalEvidencePacketValidator?.closureRole?.includes("validates any future redacted evidence packet"), "external validation manifest: external evidence validator closure role must be explicit");
  assert(manifest.externalClosureFixtures?.required === true, "external validation manifest: external closure fixtures link must be required");
  assert(manifest.externalClosureFixtures?.artifactId === "clawix-system-telemetry-external-closure-fixtures", "external validation manifest: wrong external closure fixtures artifact");
  assert(manifest.externalClosureFixtures?.path === "docs/governance/system-telemetry/external-closure.fixtures.json", "external validation manifest: wrong external closure fixtures path");
  assert(manifest.externalClosureFixtures?.status === "synthetic_templates_not_closure", "external validation manifest: external closure fixtures must be synthetic");
  assert(manifest.externalClosureFixtures?.validTemplateCount === 3, "external validation manifest: wrong external closure valid fixture count");
  assert(manifest.externalClosureFixtures?.invalidMutationCount === 20, "external validation manifest: wrong external closure invalid mutation count");
  assert(manifest.externalClosureFixtures?.closureRole?.includes("approval id, exact run scope, approving actor, approved action grants, credential/native/location/hardware/signed-app refs, approval window, evidence timeline"), "external validation manifest: external closure fixtures closure role must be explicit");
  assert(manifest.externalClosureBundleValidator?.required === true, "external validation manifest: external closure validator link must be required");
  assert(manifest.externalClosureBundleValidator?.artifactId === "clawix-system-telemetry-external-closure-validator", "external validation manifest: wrong external closure validator artifact");
  assert(manifest.externalClosureBundleValidator?.path === "scripts/validate-system-telemetry-external-closure.mjs", "external validation manifest: wrong external closure validator path");
  assert(manifest.externalClosureBundleValidator?.fixtureCommand === "node scripts/validate-system-telemetry-external-closure.mjs --fixtures", "external validation manifest: wrong external closure validator fixture command");
  assert(manifest.externalClosureBundleValidator?.bundleCommand === "node scripts/validate-system-telemetry-external-closure.mjs <bundle.json>", "external validation manifest: wrong external closure validator bundle command");
  assert(manifest.externalClosureBundleValidator?.closureRole?.includes("approval-plus-evidence app closure bundle"), "external validation manifest: external closure validator closure role must be explicit");
  assert(manifest.externalValidationManifestFixtures?.required === true, "external validation manifest: manifest fixtures link must be required");
  assert(manifest.externalValidationManifestFixtures?.artifactId === "clawix-system-telemetry-external-validation-manifest-fixtures", "external validation manifest: wrong manifest fixtures artifact");
  assert(manifest.externalValidationManifestFixtures?.path === "docs/governance/system-telemetry/external-validation.manifest.fixtures.json", "external validation manifest: wrong manifest fixtures path");
  assert(manifest.externalValidationManifestFixtures?.status === "synthetic_templates_not_evidence", "external validation manifest: manifest fixtures must be synthetic");
  assert(manifest.externalValidationManifestFixtures?.validTemplateCount === 1, "external validation manifest: wrong manifest valid fixture count");
  assert(manifest.externalValidationManifestFixtures?.invalidMutationCount === 9, "external validation manifest: wrong manifest invalid mutation count");
  assert(manifest.externalValidationManifestFixtures?.closureRole?.includes("rejects accidental completion"), "external validation manifest: manifest fixtures closure role must be explicit");
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
  assert(rows.get("CLX-SYS-TEL-EXT-005")?.acceptedEvidence?.includes("app_or_menu_same_machine_evidence"), "external validation manifest: control lane must require app/menu same-machine evidence");
  assert(rows.get("CLX-SYS-TEL-EXT-005")?.acceptedEvidence?.includes("rollback_or_continuity_evidence"), "external validation manifest: control lane must require rollback or continuity evidence");

  for (const rowId of ["CLX-SYS-TEL-EXT-001", "CLX-SYS-TEL-EXT-002", "CLX-SYS-TEL-EXT-006"]) {
    const row = rows.get(rowId);
    assert(row?.status === "VALIDATED LOCAL", `external validation manifest: ${rowId} must remain VALIDATED LOCAL`);
    assert(Array.isArray(row.blockingPrerequisites) && row.blockingPrerequisites.length === 0, `external validation manifest: ${rowId} must not keep external prerequisites`);
  }
}

function assertExternalValidationManifestSchema() {
  const schema = readJson("docs/governance/system-telemetry/external-validation.manifest.schema.json");
  const manifest = readJson("docs/governance/system-telemetry/external-validation.manifest.json");
  const serialized = JSON.stringify(schema);
  assert(schema.$schema === "https://json-schema.org/draft/2020-12/schema", "external validation manifest schema: wrong JSON schema version");
  assert(schema.$id === "https://clawix.dev/schemas/governance/system-telemetry/external-validation.manifest.schema.json", "external validation manifest schema: wrong id");
  assert(schema.title === "Clawix System Telemetry External Validation Manifest", "external validation manifest schema: wrong title");
  for (const snippet of [
    "active_goal_not_complete",
    "externalPendingBlocksCompletion",
    "requiresExactRunApprovalForExternalLanes",
    "CLX-SYS-TEL-EXT-003",
    "CLX-SYS-TEL-EXT-004",
    "CLX-SYS-TEL-EXT-005",
    "VALIDATED LOCAL",
    "EXTERNAL PENDING",
    "docs/governance/system-telemetry/external-approval.fixtures.json",
    "scripts/validate-system-telemetry-external-approval.mjs",
    "docs/governance/system-telemetry/external-closure.fixtures.json",
    "scripts/validate-system-telemetry-external-closure.mjs",
    "scripts/validate-system-telemetry-external-evidence.mjs",
    "docs/governance/system-telemetry/external-validation.manifest.fixtures.json",
  ]) {
    assert(serialized.includes(snippet), `external validation manifest schema: missing ${snippet}`);
  }
  const ajv = new Ajv2020({ allErrors: true, validateFormats: false, strict: false });
  const validate = ajv.compile(schema);
  assert(validate(manifest), `external validation manifest schema: manifest must validate: ${ajv.errorsText(validate.errors)}`);
  assert(!serialized.includes("/Users/"), "external validation manifest schema: must not publish private filesystem paths");
}

function assertExternalValidationManifestFixtures() {
  const fixtures = readJson("docs/governance/system-telemetry/external-validation.manifest.fixtures.json");
  const schema = readJson("docs/governance/system-telemetry/external-validation.manifest.schema.json");
  const manifest = readJson("docs/governance/system-telemetry/external-validation.manifest.json");
  assert(fixtures.schemaVersion === 1, "external validation manifest fixtures: schemaVersion must be 1");
  assert(fixtures.artifactId === "clawix-system-telemetry-external-validation-manifest-fixtures", "external validation manifest fixtures: wrong artifact id");
  assert(fixtures.status === "synthetic_templates_not_evidence", "external validation manifest fixtures: must be synthetic templates only");
  assert(fixtures.conversationId === "source:system-telemetry", "external validation manifest fixtures: wrong conversation id");
  assert(fixtures.planId === "plan:system-telemetry", "external validation manifest fixtures: wrong plan id");
  assert(fixtures.schemaPath === "docs/governance/system-telemetry/external-validation.manifest.schema.json", "external validation manifest fixtures: wrong schema path");
  assert(fixtures.manifestPath === "docs/governance/system-telemetry/external-validation.manifest.json", "external validation manifest fixtures: wrong manifest path");
  assert(Array.isArray(fixtures.validSyntheticManifests) && fixtures.validSyntheticManifests.length === 1, "external validation manifest fixtures: must contain 1 valid manifest reference");
  assert(Array.isArray(fixtures.invalidSyntheticMutations) && fixtures.invalidSyntheticMutations.length === 9, "external validation manifest fixtures: must contain 9 invalid mutations");
  const ajv = new Ajv2020({ allErrors: true, validateFormats: false, strict: false });
  const validate = ajv.compile(schema);
  assert(validate(manifest), `external validation manifest fixtures: current manifest must validate: ${ajv.errorsText(validate.errors)}`);
  for (const fixture of fixtures.invalidSyntheticMutations) {
    const mutated = JSON.parse(JSON.stringify(manifest));
    switch (fixture.mutation) {
      case "set_manifest_status_complete":
        mutated.status = "complete";
        break;
      case "set_external_pending_rows_zero":
        mutated.completionAudit.statusSummary.externalPendingRows = 0;
        break;
      case "mark_first_external_lane_validated_local": {
        const row = mutated.rows.find((candidate) => candidate.id === "CLX-SYS-TEL-EXT-003");
        row.status = "VALIDATED LOCAL";
        row.blockingPrerequisites = [];
        break;
      }
      case "delete_external_evidence_packet_validator":
        delete mutated.externalEvidencePacketValidator;
        break;
      case "delete_external_approval_packet_validator":
        delete mutated.externalApprovalPacketValidator;
        break;
      case "delete_external_closure_bundle_validator":
        delete mutated.externalClosureBundleValidator;
        break;
      case "set_external_closure_fixture_invalid_count_14":
        mutated.externalClosureFixtures.invalidMutationCount = 14;
        break;
      case "remove_control_lane_app_menu_evidence": {
        const row = mutated.rows.find((candidate) => candidate.id === "CLX-SYS-TEL-EXT-005");
        row.acceptedEvidence = row.acceptedEvidence.filter((entry) => entry !== "app_or_menu_same_machine_evidence");
        break;
      }
      case "drop_external_pending_lane_id":
        mutated.externalValidationRunbook.externalPendingRowIds = ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004"];
        break;
      default:
        fail(`external validation manifest fixtures: unknown mutation ${fixture.mutation}`);
    }
    assert(!validate(mutated), `external validation manifest fixtures: invalid mutation ${fixture.id} must fail validation`);
    assert(typeof fixture.reason === "string" && fixture.reason.length > 0, `external validation manifest fixtures: mutation ${fixture.id} must document reason`);
  }
  assert(!JSON.stringify(fixtures).includes("/Users/"), "external validation manifest fixtures: must not publish private filesystem paths");
}

function mutateApprovalTemplate(packet, mutation) {
  const mutated = JSON.parse(JSON.stringify(packet));
  switch (mutation) {
    case "approval.exactRunApproved=false":
      mutated.approval.exactRunApproved = false;
      break;
    case "authorization.signedAppRefs=[]":
      mutated.authorization.signedAppRefs = [];
      break;
    case "risk.appMenuValidationPlanRef=\"\"":
      mutated.risk.appMenuValidationPlanRef = "";
      break;
    case "approval.expiresAt=beforeApprovedAt":
      mutated.approval.expiresAt = "2026-05-19T23:59:59Z";
      break;
    case "approval.approvedAt=notTimestamp":
      mutated.approval.approvedAt = "not-a-timestamp";
      break;
    case "approval.approvedActions=extra":
      mutated.approval.approvedActions = [mutated.approval.approvedActions[0], "extra_unapproved_action_template"];
      break;
    case "authorization.credentialLeaseRefs=extra":
      mutated.authorization.credentialLeaseRefs = [mutated.authorization.credentialLeaseRefs[0], "extra_lease_template"];
      break;
    case "authorization.nativeGrantRefs=extra":
      mutated.authorization.nativeGrantRefs = [mutated.authorization.nativeGrantRefs[0], "extra_native_grant_template"];
      break;
    case "authorization.credentialLeaseRefs=rawSecretRef":
      mutated.authorization.credentialLeaseRefs = ["secret://raw-template"];
      break;
    case "closureImpact.externalPendingRows=extra":
      mutated.closureImpact.externalPendingRows = [mutated.laneId, "CLX-SYS-TEL-EXT-999"];
      break;
    default:
      fail(`external approval fixtures: unknown mutation ${mutation}`);
  }
  return mutated;
}

function approvalTemplateErrors(packet, validate, ajv) {
  const errors = [];
  errors.push(...publicSafetyErrors(packet));
  if (!validate(packet)) errors.push(ajv.errorsText(validate.errors));
  const approvedAt = Date.parse(packet.approval?.approvedAt);
  const expiresAt = Date.parse(packet.approval?.expiresAt);
  if (!Number.isFinite(approvedAt)) errors.push("approval.approvedAt must be parseable");
  if (!Number.isFinite(expiresAt)) errors.push("approval.expiresAt must be parseable");
  if (Number.isFinite(approvedAt) && Number.isFinite(expiresAt) && expiresAt <= approvedAt) {
    errors.push("approval.expiresAt must be after approval.approvedAt");
  }
  return errors;
}

function assertExternalApprovalSchema() {
  const schema = readJson("docs/governance/system-telemetry/external-approval.schema.json");
  const serialized = JSON.stringify(schema);
  assert(schema.$schema === "https://json-schema.org/draft/2020-12/schema", "external approval schema: wrong JSON schema version");
  assert(schema.$id === "https://clawix.dev/schemas/governance/system-telemetry/external-approval.schema.json", "external approval schema: wrong id");
  assert(schema.title === "Clawix System Telemetry External Approval Packet", "external approval schema: wrong title");
  assert(schema["x-validatorPath"] === "scripts/validate-system-telemetry-external-approval.mjs", "external approval schema: wrong validator path");
  assert(schema.properties?.schemaVersion?.const === 1, "external approval schema: schemaVersion must be 1");
  assert(schema.properties?.conversationId?.const === "source:system-telemetry", "external approval schema: wrong conversation id");
  assert(schema.properties?.planId?.const === "plan:system-telemetry", "external approval schema: wrong plan id");
  assert(schema.properties?.repoScope?.const === "clawix-app", "external approval schema: wrong repo scope");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(schema.properties?.laneId?.enum?.includes(rowId), `external approval schema: missing lane ${rowId}`);
  }
  for (const required of ["approval", "preflight", "authorization", "risk", "privacy", "closureImpact"]) {
    assert(schema.required?.includes(required), `external approval schema: missing required field ${required}`);
  }
  assert(schema.properties?.approval?.properties?.decision?.const === "approved", "external approval schema: decision must be approved");
  assert(schema.properties?.approval?.properties?.approvalId?.minLength === 1, "external approval schema: approval id must be required");
  assert(schema.properties?.approval?.properties?.exactRunApproved?.const === true, "external approval schema: exact-run approval must be true");
  assert(schema.properties?.approval?.properties?.exactRunScope?.minLength === 1, "external approval schema: exact run scope must be required");
  assert(schema.properties?.approval?.properties?.approvedActions?.maxItems === 1, "external approval schema: approved actions must be exact");
  for (const field of ["credentialLeaseRefs", "nativeGrantRefs", "locationGrantRefs", "hardwareProviderRefs", "signedAppRefs"]) {
    assert(schema.properties?.authorization?.properties?.[field]?.maxItems === 1, `external approval schema: ${field} must be exact`);
  }
  const publicCredentialLeaseRef = assertPublicCredentialLeaseRefSchema(schema, "external approval schema");
  assert(schema.properties?.authorization?.properties?.credentialLeaseRefs?.items?.$ref === publicCredentialLeaseRef, "external approval schema: credential lease refs must use public-safe refs");
  assert(schema.properties?.approval?.properties?.approvedAt?.format === "date-time", "external approval schema: approvedAt must be date-time");
  assert(schema.properties?.approval?.properties?.expiresAt?.format === "date-time", "external approval schema: expiresAt must be date-time");
  assert(schema.properties?.preflight?.properties?.command?.pattern === "^claw system ", "external approval schema: preflight command must be claw system");
  assert(schema.properties?.preflight?.properties?.mustFailClosedBeforeApproval?.const === true, "external approval schema: preflight must fail closed before approval");
  assert(schema.properties?.privacy?.properties?.containsSecrets?.const === false, "external approval schema: secrets must be forbidden");
  assert(schema.properties?.privacy?.properties?.preciseLocationApprovedForStorage?.const === false, "external approval schema: precise location storage must be forbidden");
  assert(schema.properties?.privacy?.properties?.privatePathsIncluded?.const === false, "external approval schema: private paths must be forbidden");
  assert(schema.properties?.closureImpact?.properties?.externalPendingRows?.maxItems === 1, "external approval schema: closure external rows must be exact");
  for (const snippet of [
    "provider_connection",
    "physical_sensor_read",
    "dangerous_control_execute",
    "credentialLeaseRefs",
    "nativeGrantRefs",
    "networkAccessApproved",
    "hardwareProviderRefs",
    "signedAppRefs",
    "rollbackOrContinuityPlanRef",
    "physicalValidationPlanRef",
    "appMenuValidationPlanRef",
  ]) {
    assert(serialized.includes(snippet), `external approval schema: missing ${snippet}`);
  }
  const laneRules = new Map((schema.allOf ?? []).map((rule) => [rule.if?.properties?.laneId?.const, rule.then]));
  assert(laneRules.size === 3, "external approval schema: must define exactly 3 lane-specific rules");
  assert(laneRules.get("CLX-SYS-TEL-EXT-003")?.properties?.authorization?.properties?.nativeGrantRefs?.minItems === 1, "external approval schema: sensor lane must require native grant refs");
  assert(laneRules.get("CLX-SYS-TEL-EXT-003")?.properties?.authorization?.properties?.nativeGrantRefs?.maxItems === 1, "external approval schema: sensor lane native grant refs must be exact");
  assert(laneRules.get("CLX-SYS-TEL-EXT-003")?.properties?.authorization?.properties?.hardwareProviderRefs?.minItems === 1, "external approval schema: sensor lane must require hardware provider refs");
  assert(laneRules.get("CLX-SYS-TEL-EXT-003")?.properties?.authorization?.properties?.signedAppRefs?.minItems === 1, "external approval schema: sensor lane must require signed app refs");
  assert(laneRules.get("CLX-SYS-TEL-EXT-003")?.properties?.closureImpact?.properties?.externalPendingRows?.maxItems === 1, "external approval schema: sensor lane must close only its own external row");
  assert(laneRules.get("CLX-SYS-TEL-EXT-004")?.properties?.authorization?.properties?.credentialLeaseRefs?.minItems === 1, "external approval schema: live lane must require credential lease refs");
  assert(laneRules.get("CLX-SYS-TEL-EXT-004")?.properties?.authorization?.properties?.credentialLeaseRefs?.maxItems === 1, "external approval schema: live lane credential lease refs must be exact");
  assert(laneRules.get("CLX-SYS-TEL-EXT-004")?.properties?.authorization?.properties?.networkAccessApproved?.const === true, "external approval schema: live lane must require network approval");
  assert(laneRules.get("CLX-SYS-TEL-EXT-004")?.properties?.closureImpact?.properties?.externalPendingRows?.maxItems === 1, "external approval schema: live lane must close only its own external row");
  assert(laneRules.get("CLX-SYS-TEL-EXT-005")?.properties?.risk?.properties?.rollbackOrContinuityPlanRef?.minLength === 1, "external approval schema: control lane must require rollback plan");
  assert(laneRules.get("CLX-SYS-TEL-EXT-005")?.properties?.risk?.properties?.physicalValidationPlanRef?.minLength === 1, "external approval schema: control lane must require physical validation plan");
  assert(laneRules.get("CLX-SYS-TEL-EXT-005")?.properties?.closureImpact?.properties?.externalPendingRows?.maxItems === 1, "external approval schema: control lane must close only its own external row");
  const ajv = new Ajv2020({ allErrors: true, validateFormats: false, strict: false });
  const validate = ajv.compile(schema);
  for (const packet of readJson("docs/governance/system-telemetry/external-approval.fixtures.json").validSyntheticPackets) {
    assert(validate(packet), `external approval schema: valid packet ${packet.laneId} must validate: ${ajv.errorsText(validate.errors)}`);
  }
  assert(!serialized.includes("/Users/"), "external approval schema: must not publish private filesystem paths");
}

function assertExternalApprovalFixtures() {
  const fixtures = readJson("docs/governance/system-telemetry/external-approval.fixtures.json");
  const schema = readJson("docs/governance/system-telemetry/external-approval.schema.json");
  assert(fixtures.schemaVersion === 1, "external approval fixtures: schemaVersion must be 1");
  assert(fixtures.artifactId === "clawix-system-telemetry-external-approval-fixtures", "external approval fixtures: wrong artifact id");
  assert(fixtures.status === "synthetic_templates_not_approval", "external approval fixtures: must be synthetic templates only");
  assert(fixtures.conversationId === "source:system-telemetry", "external approval fixtures: wrong conversation id");
  assert(fixtures.planId === "plan:system-telemetry", "external approval fixtures: wrong plan id");
  assert(fixtures.schemaPath === "docs/governance/system-telemetry/external-approval.schema.json", "external approval fixtures: wrong schema path");
  assert(fixtures.validatorPath === "scripts/validate-system-telemetry-external-approval.mjs", "external approval fixtures: wrong validator path");
  assert(Array.isArray(fixtures.validSyntheticPackets) && fixtures.validSyntheticPackets.length === 3, "external approval fixtures: must contain 3 valid synthetic packets");
  assert(Array.isArray(fixtures.invalidSyntheticPackets) && fixtures.invalidSyntheticPackets.length === 10, "external approval fixtures: must contain 10 invalid synthetic packets");
  const ajv = new Ajv2020({ allErrors: true, validateFormats: false, strict: false });
  const validate = ajv.compile(schema);
  const validByLaneId = new Map();
  for (const packet of fixtures.validSyntheticPackets) {
    const errors = approvalTemplateErrors(packet, validate, ajv);
    assert(errors.length === 0, `external approval fixtures: valid packet ${packet.laneId} must validate: ${errors.join("; ")}`);
    validByLaneId.set(packet.laneId, packet);
    assert(typeof packet.approval?.approvalId === "string" && packet.approval.approvalId.length > 0, `external approval fixtures: ${packet.laneId} must include approval id`);
    assert(packet.privacy?.containsSecrets === false, `external approval fixtures: ${packet.laneId} must not contain secrets`);
    assert(packet.privacy?.preciseLocationApprovedForStorage === false, `external approval fixtures: ${packet.laneId} must not store precise location`);
    assert(packet.privacy?.privatePathsIncluded === false, `external approval fixtures: ${packet.laneId} must not include private paths`);
  }
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(validByLaneId.has(rowId), `external approval fixtures: missing valid template for ${rowId}`);
  }
  for (const fixture of fixtures.invalidSyntheticPackets) {
    const base = validByLaneId.get(fixture.packetRef);
    assert(base, `external approval fixtures: invalid packet ${fixture.id} references unknown lane ${fixture.packetRef}`);
    assert(approvalTemplateErrors(mutateApprovalTemplate(base, fixture.mutation), validate, ajv).length > 0, `external approval fixtures: invalid packet ${fixture.id} must fail validation`);
  }
  assert(!JSON.stringify(fixtures).includes("/Users/"), "external approval fixtures: must not publish private filesystem paths");
}

function assertExternalApprovalValidator() {
  const output = run(process.execPath, ["scripts/validate-system-telemetry-external-approval.mjs", "--fixtures"]);
  const result = JSON.parse(output);
  assert(result.ok === true, "external approval validator: fixture validation must pass");
  assert(result.status === "synthetic_templates_not_approval", "external approval validator: fixtures must remain synthetic");
  assert(result.validSyntheticPackets === 3, "external approval validator: must accept 3 valid synthetic packets");
  assert(result.invalidSyntheticPackets === 10, "external approval validator: must reject 10 invalid synthetic packets");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(result.accepted?.includes(rowId), `external approval validator: missing accepted fixture for ${rowId}`);
  }
}

function assertExternalValidationRunbook() {
  const text = read("docs/governance/system-telemetry/external-validation-runbook.md");
  for (const snippet of [
    "Source conversation: `source:system-telemetry`",
    "Plan item: `plan:system-telemetry`",
    "Status: `active_goal_not_complete`",
    "This runbook defines the only accepted way to replace the remaining Clawix",
    "It does not authorize provider calls,",
    "Each lane requires",
    "explicit approval for the exact run before execution.",
    "`docs/governance/system-telemetry/external-approval.schema.json`",
    "`docs/governance/system-telemetry/external-approval.fixtures.json`",
    "they only prove schema behavior and are not real approval",
    "`node scripts/validate-system-telemetry-external-approval.mjs <packet.json>`",
    "before any provider, sensor, or control execution starts",
    "Any accepted run must produce a redacted evidence packet conforming to",
    "`docs/governance/system-telemetry/external-evidence.schema.json`",
    "lane-closing record",
    "`docs/governance/system-telemetry/external-validation.manifest.schema.json`",
    "lane status update",
    "`docs/governance/system-telemetry/external-validation.manifest.fixtures.json`",
    "schema validation templates only",
    "`node scripts/validate-system-telemetry-external-evidence.mjs <packet.json>`",
    "before updating any ledger, manifest, completion audit, or source Q/A review",
    "`docs/governance/system-telemetry/external-evidence.fixtures.json`",
    "templates for",
    "must not be cited as real external evidence",
    "same-lane closure bundle",
    "`docs/governance/system-telemetry/external-closure.fixtures.json`",
    "not real closure evidence",
    "All evidence timestamps must remain inside that approval packet's",
    "`node scripts/validate-system-telemetry-external-closure.mjs <bundle.json>`",
    "| Row | Safe preflight | Approval packet | Execution evidence | Update target | Fail rule |",
    "| CLX-SYS-TEL-EXT-003 | `claw system providers plan system.sensors.signed --json`",
    "Monitor sample IDs for `system.sensor.temperature` or `system.sensor.fan_speed`",
    "app/menu same-machine evidence",
    "fake zero samples are defects",
    "| CLX-SYS-TEL-EXT-004 | `claw system providers plan context.weather.live --json`",
    "Provider execution receipt, redacted audit event, Monitor sample IDs for `context.weather.temperature`",
    "Replace `CLX-SYS-TEL-EXT-004` in the ledger, manifest, completion audit, and source Q/A review",
    "a failed approved run is a defect, not a pending row",
    "| CLX-SYS-TEL-EXT-005 | `claw system controls plan <control-id> --json`",
    "Pre-execution plan with `willExecute=true` only after approval",
    "app/menu evidence, and rollback/continuity evidence",
    "failed approved execution is a defect",
    "## Exact Approval Inputs",
    "These are the minimum public-safe fields that must be resolved before building",
    "They are not approval by themselves.",
    "native `system.sensor.read` grant reference",
    "credential lease reference, location grant reference, network approval",
    "exact control id, target, value, native grant reference",
    "Must stay absent from public artifacts",
    "If any required field is still unknown, keep the lane as `EXTERNAL PENDING`",
    "Do not mark the goal complete until every lane above is either replaced with",
    "source reread, completion audit, approval schema check, evidence schema check,",
    "same-lane closure bundle check",
  ]) {
    assert(text.includes(snippet), `docs/governance/system-telemetry/external-validation-runbook.md: missing ${JSON.stringify(snippet)}`);
  }
  const laneRows = text.match(/^\| CLX-SYS-TEL-EXT-\d{3} \|/gm) ?? [];
  assert(laneRows.length === 3, "docs/governance/system-telemetry/external-validation-runbook.md: must contain exactly 3 external lane rows");
  const laneIds = laneRows.map((row) => row.match(/CLX-SYS-TEL-EXT-\d{3}/)?.[0]).filter(Boolean);
  assertSameStringSet(laneIds, ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"], "docs/governance/system-telemetry/external-validation-runbook.md: lane rows");
  assert(!text.includes("/Users/"), "docs/governance/system-telemetry/external-validation-runbook.md: must not publish private filesystem paths");
}

function assertExternalEvidenceSchema() {
  const schema = readJson("docs/governance/system-telemetry/external-evidence.schema.json");
  const serialized = JSON.stringify(schema);
  assert(schema.$schema === "https://json-schema.org/draft/2020-12/schema", "external evidence schema: wrong JSON schema version");
  assert(schema.$id === "https://clawix.dev/schemas/governance/system-telemetry/external-evidence.schema.json", "external evidence schema: wrong id");
  assert(schema.title === "Clawix System Telemetry External Evidence Packet", "external evidence schema: wrong title");
  assert(schema["x-fixturePath"] === "docs/governance/system-telemetry/external-evidence.fixtures.json", "external evidence schema: wrong fixture path");
  assert(schema.properties?.schemaVersion?.const === 1, "external evidence schema: schemaVersion must be 1");
  assert(schema.properties?.conversationId?.const === "source:system-telemetry", "external evidence schema: wrong conversation id");
  assert(schema.properties?.planId?.const === "plan:system-telemetry", "external evidence schema: wrong plan id");
  assert(schema.properties?.repoScope?.const === "clawix-app", "external evidence schema: wrong repo scope");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(schema.properties?.laneId?.enum?.includes(rowId), `external evidence schema: missing lane ${rowId}`);
  }
  for (const required of [
    "schemaVersion",
    "conversationId",
    "planId",
    "laneId",
    "repoScope",
    "runAuthorization",
    "preflight",
    "execution",
    "evidence",
    "redaction",
    "closureImpact",
    "reviewer",
  ]) {
    assert(schema.required?.includes(required), `external evidence schema: missing required field ${required}`);
  }
  assert(schema.properties?.preflight?.properties?.command?.pattern === "^claw system ", "external evidence schema: preflight command must be claw system");
  assert(schema.properties?.preflight?.properties?.failClosedBeforeApproval?.const === true, "external evidence schema: preflight must fail closed before approval");
  assert(schema.properties?.execution?.properties?.externalPendingCleared?.const === true, "external evidence schema: accepted execution must clear external pending");
  assert(schema.properties?.execution?.properties?.failedApprovedRun?.const === false, "external evidence schema: failed approved run cannot be accepted");
  assert(schema.properties?.evidence?.properties?.auditEventRefs?.minItems === 1, "external evidence schema: audit refs must be required evidence");
  assert(schema.properties?.redaction?.properties?.containsSecrets?.const === false, "external evidence schema: secrets must be forbidden");
  assert(schema.properties?.redaction?.properties?.preciseLocationIncluded?.const === false, "external evidence schema: precise location must be forbidden");
  assert(schema.properties?.redaction?.properties?.privatePathsIncluded?.const === false, "external evidence schema: private paths must be forbidden");
  assert(schema.properties?.closureImpact?.properties?.requiresFinalSourceReread?.const === true, "external evidence schema: final source reread must be required");
  assert(schema.properties?.closureImpact?.properties?.requiresForbiddenNameScan?.const === true, "external evidence schema: forbidden-name scan must be required");
  for (const field of ["rowsToReplace", "completionAuditRows", "sourceQaRows", "manifestRows"]) {
    assert(schema.properties?.closureImpact?.properties?.[field]?.maxItems === 1, `external evidence schema: ${field} must be exact`);
  }
  assert(schema.properties?.runAuthorization?.properties?.grants?.maxItems === 1, "external evidence schema: run authorization grants must be exact");
  assert(schema.properties?.runAuthorization?.properties?.credentialLeaseRefs?.maxItems === 1, "external evidence schema: credential lease refs must be exact");
  const publicCredentialLeaseRef = assertPublicCredentialLeaseRefSchema(schema, "external evidence schema");
  assert(schema.properties?.runAuthorization?.properties?.credentialLeaseRefs?.items?.$ref === publicCredentialLeaseRef, "external evidence schema: credential lease refs must use public-safe refs");
  assert(schema.properties?.runAuthorization?.properties?.nativeGrantRefs?.maxItems === 1, "external evidence schema: native grant refs must be exact");
  assert(schema.properties?.runAuthorization?.properties?.locationGrantRefs?.maxItems === 1, "external evidence schema: location grant refs must be exact");
  assert(schema.properties?.runAuthorization?.properties?.hardwareProviderRefs?.maxItems === 1, "external evidence schema: hardware provider refs must be exact");
  assert(schema.properties?.runAuthorization?.properties?.signedAppRefs?.maxItems === 1, "external evidence schema: signed app refs must be exact");
  assert(schema.properties?.reviewer?.properties?.decision?.enum?.includes("accepted"), "external evidence schema: reviewer acceptance must be explicit");
  for (const snippet of [
    "receiptRefs",
    "locationGrantRefs",
    "hardwareProviderRefs",
    "signedAppRefs",
    "monitorSampleIds",
    "sameMachineEvidenceRefs",
    "appMenuEvidenceRefs",
    "physicalValidationRefs",
    "rollbackOrContinuityRefs",
  ]) {
    assert(serialized.includes(snippet), `external evidence schema: missing ${snippet}`);
  }
  const laneRules = new Map((schema.allOf ?? []).map((rule) => [rule.if?.properties?.laneId?.const, rule.then]));
  assert(laneRules.size === 3, "external evidence schema: must define exactly 3 lane-specific rules");
  const sensorRule = laneRules.get("CLX-SYS-TEL-EXT-003");
  assert(sensorRule?.properties?.runAuthorization?.properties?.grants?.contains?.const === "system.sensor.read", "external evidence schema: sensor lane must require sensor grant");
  assert(sensorRule?.properties?.runAuthorization?.properties?.grants?.maxItems === 1, "external evidence schema: sensor lane grants must be exact");
  assert(sensorRule?.properties?.runAuthorization?.properties?.nativeGrantRefs?.minItems === 1, "external evidence schema: sensor lane must require native grant refs");
  assert(sensorRule?.properties?.runAuthorization?.properties?.nativeGrantRefs?.maxItems === 1, "external evidence schema: sensor lane native grant refs must be exact");
  assert(sensorRule?.properties?.runAuthorization?.properties?.hardwareProviderRefs?.minItems === 1, "external evidence schema: sensor lane must require hardware provider refs");
  assert(sensorRule?.properties?.runAuthorization?.properties?.hardwareProviderRefs?.maxItems === 1, "external evidence schema: sensor lane hardware provider refs must be exact");
  assert(sensorRule?.properties?.runAuthorization?.properties?.signedAppRefs?.minItems === 1, "external evidence schema: sensor lane must require signed app refs");
  assert(sensorRule?.properties?.runAuthorization?.properties?.signedAppRefs?.maxItems === 1, "external evidence schema: sensor lane signed app refs must be exact");
  assert(sensorRule?.properties?.evidence?.properties?.monitorSampleIds?.minItems === 1, "external evidence schema: sensor lane must require monitor samples");
  assert(sensorRule?.properties?.evidence?.properties?.sameMachineEvidenceRefs?.minItems === 1, "external evidence schema: sensor lane must require same-machine evidence");
  assert(sensorRule?.properties?.evidence?.properties?.appMenuEvidenceRefs?.minItems === 1, "external evidence schema: sensor lane must require app/menu evidence");
  assert(sensorRule?.properties?.closureImpact?.properties?.completionAuditRows?.contains?.const === "CLX-STA-014", "external evidence schema: sensor lane must close CLX-STA-014");
  assert(sensorRule?.properties?.closureImpact?.properties?.sourceQaRows?.contains?.const === "CLX-STQA-003", "external evidence schema: sensor lane must update source Q/A row");
  const liveRule = laneRules.get("CLX-SYS-TEL-EXT-004");
  assert(liveRule?.properties?.runAuthorization?.properties?.grants?.contains?.const === "context.weather.read", "external evidence schema: live lane must require context grant");
  assert(liveRule?.properties?.runAuthorization?.properties?.grants?.maxItems === 1, "external evidence schema: live lane grants must be exact");
  assert(liveRule?.properties?.runAuthorization?.properties?.credentialLeaseRefs?.minItems === 1, "external evidence schema: live lane must require credential lease refs");
  assert(liveRule?.properties?.runAuthorization?.properties?.credentialLeaseRefs?.maxItems === 1, "external evidence schema: live lane credential lease refs must be exact");
  assert(liveRule?.properties?.runAuthorization?.properties?.locationGrantRefs?.minItems === 1, "external evidence schema: live lane must require location grant refs");
  assert(liveRule?.properties?.runAuthorization?.properties?.locationGrantRefs?.maxItems === 1, "external evidence schema: live lane location grant refs must be exact");
  assert(liveRule?.properties?.runAuthorization?.properties?.signedAppRefs?.minItems === 1, "external evidence schema: live lane must require signed app refs");
  assert(liveRule?.properties?.runAuthorization?.properties?.signedAppRefs?.maxItems === 1, "external evidence schema: live lane signed app refs must be exact");
  assert(liveRule?.properties?.runAuthorization?.properties?.networkAccessApproved?.const === true, "external evidence schema: live lane must require network approval");
  assert(liveRule?.properties?.evidence?.properties?.monitorSampleIds?.minItems === 1, "external evidence schema: live lane must require monitor samples");
  assert(liveRule?.properties?.evidence?.properties?.appMenuEvidenceRefs?.minItems === 1, "external evidence schema: live lane must require app/menu evidence");
  assert(liveRule?.properties?.closureImpact?.properties?.completionAuditRows?.contains?.const === "CLX-STA-015", "external evidence schema: live lane must close CLX-STA-015");
  assert(liveRule?.properties?.closureImpact?.properties?.sourceQaRows?.contains?.const === "CLX-STQA-003", "external evidence schema: live lane must update source Q/A row");
  const controlRule = laneRules.get("CLX-SYS-TEL-EXT-005");
  assert(controlRule?.properties?.runAuthorization?.properties?.grants?.contains?.const === "system.control.execute", "external evidence schema: control lane must require control grant");
  assert(controlRule?.properties?.runAuthorization?.properties?.grants?.maxItems === 1, "external evidence schema: control lane grants must be exact");
  assert(controlRule?.properties?.runAuthorization?.properties?.nativeGrantRefs?.minItems === 1, "external evidence schema: control lane must require native grant refs");
  assert(controlRule?.properties?.runAuthorization?.properties?.nativeGrantRefs?.maxItems === 1, "external evidence schema: control lane native grant refs must be exact");
  assert(controlRule?.properties?.runAuthorization?.properties?.signedAppRefs?.minItems === 1, "external evidence schema: control lane must require signed app refs");
  assert(controlRule?.properties?.runAuthorization?.properties?.signedAppRefs?.maxItems === 1, "external evidence schema: control lane signed app refs must be exact");
  assert(controlRule?.properties?.evidence?.properties?.appMenuEvidenceRefs?.minItems === 1, "external evidence schema: control lane must require app/menu evidence");
  assert(controlRule?.properties?.evidence?.properties?.physicalValidationRefs?.minItems === 1, "external evidence schema: control lane must require physical validation");
  assert(controlRule?.properties?.evidence?.properties?.rollbackOrContinuityRefs?.minItems === 1, "external evidence schema: control lane must require rollback or continuity evidence");
  assert(controlRule?.properties?.closureImpact?.properties?.completionAuditRows?.contains?.const === "CLX-STA-016", "external evidence schema: control lane must close CLX-STA-016");
  assert(controlRule?.properties?.closureImpact?.properties?.sourceQaRows?.contains?.const === "CLX-STQA-003", "external evidence schema: control lane must update source Q/A row");
  assert(!serialized.includes("/Users/"), "external evidence schema: must not publish private filesystem paths");
}

function evidenceTemplateErrors(packet, validate, ajv) {
  const errors = [];
  errors.push(...publicSafetyErrors(packet));
  if (!validate(packet)) errors.push(ajv.errorsText(validate.errors));
  const approvedAt = Date.parse(packet.runAuthorization?.approvedAt);
  const preflightCompletedAt = Date.parse(packet.preflight?.completedAt);
  const executionStartedAt = Date.parse(packet.execution?.startedAt);
  const executionCompletedAt = Date.parse(packet.execution?.completedAt);
  const reviewedAt = Date.parse(packet.reviewer?.reviewedAt);
  if (!Number.isFinite(approvedAt)) errors.push("runAuthorization.approvedAt must be parseable");
  if (!Number.isFinite(preflightCompletedAt)) errors.push("preflight.completedAt must be parseable");
  if (!Number.isFinite(executionStartedAt)) errors.push("execution.startedAt must be parseable");
  if (!Number.isFinite(executionCompletedAt)) errors.push("execution.completedAt must be parseable");
  if (!Number.isFinite(reviewedAt)) errors.push("reviewer.reviewedAt must be parseable");
  if (Number.isFinite(approvedAt) && Number.isFinite(preflightCompletedAt) && preflightCompletedAt < approvedAt) {
    errors.push("preflight.completedAt must be at or after runAuthorization.approvedAt");
  }
  if (Number.isFinite(preflightCompletedAt) && Number.isFinite(executionStartedAt) && executionStartedAt < preflightCompletedAt) {
    errors.push("execution.startedAt must be at or after preflight.completedAt");
  }
  if (Number.isFinite(executionStartedAt) && Number.isFinite(executionCompletedAt) && executionCompletedAt < executionStartedAt) {
    errors.push("execution.completedAt must be at or after execution.startedAt");
  }
  if (Number.isFinite(executionCompletedAt) && Number.isFinite(reviewedAt) && reviewedAt < executionCompletedAt) {
    errors.push("reviewer.reviewedAt must be at or after execution.completedAt");
  }
  return errors;
}

function mutateEvidenceTemplate(packet, mutation) {
  if (!packet) return undefined;
  const mutated = JSON.parse(JSON.stringify(packet));
  switch (mutation) {
    case "execution.completedAt before execution.startedAt":
      mutated.execution.completedAt = "2026-05-19T23:59:59Z";
      break;
    case "preflight.completedAt before runAuthorization.approvedAt":
      mutated.preflight.completedAt = "2026-05-19T23:59:59Z";
      break;
    case "runAuthorization.grants is empty":
      mutated.runAuthorization.grants = [];
      break;
    case "runAuthorization.grants has extra":
      mutated.runAuthorization.grants = [mutated.runAuthorization.grants[0], "extra_unapproved_grant_template"];
      break;
    case "runAuthorization.credentialLeaseRefs has extra":
      mutated.runAuthorization.credentialLeaseRefs = [mutated.runAuthorization.credentialLeaseRefs[0], "extra_lease_template"];
      break;
    case "runAuthorization.nativeGrantRefs has extra":
      mutated.runAuthorization.nativeGrantRefs = [mutated.runAuthorization.nativeGrantRefs[0], "extra_native_grant_template"];
      break;
    case "runAuthorization.locationGrantRefs is empty":
      mutated.runAuthorization.locationGrantRefs = [];
      break;
    case "runAuthorization.hardwareProviderRefs is empty":
      mutated.runAuthorization.hardwareProviderRefs = [];
      break;
    case "runAuthorization.signedAppRefs is empty":
      mutated.runAuthorization.signedAppRefs = [];
      break;
    case "reviewer.reviewedAt before execution.completedAt":
      mutated.reviewer.reviewedAt = "2026-05-19T23:59:59Z";
      break;
    case "evidence.appMenuEvidenceRefs=privatePath":
      mutated.evidence.appMenuEvidenceRefs = ["file://private/menu-evidence-template.png"];
      break;
    case "closureImpact.rowsToReplace=extra":
      mutated.closureImpact.rowsToReplace = [mutated.laneId, "CLX-SYS-TEL-EXT-999"];
      break;
    default:
      return undefined;
  }
  return mutated;
}

function assertExternalEvidenceFixtures() {
  const fixtures = readJson("docs/governance/system-telemetry/external-evidence.fixtures.json");
  assert(fixtures.schemaVersion === 1, "external evidence fixtures: schemaVersion must be 1");
  assert(fixtures.artifactId === "clawix-system-telemetry-external-evidence-fixtures", "external evidence fixtures: wrong artifact id");
  assert(fixtures.status === "synthetic_templates_not_evidence", "external evidence fixtures: must be synthetic templates only");
  assert(fixtures.conversationId === "source:system-telemetry", "external evidence fixtures: wrong conversation id");
  assert(fixtures.planId === "plan:system-telemetry", "external evidence fixtures: wrong plan id");
  assert(fixtures.schemaPath === "docs/governance/system-telemetry/external-evidence.schema.json", "external evidence fixtures: wrong schema path");
  assert(Array.isArray(fixtures.validSyntheticPackets) && fixtures.validSyntheticPackets.length === 3, "external evidence fixtures: must contain 3 valid synthetic packets");
  assert(Array.isArray(fixtures.invalidSyntheticPackets) && fixtures.invalidSyntheticPackets.length === 15, "external evidence fixtures: must contain 15 invalid synthetic packets");
  const schema = readJson("docs/governance/system-telemetry/external-evidence.schema.json");
  const ajv = new Ajv2020({ allErrors: true, validateFormats: false, strict: false });
  const validate = ajv.compile(schema);
  const validLaneIds = new Set();
  for (const packet of fixtures.validSyntheticPackets) {
    const errors = evidenceTemplateErrors(packet, validate, ajv);
    assert(errors.length === 0, `external evidence fixtures: valid packet ${packet.laneId} must validate: ${errors.join("; ")}`);
    validLaneIds.add(packet.laneId);
    assert(packet.redaction?.containsSecrets === false, `external evidence fixtures: ${packet.laneId} must not contain secrets`);
    assert(packet.redaction?.preciseLocationIncluded === false, `external evidence fixtures: ${packet.laneId} must not contain precise location`);
    assert(packet.redaction?.privatePathsIncluded === false, `external evidence fixtures: ${packet.laneId} must not contain private paths`);
  }
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(validLaneIds.has(rowId), `external evidence fixtures: missing valid template for ${rowId}`);
  }
  for (const fixture of fixtures.invalidSyntheticPackets) {
    const base = fixtures.validSyntheticPackets.find((packet) => packet.laneId === fixture.baseLaneId);
    const packet = fixture.packet ?? mutateEvidenceTemplate(base, fixture.mutation);
    assert(packet, `external evidence fixtures: invalid packet ${fixture.id} must provide packet or valid mutation`);
    assert(evidenceTemplateErrors(packet, validate, ajv).length > 0, `external evidence fixtures: invalid packet ${fixture.id} must fail validation`);
    assert(typeof fixture.mutation === "string" && fixture.mutation.length > 0, `external evidence fixtures: invalid packet ${fixture.id} must document mutation`);
  }
  const serialized = JSON.stringify(fixtures);
  assert(!serialized.includes("/Users/"), "external evidence fixtures: must not publish private filesystem paths");
}

function assertExternalEvidenceValidator() {
  const output = run(process.execPath, ["scripts/validate-system-telemetry-external-evidence.mjs", "--fixtures"]);
  const result = JSON.parse(output);
  assert(result.ok === true, "external evidence validator: fixture validation must pass");
  assert(result.status === "synthetic_templates_not_evidence", "external evidence validator: fixtures must remain synthetic");
  assert(result.validSyntheticPackets === 3, "external evidence validator: must accept 3 valid synthetic packets");
  assert(result.invalidSyntheticPackets === 15, "external evidence validator: must reject 15 invalid synthetic packets");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(result.accepted?.includes(rowId), `external evidence validator: missing accepted fixture for ${rowId}`);
  }
}

function assertExternalClosureFixtures() {
  const fixtures = readJson("docs/governance/system-telemetry/external-closure.fixtures.json");
  assert(fixtures.schemaVersion === 1, "external closure fixtures: schemaVersion must be 1");
  assert(fixtures.artifactId === "clawix-system-telemetry-external-closure-fixtures", "external closure fixtures: wrong artifact id");
  assert(fixtures.status === "synthetic_templates_not_closure", "external closure fixtures: must be synthetic templates only");
  assert(fixtures.conversationId === "source:system-telemetry", "external closure fixtures: wrong conversation id");
  assert(fixtures.planId === "plan:system-telemetry", "external closure fixtures: wrong plan id");
  assert(fixtures.approvalFixturesPath === "docs/governance/system-telemetry/external-approval.fixtures.json", "external closure fixtures: wrong approval fixtures path");
  assert(fixtures.evidenceFixturesPath === "docs/governance/system-telemetry/external-evidence.fixtures.json", "external closure fixtures: wrong evidence fixtures path");
  assert(fixtures.validatorPath === "scripts/validate-system-telemetry-external-closure.mjs", "external closure fixtures: wrong validator path");
  assert(Array.isArray(fixtures.validSyntheticBundles) && fixtures.validSyntheticBundles.length === 3, "external closure fixtures: must contain 3 valid synthetic bundles");
  assert(Array.isArray(fixtures.invalidSyntheticMutations) && fixtures.invalidSyntheticMutations.length === 20, "external closure fixtures: must contain 20 invalid mutations");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(fixtures.validSyntheticBundles.some((bundle) => bundle.laneId === rowId), `external closure fixtures: missing valid bundle for ${rowId}`);
  }
  for (const fixture of fixtures.invalidSyntheticMutations) {
    assert(typeof fixture.baseLaneId === "string" && fixture.baseLaneId.startsWith("CLX-SYS-TEL-EXT-"), `external closure fixtures: invalid mutation ${fixture.id} must name base app lane`);
    assert(typeof fixture.mutation === "string" && fixture.mutation.length > 0, `external closure fixtures: invalid mutation ${fixture.id} must document mutation`);
    assert(typeof fixture.reason === "string" && fixture.reason.length > 0, `external closure fixtures: invalid mutation ${fixture.id} must document reason`);
  }
  assert(!JSON.stringify(fixtures).includes("/Users/"), "external closure fixtures: must not publish private filesystem paths");
}

function assertExternalClosureValidator() {
  const output = run(process.execPath, ["scripts/validate-system-telemetry-external-closure.mjs", "--fixtures"]);
  const result = JSON.parse(output);
  assert(result.ok === true, "external closure validator: fixture validation must pass");
  assert(result.status === "synthetic_templates_not_closure", "external closure validator: fixtures must remain synthetic");
  assert(result.validSyntheticBundles === 3, "external closure validator: must accept 3 valid synthetic bundles");
  assert(result.invalidSyntheticMutations === 20, "external closure validator: must reject 20 invalid synthetic mutations");
  for (const rowId of ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"]) {
    assert(result.accepted?.includes(rowId), `external closure validator: missing accepted fixture for ${rowId}`);
  }
}

function assertSourceQaReview() {
  const review = readJson("docs/governance/system-telemetry/source-review.json");
  assert(review.schemaVersion === 1, "source Q/A review: schemaVersion must be 1");
  assert(review.artifactId === "clawix-system-telemetry-source-qa-review", "source Q/A review: wrong artifactId");
  assert(review.discoveryTerms?.includes("system telemetry source Q/A review"), "source Q/A review: missing discovery term");
  assert(review.sourceConversationId === "source:system-telemetry", "source Q/A review: wrong sourceConversationId");
  assert(review.sourcePlanId === "plan:system-telemetry", "source Q/A review: wrong sourcePlanId");
  assert(review.sourceRef === "source-redacted", "source Q/A review: must not publish private source session path");
  assert(!JSON.stringify(review).includes("/Users/"), "source Q/A review: must not publish private filesystem paths");
  assert(review.status === "complete_with_external_pending", "source Q/A review: status must keep external blockers visible");
  assert(review.reviewedUserRoleMessages === 161, "source Q/A review: reviewed user-role message count drifted");
  assert(review.decisionBearingRowsReviewed === 12, "source Q/A review: decision-bearing row count drifted");
  const decisionIds = ["D01", "D02", "D03", "D04", "D05", "D06", "D07", "D08", "D09", "D10", "D11"];
  assertSameStringSet(review.decisionIdsReviewed, decisionIds, "source Q/A review: decisionIdsReviewed");
  for (const decisionId of decisionIds) {
    assert(review.decisionIdsReviewed?.includes(decisionId), `source Q/A review: missing ${decisionId}`);
  }
  const externalRows = ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"];
  assertSameStringSet(review.externalPendingRows, externalRows, "source Q/A review: externalPendingRows");
  for (const rowId of externalRows) {
    assert(review.externalPendingRows?.includes(rowId), `source Q/A review: missing external-pending ${rowId}`);
  }
  const localRows = ["CLX-SYS-TEL-EXT-001", "CLX-SYS-TEL-EXT-002", "CLX-SYS-TEL-EXT-006"];
  assertSameStringSet(review.validatedLocalRows, localRows, "source Q/A review: validatedLocalRows");
  for (const rowId of localRows) {
    assert(review.validatedLocalRows?.includes(rowId), `source Q/A review: missing validated-local ${rowId}`);
  }
  assert(Array.isArray(review.rows) && review.rows.length === 12, "source Q/A review: must contain exactly 12 reviewed source rows");
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
    ["CLX-STQA-011", "USER_113", 25003],
    ["CLX-STQA-012", "USER_151", 33114],
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
  assert(review.completionPolicy?.requiresCompletionAudit === true, "source Q/A review: completion audit must be required");
  assert(review.completionPolicy?.requiresForbiddenNameScan === true, "source Q/A review: forbidden-name scan must be required");
  assert(review.completionPolicy?.externalPendingBlocksCompletion === true, "source Q/A review: external pending must block completion");
}

function assertCompletionAudit() {
  const text = read("docs/governance/system-telemetry/completion.md");
  for (const snippet of [
    "Source conversation: `source:system-telemetry`",
    "Plan item: `plan:system-telemetry`",
    "Status: `active_goal_not_complete`",
    "This public-safe Clawix audit mirrors the framework system telemetry goal",
    "- `validated-local`: 12 rows.",
    "- `active-closure-gate`: 1 row.",
    "- `external-pending`: 3 rows, `CLX-STA-014`, `CLX-STA-015`, and `CLX-STA-016`.",
    "| CLX-STA-001 | Consume the framework `claw system` plane",
    "| CLX-STA-002 | Render multiple independent menu-bar indicators plus one combined item.",
    "| CLX-STA-003 | Support text, icon, gauge, sparkline, thresholds, provider rows, dropdown, toggles, and refresh behavior.",
    "| CLX-STA-004 | Record safe host telemetry into Monitor through the app path.",
    "| CLX-STA-005 | Display retained history and graph output from Monitor, not a parallel app store.",
    "| CLX-STA-006 | Decode CPU, GPU, memory, disk, network, power, process, display, audio, Bluetooth/peripheral, focus, notification, sensor, and weather/context metrics.",
    "| CLX-STA-007 | Preserve fail-closed provider and control planning with redacted audit metadata.",
    "| CLX-STA-008 | Keep host-specific menu configuration in Clawix while portable definitions stay in ClawJS.",
    "| CLX-STA-009 | Validate native menu-bar behavior through the signed app path.",
    "| CLX-STA-010 | Keep system telemetry discoverable from Clawix docs and verifiers.",
    "| CLX-STA-011 | Separate external prerequisites from bugs.",
    "| CLX-STA-012 | Re-read source decisions one by one before any completion claim.",
    "| CLX-STA-013 | Keep public materials free of disallowed third-party product names.",
    "| CLX-STA-014 | Surface physical sensor/fan values in the app/menu",
    "| CLX-STA-015 | Display live external context provider values in menu-bar widgets.",
    "| CLX-STA-016 | Execute dangerous controls from UI only through governed signed-host plans.",
    "2026-05-20 safe preflight with `willConnect=false`/`externalPending=true`",
    "2026-05-20 safe preflight returned `willExecute=false`/`externalPending=true`",
    "`CLX-SYS-TEL-EXT-003` requires compatible hardware/provider",
    "`CLX-SYS-TEL-EXT-004` requires approved provider access",
    "`CLX-SYS-TEL-EXT-005` requires exact approval",
    "The goal cannot be marked complete while any `external-pending` row remains",
    "`--safe-external-preflight-smoke` verifier mode proves the remaining lanes are",
    "but it is not external closure evidence",
  ]) {
    assert(text.includes(snippet), `docs/governance/system-telemetry/completion.md: missing ${JSON.stringify(snippet)}`);
  }
  const requirementRows = text.match(/^\| CLX-STA-\d{3} \|/gm) ?? [];
  assert(requirementRows.length === 16, "docs/governance/system-telemetry/completion.md: must contain exactly CLX-STA-001..CLX-STA-016 rows");
  const validatedRows = text.match(/^\| CLX-STA-\d{3} \|[^|]+\| validated-local \|/gm) ?? [];
  const activeRows = text.match(/^\| CLX-STA-\d{3} \|[^|]+\| active-closure-gate \|/gm) ?? [];
  const externalRows = text.match(/^\| CLX-STA-\d{3} \|[^|]+\| external-pending \|/gm) ?? [];
  assert(validatedRows.length === 12, "docs/governance/system-telemetry/completion.md: must contain exactly 12 validated-local rows");
  assert(activeRows.length === 1, "docs/governance/system-telemetry/completion.md: must contain exactly 1 active-closure-gate row");
  assert(externalRows.length === 3, "docs/governance/system-telemetry/completion.md: must contain exactly 3 external-pending rows");
  for (const rowId of ["CLX-STA-014", "CLX-STA-015", "CLX-STA-016"]) {
    assert(new RegExp(`^\\\\| ${rowId} \\\\|[^\\n]+\\\\| external-pending \\\\|`, "m").test(text), `docs/governance/system-telemetry/completion.md: ${rowId} must remain external-pending`);
  }
  assert(!text.includes("/Users/"), "docs/governance/system-telemetry/completion.md: must not publish private filesystem paths");
}

function assertDecisionMatrix() {
  const text = read("docs/governance/system-telemetry/decision-matrix.md");
  for (const snippet of [
    "Source conversation: `source:system-telemetry`",
    "Plan item: `plan:system-telemetry`",
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
    "docs/governance/system-telemetry/completion.md",
    "completion audit",
    "docs/governance/system-telemetry/external-validation-runbook.md",
    "external validation runbook",
    "docs/governance/system-telemetry/external-approval.schema.json",
    "synthetic approval templates",
    "docs/governance/system-telemetry/external-approval.fixtures.json",
    "approval validator",
    "scripts/validate-system-telemetry-external-approval.mjs",
    "approval schema",
    "approval fixture templates",
    "docs/governance/system-telemetry/external-evidence.schema.json",
    "evidence schema",
    "docs/governance/system-telemetry/external-evidence.fixtures.json",
    "synthetic fixture templates",
    "scripts/validate-system-telemetry-external-evidence.mjs",
    "evidence validator",
    "docs/governance/system-telemetry/external-closure.fixtures.json",
    "same-lane closure fixtures",
    "scripts/validate-system-telemetry-external-closure.mjs",
    "closure validator",
    "docs/governance/system-telemetry/external-validation.manifest.json",
    "docs/governance/system-telemetry/external-validation.manifest.schema.json",
    "manifest schema",
    "docs/governance/system-telemetry/external-validation.manifest.fixtures.json",
    "manifest fixtures",
    "external validation manifest",
    "docs/governance/system-telemetry/source-review.json",
    "source Q/A review",
    "`CLX-SYS-TEL-EXT-003`, `CLX-SYS-TEL-EXT-004`, or",
    "`CLX-SYS-TEL-EXT-005` remain `EXTERNAL PENDING` in the ledger or structured",
    "external-validation manifest",
    "reflected in `docs/governance/system-telemetry/source-review.json`",
    "The forbidden-name scan has not been repeated",
  ]) {
    assert(text.includes(snippet), `docs/governance/system-telemetry/decision-matrix.md: missing ${JSON.stringify(snippet)}`);
  }
  const decisionRows = text.match(/^\| D\d{2} \|/gm) ?? [];
  assert(decisionRows.length === 11, "docs/governance/system-telemetry/decision-matrix.md: must contain exactly D01-D11 decision rows");
  assert(!text.includes("/Users/"), "docs/governance/system-telemetry/decision-matrix.md: must not publish private filesystem paths");

  const decisionMap = read("docs/decision-map.md");
  for (const snippet of [
    "System telemetry, context widgets, Monitor-backed history, and menu-bar indicators",
    "docs/governance/system-telemetry/decision-matrix.md",
    "docs/governance/system-telemetry/completion.md",
    "docs/governance/system-telemetry/external-pending.md",
    "docs/governance/system-telemetry/external-validation-runbook.md",
    "docs/governance/system-telemetry/external-approval.schema.json",
    "docs/governance/system-telemetry/external-approval.fixtures.json",
    "scripts/validate-system-telemetry-external-approval.mjs",
    "docs/governance/system-telemetry/external-evidence.schema.json",
    "docs/governance/system-telemetry/external-evidence.fixtures.json",
    "scripts/validate-system-telemetry-external-evidence.mjs",
    "docs/governance/system-telemetry/external-closure.fixtures.json",
    "scripts/validate-system-telemetry-external-closure.mjs",
    "docs/governance/system-telemetry/external-validation.manifest.json",
    "docs/governance/system-telemetry/external-validation.manifest.schema.json",
    "docs/governance/system-telemetry/external-validation.manifest.fixtures.json",
    "docs/governance/system-telemetry/source-review.json",
    "node scripts/verify-system-telemetry-goal.mjs",
  ]) {
    assert(decisionMap.includes(snippet), `docs/decision-map.md: missing ${JSON.stringify(snippet)}`);
  }

  const registry = read("docs/discoverability.registry.json");
  for (const snippet of [
    "\"id\": \"clawix-system-telemetry-decision-matrix\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/decision-matrix.md\"",
    "\"query\": \"system telemetry decision matrix\"",
    "\"id\": \"clawix-system-telemetry-completion-audit\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/completion.md\"",
    "\"query\": \"system telemetry completion audit\"",
    "\"id\": \"clawix-system-telemetry-external-pending-ledger\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-pending.md\"",
    "\"query\": \"system telemetry external pending validation\"",
    "\"id\": \"clawix-system-telemetry-external-validation-manifest\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-validation.manifest.json\"",
    "\"query\": \"system telemetry external validation manifest\"",
    "\"id\": \"clawix-system-telemetry-external-validation-manifest-schema\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-validation.manifest.schema.json\"",
    "\"query\": \"system telemetry external validation manifest schema\"",
    "\"id\": \"clawix-system-telemetry-external-validation-manifest-fixtures\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-validation.manifest.fixtures.json\"",
    "\"query\": \"system telemetry external validation manifest fixtures\"",
    "\"id\": \"clawix-system-telemetry-external-validation-runbook\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-validation-runbook.md\"",
    "\"query\": \"system telemetry external validation runbook\"",
    "\"id\": \"clawix-system-telemetry-external-approval-schema\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-approval.schema.json\"",
    "\"query\": \"system telemetry external approval schema\"",
    "\"id\": \"clawix-system-telemetry-external-approval-fixtures\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-approval.fixtures.json\"",
    "\"query\": \"system telemetry external approval fixtures\"",
    "\"id\": \"clawix-system-telemetry-external-approval-validator\"",
    "\"canonicalSource\": \"scripts/validate-system-telemetry-external-approval.mjs\"",
    "\"query\": \"system telemetry external approval validator\"",
    "\"id\": \"clawix-system-telemetry-external-evidence-schema\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-evidence.schema.json\"",
    "\"query\": \"system telemetry external evidence schema\"",
    "\"id\": \"clawix-system-telemetry-external-evidence-fixtures\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-evidence.fixtures.json\"",
    "\"query\": \"system telemetry external evidence fixtures\"",
    "\"id\": \"clawix-system-telemetry-external-closure-fixtures\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/external-closure.fixtures.json\"",
    "\"query\": \"system telemetry external closure fixtures\"",
    "\"id\": \"clawix-system-telemetry-external-closure-validator\"",
    "\"canonicalSource\": \"scripts/validate-system-telemetry-external-closure.mjs\"",
    "\"query\": \"system telemetry external closure validator\"",
    "\"id\": \"clawix-system-telemetry-source-qa-review\"",
    "\"canonicalSource\": \"docs/governance/system-telemetry/source-review.json\"",
    "\"query\": \"system telemetry source Q/A review\"",
  ]) {
    assert(registry.includes(snippet), `docs/discoverability.registry.json: missing ${JSON.stringify(snippet)}`);
  }

  const router = read("docs/discoverability.md");
  for (const snippet of [
    "`clawix-system-telemetry-decision-matrix`",
    "[docs/governance/system-telemetry/decision-matrix.md](/governance/system-telemetry/decision-matrix)",
    "`clawix-system-telemetry-completion-audit`",
    "[docs/governance/system-telemetry/completion.md](/governance/system-telemetry/completion)",
    "`clawix-system-telemetry-external-pending-ledger`",
    "[docs/governance/system-telemetry/external-pending.md](/governance/system-telemetry/external-pending)",
    "`clawix-system-telemetry-external-validation-manifest`",
    "[docs/governance/system-telemetry/external-validation.manifest.json](/governance/system-telemetry/external-validation.manifest.json)",
    "`clawix-system-telemetry-external-validation-manifest-schema`",
    "[docs/governance/system-telemetry/external-validation.manifest.schema.json](/governance/system-telemetry/external-validation.manifest.schema.json)",
    "`clawix-system-telemetry-external-validation-manifest-fixtures`",
    "[docs/governance/system-telemetry/external-validation.manifest.fixtures.json](/governance/system-telemetry/external-validation.manifest.fixtures.json)",
    "`clawix-system-telemetry-external-validation-runbook`",
    "[docs/governance/system-telemetry/external-validation-runbook.md](/governance/system-telemetry/external-validation-runbook)",
    "`clawix-system-telemetry-external-approval-schema`",
    "[docs/governance/system-telemetry/external-approval.schema.json](/governance/system-telemetry/external-approval.schema.json)",
    "`clawix-system-telemetry-external-approval-fixtures`",
    "[docs/governance/system-telemetry/external-approval.fixtures.json](/governance/system-telemetry/external-approval.fixtures.json)",
    "`clawix-system-telemetry-external-approval-validator`",
    "`scripts/validate-system-telemetry-external-approval.mjs`",
    "`clawix-system-telemetry-external-evidence-schema`",
    "[docs/governance/system-telemetry/external-evidence.schema.json](/governance/system-telemetry/external-evidence.schema.json)",
    "`clawix-system-telemetry-external-evidence-fixtures`",
    "[docs/governance/system-telemetry/external-evidence.fixtures.json](/governance/system-telemetry/external-evidence.fixtures.json)",
    "`clawix-system-telemetry-external-closure-fixtures`",
    "[docs/governance/system-telemetry/external-closure.fixtures.json](/governance/system-telemetry/external-closure.fixtures.json)",
    "`clawix-system-telemetry-external-closure-validator`",
    "`scripts/validate-system-telemetry-external-closure.mjs`",
    "`clawix-system-telemetry-source-qa-review`",
    "[docs/governance/system-telemetry/source-review.json](/governance/system-telemetry/source-review.json)",
  ]) {
    assert(router.includes(snippet), `docs/discoverability.md: missing ${JSON.stringify(snippet)}`);
  }

  for (const snippet of [
    "requiresExactRunApprovalForExternalLanes",
    "same_machine_evidence",
    "physical_validation",
  ]) {
    requireSnippet("docs/governance/system-telemetry/external-validation.manifest.json", snippet);
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
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "private static let automaticHistoryMetricLimit = 3");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let menuBarWidgets = enabledWidgets.filter");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let panelWidgets = enabledWidgets.filter");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let historyWidgets = menuBarWidgets + panelWidgets.prefix(Self.automaticHistoryMetricLimit)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "widgets = menuBarWidgets");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "self.panelWidgets = panelWidgets");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "providers = await nextProviders");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "private static let historyRefreshInterval: TimeInterval = 60");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "guard !isRefreshing else { return }");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let nextHistories = await loadHistoriesIfNeeded");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "histories = nextHistories");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let orderedMetricKeys = widgets.filter { Self.supportsHistoryGraph($0) }.flatMap(\\.metricKeys)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let selectedMetricKeys = force");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "for metricKey in selectedMetricKeys");
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
  requireSnippet("macos/scripts/bundle_clawjs.sh", "packages/signals-core");
  requireSnippet("macos/scripts/bundle_clawjs.sh", "packages/signals");
  requireSnippet("macos/scripts/bundle_clawjs.sh", "deps[\"@clawjs/signals-core\"] = \"file:../signals-core\"");
  requireSnippet("macos/scripts/bundle_clawjs.sh", "FASTIFY_STAGE=\"$CACHE_ROOT/fastify-runtime\"");
}

function assertStatusItemAndRecorder() {
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func makeCombinedPanelItem() -> NSStatusItem");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func makeCombinedPanelMenu(model: SystemTelemetryMenuBarModel, title: String) -> NSMenu");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addProviderItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addWidgetConfigurationItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel) -> Bool");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addPanelItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel, currentWidgetID: String)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "let historyReader = SystemTelemetryHistoryReader()");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "bridge: .localStatusBridge(historyReader: historyReader)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "func activateFromUserSurface()");
  const telemetryStatusControllerText = read("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift");
  assert(
    !telemetryStatusControllerText.includes("ResourceSampler.startIfNeeded("),
    "SystemTelemetryStatusItemController must not start ResourceSampler; resource sampling is explicit diagnostics only"
  );
  assert(
    !telemetryStatusControllerText.includes("HangDetector.startFromDiagnosticsSurface()"),
    "SystemTelemetryStatusItemController must not start HangDetector; hang sampling is explicit diagnostics only"
  );
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "static func localStatusBridge(historyReader: SystemTelemetryHistoryReader? = nil)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let historyReader = historyReader ?? SystemTelemetryHistoryReader()");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "case (\"history\", \"get\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "historyReader.historyPayload");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addHistoryGraphItems(");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "NSMenuItem(title: \"\\(widget.title) history graph\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "SystemTelemetryHistoryGraphView(history: history, title: widget.title)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "let refresh = NSMenuItem(title: \"Refresh\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "await refreshNow(forceHistory: true)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "dependencies.recordIfDue(forceHistory)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryGraphView.swift", "final class SystemTelemetryHistoryGraphView: NSView");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryGraphView.swift", "setAccessibilityLabel(\"\\(title) history graph\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryGraphView.swift", "history.chart.points");

  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "final class SystemTelemetryMonitorRecorder");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"system\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"snapshot\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"--source\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"host\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"--record\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "func recordIfDue(now: Date = Date(), force: Bool = false)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "if !force, let lastAttemptAt");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "reason: \"minimum_interval\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "reason: \"host_command_unavailable\"");
  requireSnippet("macos/scripts/dev.sh", "Building claw-host for system telemetry");
  requireSnippet("macos/scripts/dev.sh", "$BUNDLE/Contents/MacOS/claw-host");
  requireSnippet("macos/scripts/build_release_app.sh", "Building claw-host (release)");
  requireSnippet("macos/scripts/build_release_app.sh", "$BUNDLE_DIR/Contents/MacOS/claw-host");
}

function assertSwiftTestCoverage() {
  const testFiles = [
    "macos/Tests/ClawixMeshTests/SystemTelemetryBridgeTests.swift",
    "macos/Tests/ClawixMeshTests/SystemTelemetryBridgeMenuBarTests.swift",
  ];
  const testCoverage = testFiles.map((file) => read(file)).join("\n");
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
    assert(testCoverage.includes(snippet), `${testFiles.join(", ")}: missing ${JSON.stringify(snippet)}`);
  }
}

function assertOptionalPreflight() {
  if (!args.has("--preflight")) return;
  const launcher = process.env.CLAWIX_APP_PREFLIGHT_SCRIPT ?? "";
  if (!fs.existsSync(launcher)) {
    fail("--preflight requested but CLAWIX_APP_PREFLIGHT_SCRIPT is unavailable");
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
    clickCombinedMenuRefresh();
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

function assertOptionalSafeExternalPreflightSmoke() {
  if (!args.has("--safe-external-preflight-smoke")) return;

  const sensorPlan = runClawJson(["system", "providers", "plan", "system.sensors.signed", "--json"]);
  assert(sensorPlan.ok === true, "safe external preflight: signed sensor provider plan must succeed");
  assert(sensorPlan.data?.provider?.id === "system.sensors.signed", "safe external preflight: signed sensor provider id mismatch");
  assert(sensorPlan.data?.willConnect === false, "safe external preflight: signed sensor plan must not connect");
  assert(sensorPlan.data?.externalPending === true, "safe external preflight: signed sensor plan must remain external pending");
  assert(sensorPlan.data?.broker?.failClosed === true, "safe external preflight: signed sensor broker must fail closed");
  assert(sensorPlan.data?.policy?.requiredGrants?.includes("system.sensor.read"), "safe external preflight: signed sensor plan must require system.sensor.read");
  assert(sensorPlan.data?.provider?.metrics?.includes("system.sensor.temperature"), "safe external preflight: signed sensor plan must expose temperature metric");
  assert(sensorPlan.data?.provider?.metrics?.includes("system.sensor.fan_speed"), "safe external preflight: signed sensor plan must expose fan speed metric");
  assert(sensorPlan.data?.receipt?.status === "not_issued", "safe external preflight: signed sensor plan must not issue execution receipt");
  assert(sensorPlan.data?.auditPlan?.outcome === "blocked", "safe external preflight: signed sensor audit plan must be blocked");

  const weatherPlan = runClawJson(["system", "providers", "plan", "context.weather.live", "--json"]);
  assert(weatherPlan.ok === true, "safe external preflight: live weather provider plan must succeed");
  assert(weatherPlan.data?.provider?.id === "context.weather.live", "safe external preflight: live weather provider id mismatch");
  assert(weatherPlan.data?.willConnect === false, "safe external preflight: live weather plan must not connect");
  assert(weatherPlan.data?.externalPending === true, "safe external preflight: live weather plan must remain external pending");
  assert(weatherPlan.data?.broker?.failClosed === true, "safe external preflight: live weather broker must fail closed");
  assert(weatherPlan.data?.policy?.credentialRefRequired === true, "safe external preflight: live weather plan must require credential ref");
  assert(weatherPlan.data?.policy?.networkAccess === "blocked_until_granted", "safe external preflight: live weather network access must be blocked until granted");
  assert(weatherPlan.data?.policy?.requiredGrants?.includes("weather.location.read"), "safe external preflight: live weather plan must require location grant");
  assert(weatherPlan.data?.provider?.metrics?.includes("context.weather.temperature"), "safe external preflight: live weather plan must expose weather temperature metric");
  assert(weatherPlan.data?.receipt?.status === "not_issued", "safe external preflight: live weather plan must not issue execution receipt");
  assert(weatherPlan.data?.auditPlan?.outcome === "blocked", "safe external preflight: live weather audit plan must be blocked");

  const controlsList = runClawJson(["system", "controls", "list", "--json"]);
  assert(controlsList.ok === true, "safe external preflight: controls list must succeed");
  assert(controlsList.data?.mutatesHardware === false, "safe external preflight: controls list must not mutate hardware");
  assert(controlsList.data?.execution === "plan_first_signed_host_only", "safe external preflight: controls list must stay plan-first");
  const controlIds = new Set((controlsList.data?.controls ?? []).map((control) => control.id));
  for (const controlId of ["system.fan.set_speed", "system.power.sleep", "system.process.terminate", "system.network.toggle_interface"]) {
    assert(controlIds.has(controlId), `safe external preflight: controls list missing ${controlId}`);
  }

  const controlPlan = runClawJson(["system", "controls", "plan", "system.power.sleep", "--json"]);
  assert(controlPlan.ok === true, "safe external preflight: power sleep control plan must succeed");
  assert(controlPlan.data?.action?.id === "system.power.sleep", "safe external preflight: power sleep control id mismatch");
  assert(controlPlan.data?.willExecute === false, "safe external preflight: power sleep plan must not execute");
  assert(controlPlan.data?.externalPending === true, "safe external preflight: power sleep plan must remain external pending");
  assert(controlPlan.data?.broker?.failClosed === true, "safe external preflight: power sleep broker must fail closed");
  assert(controlPlan.data?.policy?.requiresConfirmation === true, "safe external preflight: power sleep plan must require confirmation");
  assert(controlPlan.data?.policy?.requiredGrants?.includes("system.power.control"), "safe external preflight: power sleep plan must require power control grant");
  assert(controlPlan.data?.steps?.some((step) => step.id === "execute_native_action" && step.status === "blocked"), "safe external preflight: power sleep native execution step must be blocked");
  assert(controlPlan.data?.receipt?.status === "not_issued", "safe external preflight: power sleep plan must not issue execution receipt");
  assert(controlPlan.data?.auditPlan?.outcome === "blocked", "safe external preflight: power sleep audit plan must be blocked");
}

function main() {
  seedLocalMonitorHistory();
  assertNoForbiddenPublicNames();
  assertExternalPendingLedger();
  assertExternalValidationManifest();
  assertExternalValidationManifestSchema();
  assertExternalValidationManifestFixtures();
  assertExternalValidationRunbook();
  assertExternalApprovalSchema();
  assertExternalApprovalFixtures();
  assertExternalApprovalValidator();
  assertExternalEvidenceSchema();
  assertExternalEvidenceFixtures();
  assertExternalEvidenceValidator();
  assertExternalClosureFixtures();
  assertExternalClosureValidator();
  assertSourceQaReview();
  assertCompletionAudit();
  assertDecisionMatrix();
  assertBridgeContracts();
  assertStatusItemAndRecorder();
  assertSwiftTestCoverage();
  assertOptionalPreflight();
  assertOptionalSwiftTests();
  assertOptionalAccessibilitySmoke();
  assertOptionalLiveRecorderSmoke();
  assertOptionalSafeExternalPreflightSmoke();

  if (errors.length) {
    console.error(`Clawix system telemetry goal verifier failed with ${errors.length} issue(s):`);
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.log("Clawix system telemetry goal verifier passed.");
}

main();
