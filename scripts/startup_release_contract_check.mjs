#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const errors = [];
const isSelfTest = process.env.CLAWIX_STARTUP_RELEASE_CONTRACT_SELF_TEST === "1";
const allowedFlags = new Set([
  "--require-approved",
  "--current",
  "--simulate-missing-startup-flow",
  "--simulate-missing-p95",
  "--simulate-missing-private-alias",
  "--simulate-premature-enforcement",
  "--simulate-stale-approved-baseline",
  "--require-launch-evidence",
]);

let currentEvidenceArg = "";
for (let i = 0; i < rawArgs.length; i += 1) {
  const arg = rawArgs[i];
  if (arg === "--current") {
    currentEvidenceArg = rawArgs[i + 1] || "";
    i += 1;
    continue;
  }
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`startup release contract check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const content = read(relativePath);
  if (!content) return null;
  try {
    return JSON.parse(content);
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function readJsonFile(file, label) {
  if (!file || !fs.existsSync(file)) {
    fail(`${label} is missing`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function requireExact(values, label, expected) {
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must contain non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
    if (!expected.includes(value)) fail(`${label} must not include ${value}`);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
}

function privateReferenceSuffix(reference, alias, label) {
  if (typeof reference !== "string" || reference.length === 0) {
    fail(`${label} must be a private baseline alias reference`);
    return null;
  }
  const prefix = `${alias}:`;
  if (!reference.startsWith(prefix)) {
    fail(`${label} must start with ${prefix}`);
    return null;
  }
  const suffix = reference.slice(prefix.length);
  if (
    suffix.length === 0 ||
    suffix.startsWith("/") ||
    suffix.startsWith("~") ||
    suffix.includes("\\") ||
    suffix.split("/").includes("..") ||
    suffix.split("/").includes(".")
  ) {
    fail(`${label} must be a relative private alias suffix`);
    return null;
  }
  return suffix;
}

function hasLocalPath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
}

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (hasLocalPath(value)) fail(`${label} must not contain a local path`);
}

function metricAt(packet, name) {
  const [mode, metric] = name.split(".");
  return packet?.metrics?.[mode]?.[metric];
}

function validateEvidence(packet, label, manifest, { requireApproval = false } = {}) {
  const approvalFields = new Set(["approvedByUserAt", "approvedScope"]);
  const requiredFields = requireApproval
    ? manifest.flow.requiredEvidenceFields
    : manifest.flow.requiredEvidenceFields.filter((field) => !approvalFields.has(field));
  requireFields(packet, label, requiredFields);
  if (packet?.flowId !== manifest.flow.id) fail(`${label}.flowId must be ${manifest.flow.id}`);
  if (packet?.platform !== "macos") fail(`${label}.platform must be macos`);
  if (packet?.privateBaselineReference !== manifest.privateBaselineReference) {
    fail(`${label}.privateBaselineReference must match ${manifest.privateBaselineReference}`);
  }
  for (const metricName of manifest.flow.requiredMetrics) {
    const value = metricAt(packet, metricName);
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
      fail(`${label}.metrics must include numeric ${metricName}`);
    }
  }
  const completeness = packet?.milestoneCompleteness || {};
  for (const milestone of manifest.flow.requiredMilestones) {
    if (completeness[milestone] !== true) {
      fail(`${label}.milestoneCompleteness.${milestone} must be true`);
    }
  }
}

function compareAgainstBaseline(current, baseline, manifest) {
  const limits = baseline.budgets || baseline.metrics || {};
  for (const metricName of manifest.flow.requiredMetrics) {
    const [mode, metric] = metricName.split(".");
    const currentValue = current?.metrics?.[mode]?.[metric];
    const limit = limits?.[mode]?.[metric];
    if (typeof currentValue !== "number" || typeof limit !== "number") continue;
    if (currentValue > limit) {
      fail(`${metricName} regression: current ${currentValue}ms exceeds approved budget ${limit}ms`);
    }
  }
}

function valueText(value) {
  if (typeof value === "string") return value;
  if (value && typeof value === "object") {
    return [
      value.command,
      value.executable,
      value.path,
      value.name,
      value.argv,
      value.args,
    ].flat().filter(Boolean).join(" ");
  }
  return String(value ?? "");
}

function evidenceArray(packet, fields) {
  for (const field of fields) {
    if (Array.isArray(packet?.[field])) return packet[field];
  }
  return [];
}

function validateLaunchDependencyEvidence(packet) {
  requireFields(packet, "launch dependency evidence", ["flowId", "platform", "capturedWindow"]);
  if (packet?.flowId !== "macos-startup-first-chat-interactive") {
    fail("launch dependency evidence.flowId must be macos-startup-first-chat-interactive");
  }
  if (packet?.platform !== "macos") fail("launch dependency evidence.platform must be macos");
  if (packet?.capturedWindow !== "initial-window-before-route-demand") {
    fail("launch dependency evidence.capturedWindow must be initial-window-before-route-demand");
  }

  const forbiddenProcessFragments = [
    "Contents/Resources/clawjs/node",
    "node_modules/@clawjs/runtime",
    "node_modules/@clawjs/search",
    "node_modules/@clawjs/database",
    "node_modules/@clawjs/local-data",
    "node_modules/@clawjs/domain-pack-dense-data",
    "open runtime",
    "open sessions",
    "open database",
    "open index",
  ];
  for (const processInfo of evidenceArray(packet, ["processes", "processTable", "childProcesses"])) {
    const text = valueText(processInfo);
    for (const fragment of forbiddenProcessFragments) {
      if (text.includes(fragment)) fail(`launch dependency evidence must not include early heavy process ${fragment}`);
    }
  }

  for (const portInfo of evidenceArray(packet, ["ports", "listeningPorts", "listeners"])) {
    const raw = typeof portInfo === "number" ? portInfo : portInfo?.port ?? portInfo?.localPort ?? portInfo?.listenPort;
    const port = Number(raw);
    if (Number.isInteger(port) && port >= 24100 && port <= 24199) {
      fail(`launch dependency evidence must not include early ClawJS service port ${port}`);
    }
  }

  const forbiddenPathFragments = [
    "runtime.sqlite",
    "sessions.sqlite",
    "index.sqlite",
    "search.sqlite",
    "core.sqlite",
    "/Search/",
    "/Runtime/",
    "/Sessions/",
    "/Index/",
  ];
  for (const pathInfo of evidenceArray(packet, ["paths", "createdPaths", "openedPaths", "files"])) {
    const text = valueText(pathInfo);
    for (const fragment of forbiddenPathFragments) {
      if (text.includes(fragment)) fail(`launch dependency evidence must not include early service storage ${fragment}`);
    }
  }
}

const manifestPath = "docs/performance/startup-release-contract.manifest.json";
const docPath = "docs/performance/startup-release-contract.md";
const manifest = readJson(manifestPath);
read(docPath);

if (args.has("--simulate-missing-startup-flow") && manifest?.flow) {
  manifest.flow.id = "macos-startup";
}
if (args.has("--simulate-missing-p95") && Array.isArray(manifest?.flow?.requiredMetrics)) {
  manifest.flow.requiredMetrics = manifest.flow.requiredMetrics.filter((metric) => metric !== "warm.p95Ms");
}
if (args.has("--simulate-missing-private-alias") && manifest) {
  manifest.privateBaselineAlias = "";
}
if (args.has("--simulate-premature-enforcement") && manifest) {
  manifest.status = "approved-baseline-enforced";
}

requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "platformScope",
  "flow",
  "privateBaselineAlias",
  "privateBaselineReference",
  "baselineFilename",
  "currentEvidenceEnv",
  "privateRootEnv",
  "verificationCommand",
  "publicFallback",
]);
if (manifest?.schemaVersion !== 1) fail(`${manifestPath}.schemaVersion must be 1`);
if (!["pending-approved-baseline-capture", "approved-baseline-enforced"].includes(manifest?.status)) {
  fail(`${manifestPath}.status must be pending-approved-baseline-capture or approved-baseline-enforced`);
}
if (manifest?.status === "approved-baseline-enforced" && !process.env[manifest?.privateRootEnv || ""]) {
  fail(`${manifestPath}.status cannot be approved-baseline-enforced without approved private baseline verification`);
}

requireExact(requireArray(manifest?.platformScope, `${manifestPath}.platformScope`, "covered"), `${manifestPath}.platformScope.covered`, ["macos"]);
requireExact(requireArray(manifest?.platformScope, `${manifestPath}.platformScope`, "future"), `${manifestPath}.platformScope.future`, ["ios", "android", "web"]);
requireFields(manifest?.flow, `${manifestPath}.flow`, [
  "id",
  "platform",
  "scope",
  "primaryDuration",
  "supportingDurations",
  "launchModes",
  "requiredMilestones",
  "requiredMetrics",
  "requiredEvidenceFields",
]);
if (manifest?.flow?.id !== "macos-startup-first-chat-interactive") {
  fail(`${manifestPath}.flow.id must be macos-startup-first-chat-interactive`);
}
if (manifest?.flow?.platform !== "macos") fail(`${manifestPath}.flow.platform must be macos`);
if (manifest?.flow?.scope !== "release") fail(`${manifestPath}.flow.scope must be release`);
if (manifest?.flow?.primaryDuration !== "process_start->first_chat_interactive") {
  fail(`${manifestPath}.flow.primaryDuration must be process_start->first_chat_interactive`);
}
requireExact(requireArray(manifest?.flow, `${manifestPath}.flow`, "launchModes"), `${manifestPath}.flow.launchModes`, ["cold", "warm"]);
requireExact(requireArray(manifest?.flow, `${manifestPath}.flow`, "requiredMilestones"), `${manifestPath}.flow.requiredMilestones`, [
  "process_start",
  "app_init_start",
  "app_init_end",
  "first_window",
  "first_sidebar_paint",
  "first_chat_interactive",
  "core_ready",
]);
requireExact(requireArray(manifest?.flow, `${manifestPath}.flow`, "requiredMetrics"), `${manifestPath}.flow.requiredMetrics`, [
  "cold.p50Ms",
  "cold.p95Ms",
  "warm.p50Ms",
  "warm.p95Ms",
]);
for (const field of [
  "flowId",
  "platform",
  "privateBaselineReference",
  "measurementSamples",
  "metrics",
  "milestoneCompleteness",
  "approvedByUserAt",
  "approvedScope",
]) {
  if (!manifest?.flow?.requiredEvidenceFields?.includes(field)) {
    fail(`${manifestPath}.flow.requiredEvidenceFields must include ${field}`);
  }
}

if (manifest?.privateBaselineAlias !== "private-codex-startup-baselines") {
  fail(`${manifestPath}.privateBaselineAlias must be private-codex-startup-baselines`);
}
const suffix = privateReferenceSuffix(
  manifest?.privateBaselineReference,
  manifest?.privateBaselineAlias,
  `${manifestPath}.privateBaselineReference`,
);
if (suffix && suffix !== "macos/startup-first-chat-interactive") {
  fail(`${manifestPath}.privateBaselineReference must resolve to macos/startup-first-chat-interactive`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/startup_release_contract_check.mjs --require-approved")) {
  fail(`${manifestPath}.verificationCommand must run scripts/startup_release_contract_check.mjs --require-approved`);
}
if (!String(manifest?.verificationCommand || "").includes("CLAWIX_STARTUP_PRIVATE_BASELINE_ROOT=<private-root>")) {
  fail(`${manifestPath}.verificationCommand must require CLAWIX_STARTUP_PRIVATE_BASELINE_ROOT`);
}
if (!String(manifest?.verificationCommand || "").includes("CLAWIX_STARTUP_CURRENT_EVIDENCE=<private-evidence-json>")) {
  fail(`${manifestPath}.verificationCommand must require CLAWIX_STARTUP_CURRENT_EVIDENCE`);
}
scanForLocalPaths(manifest, manifestPath);

const signpostSource = read("macos/Sources/Clawix/Diagnostics/Signposts.swift");
const milestoneSource = read("macos/Sources/Clawix/Diagnostics/LaunchMilestones.swift");
const appSource = read("macos/Sources/Clawix/App.swift");
const rootViewSource = read("macos/Sources/Clawix/SplashView.swift");
const sidebarSource = read("macos/Sources/Clawix/SidebarView.swift");
const composerSource = read("macos/Sources/Clawix/ComposerTextEditor.swift");
const startupSource = read("macos/Sources/Clawix/ClawJS/ClawJSServiceDemandPolicy.swift");
for (const snippet of [
  'case launch = "launch"',
  'case processStart = "process_start"',
  'case appInitStart = "app_init_start"',
  'case appInitEnd = "app_init_end"',
  'case firstWindow = "first_window"',
  'case firstSidebarPaint = "first_sidebar_paint"',
  'case firstChatInteractive = "first_chat_interactive"',
  'case coreReady = "core_ready"',
]) {
  if (!`${signpostSource}\n${milestoneSource}`.includes(snippet)) fail(`launch signpost source must include ${snippet}`);
}
for (const [sourceName, source, snippet] of [
  ["App.swift", appSource, "LaunchMilestones.mark(.processStart)"],
  ["App.swift", appSource, "LaunchMilestones.mark(.appInitStart)"],
  ["App.swift", appSource, "LaunchMilestones.mark(.appInitEnd)"],
  ["SplashView.swift", rootViewSource, "LaunchMilestones.mark(.firstWindow)"],
  ["SidebarView.swift", sidebarSource, "LaunchMilestones.mark(.firstSidebarPaint)"],
  ["ComposerTextEditor.swift", composerSource, "LaunchMilestones.mark(.firstChatInteractive)"],
  ["ClawJSServiceDemandPolicy.swift", startupSource, "LaunchMilestones.mark(.coreReady)"],
]) {
  if (!source.includes(snippet)) fail(`${sourceName} must emit ${snippet}`);
}

for (const snippet of [
  "static let startupCoreServices: Set<ClawJSService> = []",
  "case .home, .search",
  ".settings, .rescue",
  "return []",
  "case .chat:",
  "return [.runtime, .sessions]",
]) {
  if (!startupSource.includes(snippet)) fail(`ClawJSServiceDemandPolicy launch dependency budget must include ${snippet}`);
}
for (const forbidden of [
  "startupCoreServices: Set<ClawJSService> = [.runtime",
  "startupCoreServices: Set<ClawJSService> = [.sessions",
  "startupCoreServices: Set<ClawJSService> = [.database",
  "startupCoreServices: Set<ClawJSService> = [.index",
]) {
  if (startupSource.includes(forbidden)) fail(`ClawJSServiceDemandPolicy must not start heavy service at launch: ${forbidden}`);
}
if (!appSource.includes("ClawixStartupCore.run(role: ClawixAppRole.current)")) {
  fail("AppDelegate must start through ClawixStartupCore.run(role:) instead of direct service startup");
}
for (const forbidden of [
  "ClawJSServiceManager.shared.start([.runtime",
  "ClawJSServiceManager.shared.start([.sessions",
  "ClawJSServiceManager.shared.start([.database",
  "ClawJSServiceManager.shared.start([.index",
  "ClawJSServiceManager.shared.start(Set(ClawJSService.allCases)",
]) {
  if (appSource.includes(forbidden)) fail(`AppDelegate launch must not directly start heavy services: ${forbidden}`);
}

const launchEvidencePath = process.env.CLAWIX_LAUNCH_DEPENDENCY_EVIDENCE || "";
if (launchEvidencePath) {
  const launchEvidence = readJsonFile(launchEvidencePath, "CLAWIX_LAUNCH_DEPENDENCY_EVIDENCE");
  if (launchEvidence) validateLaunchDependencyEvidence(launchEvidence);
} else if (args.has("--require-launch-evidence")) {
  console.error("EXTERNAL PENDING launch dependency budget: CLAWIX_LAUNCH_DEPENDENCY_EVIDENCE is not set");
  process.exit(2);
}

const privateRoot = process.env[manifest?.privateRootEnv || ""] || "";
const requireApproved = args.has("--require-approved");
if (privateRoot) {
  const baselinePath = path.join(privateRoot, "macos", "startup-first-chat-interactive", manifest.baselineFilename);
  const baseline = readJsonFile(baselinePath, `${manifest.privateRootEnv} baseline`);
  if (args.has("--simulate-stale-approved-baseline") && baseline) {
    baseline.approvedScope = "wrong-flow";
  }
  if (baseline) {
    validateEvidence(baseline, "approved startup baseline", manifest, { requireApproval: true });
    if (baseline.baselineStatus !== "approved") fail("approved startup baseline.baselineStatus must be approved");
    if (baseline.approvedScope !== manifest.flow.id) {
      fail("approved startup baseline.approvedScope must match macos-startup-first-chat-interactive");
    }
    const currentPath = currentEvidenceArg || process.env[manifest.currentEvidenceEnv] || "";
    if (currentPath) {
      const current = readJsonFile(currentPath, manifest.currentEvidenceEnv);
      if (current) {
        validateEvidence(current, "current startup evidence", manifest);
        compareAgainstBaseline(current, baseline, manifest);
      }
    } else if (requireApproved) {
      fail(`${manifest.currentEvidenceEnv} is required for approved startup regression enforcement`);
    }
  }
} else if (requireApproved) {
  console.error("EXTERNAL PENDING startup release contract: CLAWIX_STARTUP_PRIVATE_BASELINE_ROOT is not set");
  process.exit(2);
}

if (errors.length === 0 && !isSelfTest && rawArgs.length === 0) {
  const scriptPath = path.relative(rootDir, new URL(import.meta.url).pathname);
  const staleRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-startup-contract."));
  const staleDir = path.join(staleRoot, "macos", "startup-first-chat-interactive");
  fs.mkdirSync(staleDir, { recursive: true });
  const baseline = {
    baselineStatus: "approved",
    flowId: "macos-startup-first-chat-interactive",
    platform: "macos",
    privateBaselineReference: "private-codex-startup-baselines:macos/startup-first-chat-interactive",
    bundleIdentifier: "redacted",
    bundleVersion: "1",
    gitHead: "abcdef0",
    appMode: "real",
    environmentHash: "sha256-test",
    measurementSamples: [{ mode: "cold", primaryMs: 100 }],
    metrics: {
      cold: { p50Ms: 100, p95Ms: 120 },
      warm: { p50Ms: 80, p95Ms: 90 },
    },
    milestoneCompleteness: Object.fromEntries(manifest.flow.requiredMilestones.map((milestone) => [milestone, true])),
    failures: [],
    timeouts: [],
    measuredAt: "2026-05-21T00:00:00Z",
    approvedByUserAt: "2026-05-21T00:00:00Z",
    approvedScope: "macos-startup-first-chat-interactive",
  };
  fs.writeFileSync(path.join(staleDir, manifest.baselineFilename), JSON.stringify(baseline, null, 2));
  for (const [flag, expectedOutput, env] of [
    ["--unknown-flag", "received unknown flag --unknown-flag", {}],
    ["--simulate-missing-startup-flow", "flow.id must be macos-startup-first-chat-interactive", {}],
    ["--simulate-missing-p95", "requiredMetrics must include warm.p95Ms", {}],
    ["--simulate-missing-private-alias", "privateBaselineAlias must be private-codex-startup-baselines", {}],
    ["--simulate-premature-enforcement", "status cannot be approved-baseline-enforced without approved private baseline verification", {}],
    ["--simulate-stale-approved-baseline", "approved startup baseline.approvedScope must match macos-startup-first-chat-interactive", { CLAWIX_STARTUP_PRIVATE_BASELINE_ROOT: staleRoot }],
  ]) {
    const result = spawnSync(process.execPath, [scriptPath, flag], {
      cwd: rootDir,
      encoding: "utf8",
      env: { ...process.env, ...env, CLAWIX_STARTUP_RELEASE_CONTRACT_SELF_TEST: "1" },
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0 || !output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
  fs.rmSync(staleRoot, { recursive: true, force: true });
}

if (errors.length > 0) {
  console.error("startup release contract check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (!privateRoot) {
  console.log("startup release contract check passed (EXTERNAL PENDING approved private baseline)");
} else {
  console.log("startup release contract check passed");
}
