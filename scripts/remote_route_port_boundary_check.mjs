#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const inventoryPath = path.join(rootDir, "docs/governance/remote-route-port-inventory.json");
const planPath = "docs/plans/remote-route-port-refactor-plan.md";

const scanRoots = [
  "macos",
  "ios",
  "packages",
  "linux",
  "windows",
  "web",
  "scripts",
  "docs",
  "qa",
  "playbooks",
];

const excludedPathFragments = [
  "/node_modules/",
  "/dist/",
  "/.build/",
  "/DerivedData/",
  "/__pycache__/",
  "/web-dist/",
  "/.playwright-cli/",
  "/artifacts/",
  "/test-results/",
];

const excludedBasenames = new Set([
  "Localizable.xcstrings",
]);

const excludedExactPaths = new Set([
  "docs/governance/remote-route-port-inventory.json",
]);

const binaryExtensions = new Set([
  ".a",
  ".app",
  ".bin",
  ".bmp",
  ".car",
  ".dmg",
  ".gif",
  ".heic",
  ".icns",
  ".ico",
  ".jpeg",
  ".jpg",
  ".mov",
  ".mp3",
  ".mp4",
  ".otf",
  ".pdf",
  ".png",
  ".sqlite",
  ".ttf",
  ".webp",
  ".xcarchive",
  ".zip",
]);

