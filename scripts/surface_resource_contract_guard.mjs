#!/usr/bin/env node
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const persistentManifestPath = "docs/persistent-surface-clawix.manifest.json";
const interfaceRegistryPath = "docs/interface-surface-clawix.registry.json";
const baselinePath = path.join(rootDir, "docs/surface-resource-contract-clawix-baseline.json");
const today = new Date().toISOString().slice(0, 10);
const requiredFields = ["startup", "idle", "memory", "streaming", "storage", "hotPath", "scale", "validation"];

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function sha256Ids(ids) {
  return crypto.createHash("sha256").update([...ids].sort().join("\n")).digest("hex");
}

function sortedIds(ids) {
  return [...ids].sort();
}

function diffIds(actualIds, expectedIds) {
  const expected = new Set(expectedIds);
  const actual = new Set(actualIds);
  return {
    added: actualIds.filter((id) => !expected.has(id)),
    removed: expectedIds.filter((id) => !actual.has(id)),
  };
}

function hasText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function validateResourceContract(contract, label, failures) {
  if (!contract || typeof contract !== "object" || Array.isArray(contract)) {
    failures.push(`${label} is missing resourceContract`);
    return;
  }
  for (const field of requiredFields) {
    if (!hasText(contract[field])) failures.push(`${label}.resourceContract.${field} must be a non-empty string`);
  }
}

function missingResourceContractIds(items) {
  return items.filter((item) => !item.resourceContract).map((item) => item.id).sort();
}

function loadSurfaces() {
  const manifest = readJson(persistentManifestPath);
  const interfaceRegistry = readJson(interfaceRegistryPath);
  return {
    persistentNodes: manifest.nodes ?? [],
    routes: manifest.routes ?? [],
    interfaceSurfaces: interfaceRegistry.surfaces ?? [],
  };
}

function readBaseline() {
  if (!fs.existsSync(baselinePath)) return { version: 1, entries: [] };
  return JSON.parse(fs.readFileSync(baselinePath, "utf8"));
}

function baselineEntry(baseline) {
  return (baseline.entries ?? []).find((entry) => entry.id === "clawix.existing-surfaces-without-resource-contract");
}

function validateBaselineEnvelope(baseline) {
  const failures = [];
  if (baseline.version !== 1) failures.push("Clawix surface resource contract baseline version must be 1");
  for (const [index, entry] of (baseline.entries ?? []).entries()) {
    const label = entry.id ?? `<entry ${index + 1}>`;
    for (const field of ["id", "classification", "steward", "reason", "risk", "expires", "nextPhase", "reentryCondition"]) {
      if (!entry[field]) failures.push(`${label} is missing ${field}`);
    }
    if (!["lateral_debt", "pre_existing_dirty"].includes(entry.classification)) {
      failures.push(`${label} has invalid classification ${entry.classification}`);
    }
    if (entry.expires && entry.expires < today) failures.push(`${label} expired on ${entry.expires}`);
    for (const key of ["persistentNodes", "routes", "interfaceSurfaces"]) {
      const summary = entry.missingResourceContract?.[key];
      if (!summary || typeof summary.count !== "number" || !hasText(summary.idsSha256)) {
        failures.push(`${label}.missingResourceContract.${key} must include count, idsSha256, and ids`);
        continue;
      }
      if (!Array.isArray(summary.ids) || !summary.ids.every(hasText)) {
        failures.push(`${label}.missingResourceContract.${key}.ids must be an array of non-empty strings`);
        continue;
      }
      const ids = sortedIds(summary.ids);
      if (summary.ids.length !== summary.count) {
        failures.push(`${label}.missingResourceContract.${key}.count must equal ids.length`);
      }
      const idsHash = sha256Ids(ids);
      if (idsHash !== summary.idsSha256) {
        failures.push(`${label}.missingResourceContract.${key}.idsSha256 must match ids`);
      }
    }
  }
  return failures;
}

function compareMissingToBaseline(kind, ids, entry, failures) {
  const expected = entry?.missingResourceContract?.[kind];
  if (!expected) {
    failures.push(`missing resource contract baseline does not include ${kind}`);
    return;
  }
  const actualHash = sha256Ids(ids);
  if (ids.length !== expected.count || actualHash !== expected.idsSha256) {
    const expectedIds = Array.isArray(expected.ids) ? sortedIds(expected.ids) : [];
    const { added, removed } = diffIds(ids, expectedIds);
    failures.push(`${kind} without resourceContract baseline drift: expected ${expected.count}/${expected.idsSha256}, got ${ids.length}/${actualHash}`);
    if (added.length > 0) failures.push(`added missing ${kind}: ${added.join(", ")}`);
    if (removed.length > 0) failures.push(`removed missing ${kind}: ${removed.join(", ")}`);
  }
}

