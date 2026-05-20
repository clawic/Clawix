#!/usr/bin/env node
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const persistentManifestPath = "docs/persistent-surface-clawix.manifest.json";
const interfaceRegistryPath = "docs/interface-surface-clawix.registry.json";
const baselinePath = path.join(rootDir, "docs/surface-narrative-clawix-baseline.json");
const today = new Date().toISOString().slice(0, 10);

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function sha256Ids(ids) {
  return crypto.createHash("sha256").update([...ids].sort().join("\n")).digest("hex");
}

function hasText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function existingRelativePath(relativePath) {
  return hasText(relativePath) && fs.existsSync(path.join(rootDir, relativePath));
}

function validateNarrative(narrative, label, failures) {
  if (!narrative || typeof narrative !== "object" || Array.isArray(narrative)) {
    failures.push(`${label} is missing surfaceNarrative`);
    return;
  }
  if (!hasText(narrative.concept)) failures.push(`${label}.surfaceNarrative.concept must be a non-empty string`);
  if (!hasText(narrative.nonInference)) failures.push(`${label}.surfaceNarrative.nonInference must be a non-empty string`);
  const decision = narrative.authorizingDecision;
  if (!decision || typeof decision !== "object" || Array.isArray(decision)) {
    failures.push(`${label}.surfaceNarrative.authorizingDecision must be an object`);
  } else {
    if (!hasText(decision.ref)) failures.push(`${label}.surfaceNarrative.authorizingDecision.ref must be a non-empty string`);
    if (!hasText(decision.path)) {
      failures.push(`${label}.surfaceNarrative.authorizingDecision.path must be a non-empty string`);
    } else if (!existingRelativePath(decision.path)) {
      failures.push(`${label}.surfaceNarrative.authorizingDecision.path does not exist: ${decision.path}`);
    }
  }
  const completingSurface = narrative.completingSurface;
  if (!completingSurface || typeof completingSurface !== "object" || Array.isArray(completingSurface)) {
    failures.push(`${label}.surfaceNarrative.completingSurface must be an object`);
  } else {
    if (!hasText(completingSurface.human)) failures.push(`${label}.surfaceNarrative.completingSurface.human must be a non-empty string`);
    if (!hasText(completingSurface.programmatic)) failures.push(`${label}.surfaceNarrative.completingSurface.programmatic must be a non-empty string`);
  }
}

function missingNarrativeIds(items) {
  return items.filter((item) => !item.surfaceNarrative).map((item) => item.id).sort();
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
  return (baseline.entries ?? []).find((entry) => entry.id === "clawix.existing-surfaces-without-narrative");
}

function validateBaselineEnvelope(baseline) {
  const failures = [];
  if (baseline.version !== 1) failures.push("Clawix surface narrative baseline version must be 1");
  for (const [index, entry] of (baseline.entries ?? []).entries()) {
    const label = entry.id ?? `<entry ${index + 1}>`;
    for (const field of ["id", "classification", "owner", "reason", "risk", "expires", "nextPhase", "reentryCondition"]) {
      if (!entry[field]) failures.push(`${label} is missing ${field}`);
    }
    if (!["lateral_debt", "pre_existing_dirty"].includes(entry.classification)) {
      failures.push(`${label} has invalid classification ${entry.classification}`);
    }
    if (entry.expires && entry.expires < today) failures.push(`${label} expired on ${entry.expires}`);
    for (const key of ["persistentNodes", "routes", "interfaceSurfaces"]) {
      const summary = entry.missingNarrative?.[key];
      if (!summary || typeof summary.count !== "number" || !hasText(summary.idsSha256)) {
        failures.push(`${label}.missingNarrative.${key} must include count and idsSha256`);
      }
    }
  }
  return failures;
}

function compareMissingToBaseline(kind, ids, entry, failures) {
  const expected = entry?.missingNarrative?.[kind];
  if (!expected) {
    failures.push(`missing narrative baseline does not include ${kind}`);
    return;
  }
  const actualHash = sha256Ids(ids);
  if (ids.length !== expected.count || actualHash !== expected.idsSha256) {
    failures.push(`${kind} without surfaceNarrative baseline drift: expected ${expected.count}/${expected.idsSha256}, got ${ids.length}/${actualHash}`);
  }
}