const tokenPattern = /\/v1\/(?:remote|gateway|sync|mesh)\/[A-Za-z0-9_./:{}-]*|https?:\/\/[A-Za-z0-9_./:!#$%&'()*+,;=?@~{}\\-]+|wss?:\/\/[A-Za-z0-9_./:!#$%&'()*+,;=?@~{}\\-]+|127\.0\.0\.1|localhost|24080|24081/g;

const routePattern = /\/v1\/(?:remote|gateway|sync|mesh)\/[A-Za-z0-9_./:{}-]*/;

const docsRouteAnchorPaths = [
  "docs/adr/0011-surface-route-graph.md",
  "docs/interface-matrix.md",
  "docs/decision-map.md",
  planPath,
];

const guardAndFixturePaths = [
  "scripts/persistent-surface-guard.mjs",
  "scripts/remote_canon_alignment_check.mjs",
  "scripts/remote_route_port_boundary_check.mjs",
  "scripts/clawjs_mirror_contradiction_check.mjs",
  "scripts/mesh_route_classification_check.mjs",
  "scripts/verify-sdk-first-custom-surfaces-goal.mjs",
];

const endpointResolverAllowlist = [
  "linux/app/src-tauri/src/bridge_endpoint.rs",
  "macos/Helpers/Bridged/Sources/clawix-bridge/OpenCodeDaemonEngineHost.swift",
  "packages/ClawixEngine/Sources/ClawixEngine/Audio/ClawJSAudioEndpointResolver.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSServiceEndpointResolver.swift",
  "packages/ClawixEngine/Sources/ClawixEngine/BridgeEndpointResolver.swift",
  "web/src/bridge/endpoint.ts",
  "windows/Clawix.App/Services/BridgeEndpoint.cs",
  "macos/Sources/Clawix/ClawJS/ClawJSServiceStatus.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSServiceEnvironmentBuilder.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSServiceLaunchAdapter.swift",
  "macos/Sources/Clawix/ClawJS/ClawJSServiceSupervisor.swift",
  "macos/Sources/Clawix/AppState.swift",
  "macos/Sources/Clawix/Bridge/BridgeAgentControl.swift",
  "macos/Sources/Clawix/Bridge/MeshClient.swift",
  "macos/Helpers/Bridged/Sources/clawix-bridge/main.swift",
  "packages/ClawixEngine/Sources/ClawixEngine/BridgeServerNIO.swift",
];

const declarativeLoopbackAllowlist = [
  "linux/app/src-tauri/tauri.conf.json",
];

const externalProviderLoopbackPaths = [
  "macos/Sources/Clawix/Providers/Backends/OllamaClient.swift",
  "packages/AIProviders/Sources/AIProviders/Catalog/CustomOpenAICompatCatalog.swift",
  "packages/AIProviders/Sources/AIProviders/Catalog/OllamaCatalog.swift",
];

const localizationResourcePattern = /^macos\/Sources\/Clawix\/Resources\/[^/]+\.lproj\/Localizable\.strings$/;

function normalizeRelative(filePath) {
  return filePath.split(path.sep).join("/");
}

function shouldExclude(relativePath) {
  const normalized = `/${relativePath}`;
  if (excludedExactPaths.has(relativePath)) return true;
  if (excludedBasenames.has(path.basename(relativePath))) return true;
  if (binaryExtensions.has(path.extname(relativePath))) return true;
  return excludedPathFragments.some((fragment) => normalized.includes(fragment));
}

function listFiles() {
  try {
    const output = execFileSync("rg", ["--files", ...scanRoots], {
      cwd: rootDir,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return output.split("\n").filter(Boolean).map(normalizeRelative).filter((file) => !shouldExclude(file)).sort();
  } catch {
    const files = [];
    for (const root of scanRoots) collectFiles(path.join(rootDir, root), root, files);
    return files.filter((file) => !shouldExclude(file)).sort();
  }
}

function collectFiles(absoluteDir, relativeDir, files) {
  if (!fs.existsSync(absoluteDir)) return;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = normalizeRelative(path.join(relativeDir, entry.name));
    if (shouldExclude(relativePath)) continue;
    const absolutePath = path.join(rootDir, relativePath);
    if (entry.isDirectory()) collectFiles(absolutePath, relativePath, files);
    else if (entry.isFile()) files.push(relativePath);
  }
}

function readText(relativePath) {
  try {
    const buffer = fs.readFileSync(path.join(rootDir, relativePath));
    if (buffer.includes(0)) return null;
    return buffer.toString("utf8");
  } catch {
    return null;
  }
}

function extractFindings(files = listFiles()) {
  const findings = [];
  for (const file of files) {
    const text = readText(file);
    if (text == null) continue;
    const lines = text.split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      const values = [...new Set([...line.matchAll(tokenPattern)].map((match) => match[0]))];
      for (const value of values) {
        const finding = classifyFinding({
          file,
          line: index + 1,
          column: line.indexOf(value) + 1,
          value,
          snippet: compactSnippet(line),
        });
        findings.push(finding);
      }
    }
  }
  return findings.sort(compareFindings);
}

function compactSnippet(line) {
  const trimmed = line.trim().replace(/\s+/g, " ");
  return trimmed.length <= 180 ? trimmed : `${trimmed.slice(0, 177)}...`;
}

function compareFindings(a, b) {
  return a.file.localeCompare(b.file)
    || a.line - b.line
    || a.column - b.column
    || a.value.localeCompare(b.value);
}

function classifyFinding(input) {
  const route = input.value.match(routePattern)?.[0] ?? null;
  const isDocs = input.file.startsWith("docs/")
    || input.file.startsWith("playbooks/")
    || input.file.endsWith("/README.md")
    || input.file === "README.md";
  const isTest = /(^|\/)(Tests?|tests?|Fixtures?|fixtures?|qa)(\/|$)/.test(input.file)
    || /(^|\/)[^/]*\.Tests\//.test(input.file);
  const isGuardFixture = guardAndFixturePaths.includes(input.file);
  const isDeclarativeLoopback = declarativeLoopbackAllowlist.includes(input.file);
  const isExternalProviderLoopback = externalProviderLoopbackPaths.includes(input.file);
  const isLocalizationResource = localizationResourcePattern.test(input.file);
  const isExternalUrl = /^(?:https?:\/\/|wss?:\/\/)/.test(input.value)
    && !input.value.includes("127.0.0.1")
    && !input.value.includes("localhost");

  let category = "service_endpoint";
  let steward = "clawix";
  let classification = null;
  let replacement = null;
  let validation = "remote_route_port_boundary_check";
  let allowedReason = "loopback endpoint literal inventoried for endpoint resolver migration";
  const violations = [];

  if (isExternalUrl) {
    category = "external_provider";
    steward = "external";
    allowedReason = "external provider or standards URL, not a Clawix route authority";
    validation = "public hygiene and provider-specific tests";
  }

  if (isExternalProviderLoopback) {
    category = "external_provider";
    steward = "external";
    allowedReason = "documented third-party local provider endpoint, not a Clawix route authority";
    validation = "provider catalog and backend tests";
  }

  if (isDocs || isLocalizationResource) {
    category = route && /\/v1\/(?:remote|gateway|sync)\//.test(route) ? "framework_remote_route" : "docs";
    steward = route && /\/v1\/(?:remote|gateway|sync)\//.test(route) ? "claw" : "clawix";
    allowedReason = isLocalizationResource
      ? "localized UI copy; not an executable Clawix route declaration"
      : "documentation or plan anchor; not an executable Clawix route declaration";
    validation = isLocalizationResource ? "localization review" : "docs alignment and remote canon checks";
  }

  if (isDeclarativeLoopback) {
    category = "host_leg";
    steward = "clawix";
    allowedReason = "declarative local development or CSP loopback policy, not runtime endpoint construction";
    validation = "Tauri configuration review and Linux smoke tests";
  }

  if (isTest || isGuardFixture) {
    category = "fixture";
    steward = "test";
    allowedReason = "fixture or guard example";
    validation = "self-test or focused unit test";
  }

  if (route?.startsWith("/v1/remote/") || route?.startsWith("/v1/gateway/") || route?.startsWith("/v1/sync/")) {
    category = "framework_remote_route";
    steward = "claw";
    replacement = "Consume via claw inspect remote, claw remote contracts, or framework projection payloads.";
    validation = "claw inspect remote --json and remote canon alignment";
    if (!isDocsRouteAnchor(input.file) && !isTest && !isGuardFixture) {
      violations.push("framework_remote_route_declared_outside_allowed_projection");
    }
  }

  if (route?.startsWith("/v1/mesh/")) {
    category = "mesh_route";
    steward = "clawix";
    const mesh = classifyMeshRoute(route);
    classification = mesh.classification;
    replacement = mesh.replacement;
    allowedReason = mesh.reason;
    validation = mesh.validation;
    if (classification === "unclassified" && !isDocs && !isTest && !isGuardFixture) {
      violations.push("unclassified_mesh_route");
    }
  }

  if (input.value === "24080" || input.value === "24081" || input.value.startsWith("ws://")) {
    category = category === "docs" || category === "fixture" ? category : "host_leg";
    steward = steward === "test" ? steward : "clawix";
    allowedReason = category === "host_leg"
      ? "approved local bridge transport or bridge HTTP helper literal"
      : allowedReason;
    validation = category === "host_leg" ? "bridge contract parity and demand-lease tests" : validation;
  }

  if (
    isLoopbackHttp(input.value)
    && !isDocs
    && !isLocalizationResource
    && !isTest
    && !isGuardFixture
    && !isDeclarativeLoopback
    && !isExternalProviderLoopback
    && !endpointResolverAllowlist.includes(input.file)
  ) {
    violations.push("ad_hoc_loopback_endpoint_outside_resolver_allowlist");
  }

  return {
    file: input.file,
    line: input.line,
    column: input.column,
    value: input.value,
    category,
    steward,
    route,
    classification,
    replacement,
    requiredValidation: validation,
    allowedReason,
    violations,
    snippet: input.snippet,
  };
}

function isDocsRouteAnchor(file) {
  return docsRouteAnchorPaths.includes(file) || file.startsWith("docs/governance/");
}

function isLoopbackHttp(value) {
  return /^(?:https?:\/\/|wss?:\/\/)/.test(value)
    && (value.includes("127.0.0.1") || value.includes("localhost"));
}

function classifyMeshRoute(route) {
  const normalized = route.replace(/\{[^}]+\}/g, ":id");
  const hostLocal = new Set([
    "/v1/mesh/",
    "/v1/mesh/identity",
    "/v1/mesh/peers",
    "/v1/mesh/workspaces",
    "/v1/mesh/link",
    "/v1/mesh/pair",
  ]);
  const compatibility = new Set([
    "/v1/mesh/jobs",
    "/v1/mesh/jobs/",
    "/v1/mesh/jobs/:id",
    "/v1/mesh/jobs/cancel",
    "/v1/mesh/jobs/events",
    "/v1/mesh/remote-jobs",
  ]);
  if (hostLocal.has(normalized)) {
    return {
      classification: "host_local_bridge_helper",
      replacement: "Retain only as private loopback bridge helper unless ClawJS promotes an equivalent node route.",
      reason: "current Clawix helper route for local bridge pairing, identity, peers, or workspace allowlist",
      validation: "mesh classification guard plus bridge/mesh loopback tests",
    };
  }
  if (compatibility.has(normalized)) {
    return {
      classification: "compatibility_adapter",
      replacement: "Migrate remote job behavior to ClawJS remote.chatGateway, gateway.headlessAgentHost, or mesh.resourceShare contracts.",
      reason: "temporary Clawix mesh job adapter; not a canonical framework remote contract",
      validation: "mesh compatibility tests plus ClawJS remote route contract checks",
    };
  }
  if (/^\/v1\/mesh\/hosts(?:\/:id)?(?:\/(?:revoke|unrevoke))?$/.test(normalized)) {
    return {
      classification: "compatibility_adapter",
      replacement: "Migrate host trust and revocation to ClawJS nodes trust/revoke/share contracts.",
      reason: "temporary host record adapter; must not become hidden trust authority",
      validation: "signed-host trust tests plus ClawJS nodes contract checks",
    };
  }
  if (/^\/v1\/mesh\/(?:invitations|shares|revocations)(?:\/.*)?$/.test(normalized)) {
    return {
      classification: "framework_projection",
      replacement: "Consume ClawJS mesh.resourceShare route contracts.",
      reason: "framework-owned mesh collaboration route anchor",
      validation: "claw inspect remote --json and claw remote contracts --json",
    };
  }
  return {
    classification: "unclassified",
    replacement: "Add route classification before accepting this route.",
    reason: "no approved Clawix/ClawJS route classification matched",
    validation: "remote_route_port_boundary_check",
  };
}

