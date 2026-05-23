#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = path.join(rootDir, "docs/governance/mesh-route-classification.json");
const persistentManifestPaths = [
  "docs/persistent-surface-clawix.manifest.json",
  "macos/Sources/Clawix/Resources/persistent-surface-clawix.manifest.json",
];

const allowedClassifications = new Set([
  "host_local_bridge_helper",
  "framework_projection",
  "compatibility_adapter",
  "retired",
]);

const requiredCanonCommands = new Set([
  "claw inspect route remote.chatGateway --json",
  "claw inspect route gateway.headlessAgentHost --json",
  "claw inspect route mesh.resourceShare --json",
  "claw remote contracts --json",
  "claw remote pending --json",
]);

const remoteMeshBoundaryTest = "swift test --package-path macos/Helpers/Bridged --filter RemoteMeshHTTPControllerBoundaryTests";

function readText(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function routeKey(method, route) {
  return `${method.toUpperCase()} ${normalizeRoute(route)}`;
}

function normalizeRoute(route) {
  return route
    .replace(/:id\b/g, "{nodeId}")
    .replace(/:jobId\b/g, "{jobId}")
    .replace(/\{id\}/g, "{nodeId}")
    .replace(/\/$/, "");
}

function swiftInterpolationToRoute(pathFragment) {
  return `/v1${pathFragment}`
    .replace(/\\\((nodeId)\)/g, "{$1}")
    .replace(/\\\((id)\)/g, "{jobId}");
}

function extractStableRoutes() {
  const text = readText("packages/ClawixCore/Sources/ClawixCore/StableSurfaceValues.swift");
  const block = text.match(/public enum ClawixMeshRoute \{([\s\S]*?)\n\}/)?.[1] ?? "";
  const nameToRoute = new Map();
  for (const match of block.matchAll(/public static let (\w+) = "([^"]+)"/g)) {
    const [, name, route] = match;
    if (name === "prefix") continue;
    nameToRoute.set(name, name === "jobsPrefix" ? "/v1/mesh/jobs/{jobId}" : route);
  }
  return nameToRoute;
}

function extractControllerRoutes(nameToRoute) {
  const text = readText("macos/Helpers/Bridged/Sources/clawix-bridge/RemoteMeshHTTPController.swift");
  const routes = new Set();
  for (const match of text.matchAll(/case \("([A-Z]+)", ClawixMeshRoute\.(\w+)\)/g)) {
    const [, method, name] = match;
    if (nameToRoute.has(name)) routes.add(routeKey(method, nameToRoute.get(name)));
  }
  for (const match of text.matchAll(/case \("([A-Z]+)", let path\) where path\.hasPrefix\(ClawixMeshRoute\.(\w+)\)/g)) {
    const [, method, name] = match;
    if (nameToRoute.has(name)) routes.add(routeKey(method, nameToRoute.get(name)));
  }
  return routes;
}

function extractPersistentRegistryRoutes() {
  const text = readText("macos/Sources/Clawix/Persistence/PersistentSurfaceRegistry.swift");
  const routes = new Set();
  for (const match of text.matchAll(/\("mesh", "([A-Z]+)", "([^"]+)",/g)) {
    routes.add(routeKey(match[1], match[2]));
  }
  return routes;
}

function extractPersistentManifestRoutes(relativePath) {
  const manifest = JSON.parse(readText(relativePath));
  const routes = new Set();
  for (const route of manifest.routes ?? []) {
    if (route.route?.startsWith("/v1/mesh/") && route.method) {
      routes.add(routeKey(route.method, route.route));
    }
  }
  for (const node of manifest.nodes ?? []) {
    if (node.route?.startsWith("/v1/mesh/") && node.method) {
      routes.add(routeKey(node.method, node.route));
    }
  }
  return routes;
}

function extractPersistentManifestRouteSets() {
  return persistentManifestPaths.map((relativePath) => ({
    relativePath,
    routes: extractPersistentManifestRoutes(relativePath),
  }));
}