function validateSurfaceResourceContracts(surfaces = loadSurfaces(), baseline = readBaseline()) {
  const failures = [];
  failures.push(...validateBaselineEnvelope(baseline));
  for (const [kind, items] of Object.entries(surfaces)) {
    for (const item of items) {
      if (item.resourceContract) validateResourceContract(item.resourceContract, `${kind} ${item.id}`, failures);
    }
  }
  const entry = baselineEntry(baseline);
  if (!entry) {
    failures.push("surface resource contract baseline must include clawix.existing-surfaces-without-resource-contract");
  } else {
    for (const [kind, items] of Object.entries(surfaces)) {
      compareMissingToBaseline(kind, missingResourceContractIds(items), entry, failures);
    }
  }
  return failures;
}

function missingSummary(items) {
  const ids = missingResourceContractIds(items);
  return { count: ids.length, idsSha256: sha256Ids(ids), ids };
}

function buildBaseline(surfaces = loadSurfaces()) {
  return {
    version: 1,
    entries: [
      {
        id: "clawix.existing-surfaces-without-resource-contract",
        classification: "lateral_debt",
        steward: "clawix",
        reason: "Initial bounded baseline for Clawix manifest and interface surfaces that predate the resourceContract requirement.",
        risk: "Existing host/UI surfaces remain registered, but their startup, idle, memory, streaming, storage, hot-path, scale, and validation contract is not yet machine-checkable.",
        expires: "2026-08-18",
        missingResourceContract: {
          persistentNodes: missingSummary(surfaces.persistentNodes),
          routes: missingSummary(surfaces.routes),
          interfaceSurfaces: missingSummary(surfaces.interfaceSurfaces),
        },
        nextPhase: "Backfill resourceContract on high-change host, route, permission, stream, cache, and UI surfaces, then reduce this baseline.",
        reentryCondition: "Any new Clawix API, UI, CLI, schema, storage key, route, permission, stream, cache, or feature flag surface must carry resourceContract before landing.",
      },
    ],
  };
}

function runSelfTest() {
  const validResourceContract = {
    startup: "self-test startup",
    idle: "self-test idle",
    memory: "self-test memory",
    streaming: "self-test streaming",
    storage: "self-test storage",
    hotPath: "self-test hot path",
    scale: "self-test scale",
    validation: "self-test validation",
  };
  const surfaces = {
    persistentNodes: [{ id: "node.withResourceContract", resourceContract: validResourceContract }, { id: "node.baselined" }],
    routes: [{ id: "route.withResourceContract", resourceContract: validResourceContract }, { id: "route.baselined" }],
    interfaceSurfaces: [{ id: "ui.withResourceContract", resourceContract: validResourceContract }, { id: "ui.baselined" }],
  };
  const baseline = buildBaseline(surfaces);
  assert.deepEqual(validateSurfaceResourceContracts(surfaces, baseline), []);

  const newSurfaceFailures = validateSurfaceResourceContracts({
    ...surfaces,
    interfaceSurfaces: [...surfaces.interfaceSurfaces, { id: "ui.new" }],
  }, baseline);
  assert.match(newSurfaceFailures.join("\n"), /added missing interfaceSurfaces: ui\.new/);

  const malformedContractFailures = validateSurfaceResourceContracts({
    persistentNodes: [{ id: "node.bad", resourceContract: { ...validResourceContract, hotPath: "" } }],
    routes: [],
    interfaceSurfaces: [],
  }, buildBaseline({ persistentNodes: [], routes: [], interfaceSurfaces: [] }));
  assert.match(malformedContractFailures.join("\n"), /resourceContract\.hotPath must be a non-empty string/);
}

if (process.argv.includes("--self-test")) {
  runSelfTest();
  console.log("surface resource contract guard self-test passed");
  process.exit(0);
}

if (process.argv.includes("--update-baseline")) {
  fs.writeFileSync(baselinePath, `${JSON.stringify(buildBaseline(), null, 2)}\n`);
  console.log(`updated ${path.relative(rootDir, baselinePath)}`);
  process.exit(0);
}

const failures = validateSurfaceResourceContracts();
if (failures.length > 0) {
  console.error("surface resource contract guard failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("surface resource contract guard passed");