function buildInventory(files) {
  const findings = extractFindings(files);
  const violations = findings.flatMap((finding) => finding.violations.map((violation) => ({
    file: finding.file,
    line: finding.line,
    value: finding.value,
    violation,
  })));
  return {
    schemaVersion: 1,
    sourcePlan: planPath,
    scanRoots,
    excluded: {
      pathFragments: excludedPathFragments,
      exactPaths: [...excludedExactPaths].sort(),
      basenames: [...excludedBasenames].sort(),
      binaryExtensions: [...binaryExtensions].sort(),
    },
    policy: {
      defaultMode: "baseline_inventory",
      strictMode: "fails on current violations as well as inventory drift",
      noUnknownRows: true,
    },
    counts: {
      findings: findings.length,
      violations: violations.length,
      byCategory: countBy(findings, "category"),
      bySteward: countBy(findings, "steward"),
      byMeshClassification: countBy(findings.filter((finding) => finding.category === "mesh_route"), "classification"),
    },
    violations,
    findings,
  };
}

function countBy(items, key) {
  return Object.fromEntries([...items.reduce((map, item) => {
    const value = item[key] ?? "none";
    map.set(value, (map.get(value) ?? 0) + 1);
    return map;
  }, new Map())].sort(([a], [b]) => String(a).localeCompare(String(b))));
}

function stableJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function runSelfTest() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-route-boundary-"));
  const fixtures = {
    "docs/adr/0011-surface-route-graph.md": "GET /v1/remote/conformance is a docs anchor\n",
    "macos/Sources/Clawix/Settings/Remote.swift": "let route = \"/v1/remote/conformance\"\n",
    "macos/Sources/Clawix/Bridge/NewMesh.swift": "let route = \"/v1/mesh/new-route\"\n",
    "macos/Sources/Clawix/Feature/Client.swift": "let url = \"http://127.0.0.1:24100/v1/health\"\n",
    "macos/Sources/Clawix/Bridge/MeshClient.swift": "let route = \"/v1/mesh/jobs\"\n",
    "packages/AIProviders/Sources/AIProviders/Catalog/OllamaCatalog.swift": "let url = \"http://localhost:11434\"\n",
    "macos/Sources/Clawix/Resources/en.lproj/Localizable.strings": "\"example\" = \"Use http://localhost:9000/v1\";\n",
    "linux/app/src-tauri/tauri.conf.json": "{\"devUrl\":\"http://localhost:1420\",\"csp\":\"ws://127.0.0.1:*\"}\n",
  };
  for (const [file, text] of Object.entries(fixtures)) {
    const absolute = path.join(temp, file);
    fs.mkdirSync(path.dirname(absolute), { recursive: true });
    fs.writeFileSync(absolute, text);
  }
  const originalRoot = process.cwd();
  try {
    process.chdir(temp);
    const files = Object.keys(fixtures);
    const findings = extractFindingsFromRoot(temp, files);
    const violations = findings.flatMap((finding) => finding.violations.map((violation) => violation));
    assert(violations.includes("framework_remote_route_declared_outside_allowed_projection"));
    assert(violations.includes("unclassified_mesh_route"));
    assert(violations.includes("ad_hoc_loopback_endpoint_outside_resolver_allowlist"));
    assert(findings.some((finding) => finding.value === "/v1/mesh/jobs" && finding.classification === "compatibility_adapter"));
    assert(findings.some((finding) => finding.value === "/v1/remote/conformance" && finding.file.startsWith("docs/") && finding.violations.length === 0));
    assert(findings.some((finding) => finding.file.includes("OllamaCatalog.swift") && finding.category === "external_provider" && finding.violations.length === 0));
    assert(findings.some((finding) => finding.file.includes("Localizable.strings") && finding.category === "docs" && finding.violations.length === 0));
    assert(findings.some((finding) => finding.file.includes("tauri.conf.json") && finding.category === "host_leg" && finding.violations.length === 0));
  } finally {
    process.chdir(originalRoot);
    fs.rmSync(temp, { recursive: true, force: true });
  }
  console.error("remote route port boundary self-test passed");
}