function extractMeshClientRoutes() {
  const text = readText("macos/Sources/Clawix/Bridge/MeshClient.swift");
  const routes = new Set();
  const marker = "\\(ClawixPersistentSurfaceKeys.publicApiPrefix)";
  for (const line of text.split(/\r?\n/)) {
    const call = line.match(/\b(get|post|postEmpty|delete)\("/);
    if (!call) continue;
    const markerIndex = line.indexOf(marker);
    if (markerIndex === -1) continue;
    const routeMatch = line.slice(markerIndex + marker.length).match(/^(\/mesh\/[^"]*)/);
    if (!routeMatch) continue;
    const method = ({ get: "GET", post: "POST", postEmpty: "POST", delete: "DELETE" })[call[1]];
    routes.add(routeKey(method, swiftInterpolationToRoute(routeMatch[1])));
  }
  return routes;
}

function expectedRouteKeys() {
  const stable = extractStableRoutes();
  return new Set([
    ...extractControllerRoutes(stable),
    ...extractPersistentRegistryRoutes(),
    ...extractMeshClientRoutes(),
  ]);
}

function validateManifest(
  manifest,
  expected = expectedRouteKeys(),
  persistentSets = extractPersistentManifestRouteSets(),
) {
  const errors = [];
  if (manifest.schemaVersion !== 1) errors.push("schemaVersion must be 1");
  if (manifest.sourcePlan !== "docs/plans/remote-route-port-refactor-plan.md") {
    errors.push("sourcePlan must point to docs/plans/remote-route-port-refactor-plan.md");
  }
  if (!manifest.reviewedAt || Number.isNaN(Date.parse(manifest.reviewedAt))) {
    errors.push("reviewedAt must be a valid date");
  }
  if (!Array.isArray(manifest.routes) || manifest.routes.length === 0) {
    errors.push("routes must be a non-empty array");
  }

  const canonCommands = new Set((manifest.canonicalSources ?? []).map((source) => source.command).filter(Boolean));
  for (const command of requiredCanonCommands) {
    if (!canonCommands.has(command)) errors.push(`missing canonical source command: ${command}`);
  }

  const rows = new Map();
  for (const [index, route] of (manifest.routes ?? []).entries()) {
    const label = route.id ?? `routes[${index}]`;
    const key = route.method && route.route ? routeKey(route.method, route.route) : null;
    if (!route.id) errors.push(`${label}: missing id`);
    if (!route.method || !/^(GET|POST|DELETE|PUT|PATCH)$/.test(route.method)) errors.push(`${label}: invalid method`);
    if (!route.route?.startsWith("/v1/mesh/")) errors.push(`${label}: route must start with /v1/mesh/`);
    if (!allowedClassifications.has(route.classification)) errors.push(`${label}: invalid classification`);
    if (!route.currentOwner || !route.targetOwner) errors.push(`${label}: missing currentOwner or targetOwner`);
    if (!route.migrationState) errors.push(`${label}: missing migrationState`);
    if (!Array.isArray(route.currentImplementationRefs) || route.currentImplementationRefs.length === 0) errors.push(`${label}: missing currentImplementationRefs`);
    if (!Array.isArray(route.currentClientRefs) || route.currentClientRefs.length === 0) errors.push(`${label}: missing currentClientRefs`);
    if (!Array.isArray(route.targetContractRefs) || route.targetContractRefs.length === 0) errors.push(`${label}: missing targetContractRefs`);
    if (!Array.isArray(route.currentBehaviorTests) || route.currentBehaviorTests.length === 0) errors.push(`${label}: missing currentBehaviorTests`);
    if (!Array.isArray(route.targetBehaviorTests) || route.targetBehaviorTests.length === 0) errors.push(`${label}: missing targetBehaviorTests`);
    if (!route.securityPosture?.access || !route.securityPosture?.notes) errors.push(`${label}: missing securityPosture access or notes`);
    if (!Array.isArray(route.externalPending)) errors.push(`${label}: externalPending must be an array`);
    const implementedByRemoteMeshController = route.currentImplementationRefs?.some((ref) => ref.endsWith("RemoteMeshHTTPController.swift"));
    if (implementedByRemoteMeshController) {
      if (!route.currentBehaviorTests.some((ref) => ref === remoteMeshBoundaryTest)) {
        errors.push(`${label}: RemoteMeshHTTPController route needs network boundary test evidence`);
      }
    }

    if (route.classification === "compatibility_adapter") {
      if (!route.expiresAt || Number.isNaN(Date.parse(route.expiresAt))) errors.push(`${label}: compatibility_adapter needs a valid expiresAt`);
      if (route.expiresAt && manifest.reviewedAt && Date.parse(route.expiresAt) <= Date.parse(manifest.reviewedAt)) {
        errors.push(`${label}: compatibility_adapter expiresAt must be after reviewedAt`);
      }
      if (!Array.isArray(route.replacementEvidence) || route.replacementEvidence.length === 0) {
        errors.push(`${label}: compatibility_adapter needs replacementEvidence`);
      }
      if (!route.targetContractRefs.some((ref) => /remote\.chatGateway|gateway\.headlessAgentHost|mesh\.resourceShare|remote\.secretBrokeredOperation|jobs\.(stream|start|cancel)|@clawjs\/(mesh|runtime)/.test(ref))) {
        errors.push(`${label}: compatibility_adapter needs a ClawJS replacement contract ref`);
      }
      if (/runtime_or_gateway_job_projection/.test(route.migrationState)) {
        if (!route.targetContractRefs.some((ref) => /jobs\.stream|jobs\.cancel|jobs\.start|@clawjs\/runtime/.test(ref))) {
          errors.push(`${label}: runtime job compatibility_adapter needs a runtime jobs replacement ref`);
        }
        if (!route.replacementEvidence.some((ref) => /clawjs-runtime|runtime\/jobs/.test(ref))) {
          errors.push(`${label}: runtime job compatibility_adapter needs runtime jobs replacement evidence`);
        }
      }
      if (!route.externalPending.length) errors.push(`${label}: compatibility_adapter needs external pending evidence`);
    }

    if (route.classification === "retired") {
      if (!Array.isArray(route.replacementEvidence) || route.replacementEvidence.length === 0) {
        errors.push(`${label}: retired route needs replacementEvidence`);
      }
      if (!route.targetBehaviorTests.some((ref) => /removal|retir|delete|absen|guard|classification/i.test(ref))) {
        errors.push(`${label}: retired route needs targetBehaviorTests that prove removal or absence`);
      }
    }

    if (route.classification === "host_local_bridge_helper") {
      if (!["loopback", "pairing_token", "bearer_or_pairing_metadata"].includes(route.securityPosture?.access)) {
        errors.push(`${label}: host_local_bridge_helper must declare loopback, pairing_token, or bearer_or_pairing_metadata access`);
      }
      if (route.targetOwner !== "clawjs") errors.push(`${label}: host-local route still needs targetOwner clawjs for shared route projection`);
    }

    if (key) {
      if (rows.has(key)) errors.push(`${label}: duplicate route key ${key}`);
      rows.set(key, route);
    }
  }

  for (const key of expected) {
    if (!rows.has(key)) errors.push(`missing classification for discovered route: ${key}`);
  }
  for (const key of rows.keys()) {
    if (!expected.has(key)) errors.push(`manifest contains route not discovered in Clawix mesh surfaces: ${key}`);
  }

  if (persistentSets.length > 0) {
    const baseline = persistentSets[0];
    for (const entry of persistentSets) {
      for (const key of baseline.routes) {
        if (!entry.routes.has(key)) errors.push(`${entry.relativePath}: missing persistent mesh route from ${baseline.relativePath}: ${key}`);
      }
      for (const key of entry.routes) {
        if (!baseline.routes.has(key)) errors.push(`${entry.relativePath}: extra persistent mesh route not in ${baseline.relativePath}: ${key}`);
        if (!rows.has(key)) errors.push(`${entry.relativePath}: persistent mesh route lacks classification: ${key}`);
      }
    }
  }

  return errors;
}

function loadManifest(filePath = manifestPath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function runSelfTest() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-mesh-route-classification-"));
  try {
    const expected = new Set([routeKey("POST", "/v1/mesh/jobs")]);
    const valid = {
      schemaVersion: 1,
      sourcePlan: "docs/plans/remote-route-port-refactor-plan.md",
      reviewedAt: "2026-05-23",
      canonicalSources: [...requiredCanonCommands].map((command) => ({ kind: "clawjs_route_graph", command })),
      routes: [
        {
          id: "test.mesh.jobs.post",
          method: "POST",
          route: "/v1/mesh/jobs",
          classification: "compatibility_adapter",
          currentOwner: "clawix",
          targetOwner: "clawjs",
          migrationState: "replace_with_gateway_remote_job_contract",
          expiresAt: "2026-07-15",
          currentImplementationRefs: ["server.swift"],
          currentClientRefs: ["client.swift"],
          targetContractRefs: ["remote.chatGateway"],
          replacementEvidence: ["claw inspect route remote.chatGateway --json"],
          currentBehaviorTests: ["current", remoteMeshBoundaryTest],
          targetBehaviorTests: ["target"],
          securityPosture: { access: "signed_encrypted_peer", notes: "signed" },
          externalPending: ["agent_runtime_execution"]
        }
      ]
    };
    const persistentSets = [
      { relativePath: "docs/persistent-surface-clawix.manifest.json", routes: new Set([routeKey("POST", "/v1/mesh/jobs")]) },
      { relativePath: "macos/Sources/Clawix/Resources/persistent-surface-clawix.manifest.json", routes: new Set([routeKey("POST", "/v1/mesh/jobs")]) },
    ];
    assert.deepEqual(validateManifest(valid, expected, persistentSets), []);
    const invalid = structuredClone(valid);
    invalid.routes[0].route = "/v1/mesh/unclassified";
    invalid.routes[0].expiresAt = "";
    invalid.routes[0].replacementEvidence = [];
    const errors = validateManifest(invalid, expected, persistentSets);
    assert(errors.some((error) => error.includes("missing classification for discovered route")));
    assert(errors.some((error) => error.includes("contains route not discovered")));
    assert(errors.some((error) => error.includes("valid expiresAt")));
    assert(errors.some((error) => error.includes("replacementEvidence")));
    const invalidRuntime = structuredClone(valid);
    invalidRuntime.routes[0].migrationState = "replace_with_runtime_or_gateway_job_projection";
    invalidRuntime.routes[0].targetContractRefs = ["remote.chatGateway"];
    invalidRuntime.routes[0].replacementEvidence = ["claw inspect route remote.chatGateway --json"];
    const runtimeErrors = validateManifest(invalidRuntime, expected, persistentSets);
    assert(runtimeErrors.some((error) => error.includes("runtime jobs replacement ref")));
    assert(runtimeErrors.some((error) => error.includes("runtime jobs replacement evidence")));
    const invalidPersistent = structuredClone(valid);
    const persistentErrors = validateManifest(invalidPersistent, expected, [
      { relativePath: "docs/persistent-surface-clawix.manifest.json", routes: new Set([routeKey("POST", "/v1/mesh/jobs")]) },
      { relativePath: "macos/Sources/Clawix/Resources/persistent-surface-clawix.manifest.json", routes: new Set([routeKey("POST", "/v1/mesh/jobs"), routeKey("POST", "/v1/mesh/jobs/events")]) },
    ]);
    assert(persistentErrors.some((error) => error.includes("extra persistent mesh route")));
    assert(persistentErrors.some((error) => error.includes("persistent mesh route lacks classification")));
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
  console.error("mesh route classification self-test passed");
}

function main() {
  if (process.argv.includes("--self-test")) {
    runSelfTest();
    return;
  }

  const errors = validateManifest(loadManifest());
  if (errors.length > 0) {
    console.error("mesh route classification check failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.error("mesh route classification check passed");
}

main();