function validateSurfaceNarratives(surfaces = loadSurfaces(), baseline = readBaseline()) {
  const failures = [];
  failures.push(...validateBaselineEnvelope(baseline));
  for (const [kind, items] of Object.entries(surfaces)) {
    for (const item of items) {
      if (item.surfaceNarrative) validateNarrative(item.surfaceNarrative, `${kind} ${item.id}`, failures);
    }
  }
  const entry = baselineEntry(baseline);
  if (!entry) {
    failures.push("surface narrative baseline must include clawix.existing-surfaces-without-narrative");
  } else {
    for (const [kind, items] of Object.entries(surfaces)) {
      compareMissingToBaseline(kind, missingNarrativeIds(items), entry, failures);
    }
  }
  return failures;
}

function buildBaseline(surfaces = loadSurfaces()) {
  return {
    version: 1,
    entries: [
      {
        id: "clawix.existing-surfaces-without-narrative",
        classification: "lateral_debt",
        owner: "clawix",
        reason: "Initial bounded baseline for Clawix manifest and interface surfaces that predate the surfaceNarrative contract.",
        risk: "Existing host/UI surfaces remain registered, but their conceptual authorization is not yet machine-checkable.",
        expires: "2026-08-18",
        missingNarrative: {
          persistentNodes: missingSummary(surfaces.persistentNodes),
          routes: missingSummary(surfaces.routes),
          interfaceSurfaces: missingSummary(surfaces.interfaceSurfaces),
        },
        nextPhase: "Backfill surfaceNarrative on high-change host, route, permission, and UI surfaces, then reduce this baseline.",
        reentryCondition: "Any new Clawix API, UI, CLI, schema, storage key, route, permission, or feature flag surface must carry surfaceNarrative before landing.",
      },
    ],
  };
}

function missingSummary(items) {
  const ids = missingNarrativeIds(items);
  return { count: ids.length, idsSha256: sha256Ids(ids) };
}

function runSelfTest() {
  const validNarrative = {
    concept: "Self-test concept",
    authorizingDecision: {
      ref: "ADR 0011",
      path: "docs/adr/0011-surface-route-graph.md",
    },
    completingSurface: {
      human: "self-test human surface",
      programmatic: "self-test programmatic surface",
    },
    nonInference: "self-test does not authorize other surfaces",
  };
  const surfaces = {
    persistentNodes: [{ id: "node.withNarrative", surfaceNarrative: validNarrative }, { id: "node.baselined" }],
    routes: [{ id: "route.withNarrative", surfaceNarrative: validNarrative }, { id: "route.baselined" }],
    interfaceSurfaces: [{ id: "ui.withNarrative", surfaceNarrative: validNarrative }, { id: "ui.baselined" }],
  };
  const baseline = buildBaseline(surfaces);
  assert.deepEqual(validateSurfaceNarratives(surfaces, baseline), []);

  const newSurfaceFailures = validateSurfaceNarratives({
    ...surfaces,
    interfaceSurfaces: [...surfaces.interfaceSurfaces, { id: "ui.new" }],
  }, baseline);
  assert.match(newSurfaceFailures.join("\n"), /interfaceSurfaces without surfaceNarrative baseline drift/);

  const invalidNarrativeFailures = validateSurfaceNarratives({
    ...surfaces,
    routes: [{ id: "route.invalid", surfaceNarrative: { ...validNarrative, authorizingDecision: { ref: "missing", path: "docs/missing.md" } } }, surfaces.routes[1]],
  }, baseline);
  assert.match(invalidNarrativeFailures.join("\n"), /authorizingDecision\.path does not exist/);
}

if (process.argv.includes("--self-test")) {
  runSelfTest();
  console.log("Clawix surface narrative guard self-test passed");
  process.exit(0);
}

if (process.argv.includes("--print-baseline")) {
  console.log(JSON.stringify(buildBaseline(), null, 2));
  process.exit(0);
}

const failures = validateSurfaceNarratives();
if (failures.length > 0) {
  console.error("Clawix surface narrative guard failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("Clawix surface narrative guard passed");