function extractFindingsFromRoot(tempRoot, files) {
  return files.flatMap((file) => {
    const absolute = path.join(tempRoot, file);
    const text = fs.readFileSync(absolute, "utf8");
    return text.split(/\r?\n/).flatMap((line, index) => {
      const values = [...new Set([...line.matchAll(tokenPattern)].map((match) => match[0]))];
      return values.map((value) => classifyFinding({
        file,
        line: index + 1,
        column: line.indexOf(value) + 1,
        value,
        snippet: compactSnippet(line),
      }));
    });
  }).sort(compareFindings);
}

function main() {
  const args = new Set(process.argv.slice(2));
  if (args.has("--self-test")) {
    runSelfTest();
    return;
  }

  const inventory = buildInventory();
  const rendered = stableJson(inventory);

  if (args.has("--write")) {
    fs.mkdirSync(path.dirname(inventoryPath), { recursive: true });
    fs.writeFileSync(inventoryPath, rendered);
    console.error(`wrote ${path.relative(rootDir, inventoryPath)} (${inventory.counts.findings} findings, ${inventory.counts.violations} baseline violations)`);
    return;
  }

  if (!fs.existsSync(inventoryPath)) {
    console.error(`missing ${path.relative(rootDir, inventoryPath)}; run node scripts/remote_route_port_boundary_check.mjs --write`);
    process.exit(1);
  }

  const current = fs.readFileSync(inventoryPath, "utf8");
  if (current !== rendered) {
    console.error("remote route port inventory drift detected; run node scripts/remote_route_port_boundary_check.mjs --write and review changes");
    process.exit(1);
  }

  if (args.has("--strict") && inventory.violations.length > 0) {
    console.error(`remote route port strict check failed (${inventory.violations.length} violations)`);
    for (const violation of inventory.violations.slice(0, 50)) {
      console.error(`- ${violation.file}:${violation.line} ${violation.violation} ${violation.value}`);
    }
    process.exit(1);
  }

  console.error(`remote route port boundary check passed (${inventory.counts.findings} findings, ${inventory.counts.violations} baseline violations)`);
}

main();
