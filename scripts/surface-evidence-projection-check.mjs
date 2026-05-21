#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const manifestPath = "docs/persistent-surface-clawix.manifest.json";
const baselinePath = "docs/surface-evidence-projection-baseline.json";

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function sha256Ids(ids) {
  return crypto.createHash("sha256").update([...ids].sort().join("\n")).digest("hex");
}

function sortedIds(ids) {
  return [...ids].sort();
}

function hasText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function diffIds(actualIds, expectedIds) {
  const expected = new Set(expectedIds);
  const actual = new Set(actualIds);
  return {
    added: actualIds.filter((id) => !expected.has(id)),
    removed: expectedIds.filter((id) => !actual.has(id)),
  };
}

function existingPath(relativePath) {
  return fs.existsSync(path.join(rootDir, relativePath));
}

function requireArray(value, label, failures) {
  if (!Array.isArray(value)) {
    failures.push(`${label} must be an array`);
    return [];
  }
  return value;
}

function checkIdSummary(summary, label, failures) {
  if (!summary || typeof summary.count !== "number" || !hasText(summary.idsSha256)) {
    failures.push(`${label} must include count, idsSha256, and ids`);
    return;
  }
  if (!Array.isArray(summary.ids) || !summary.ids.every(hasText)) {
    failures.push(`${label}.ids must be an array of non-empty strings`);
    return;
  }
  const ids = sortedIds(summary.ids);
  if (summary.ids.length !== summary.count) {
    failures.push(`${label}.count must equal ids.length`);
  }
  if (sha256Ids(ids) !== summary.idsSha256) {
    failures.push(`${label}.idsSha256 must match ids`);
  }
}

function checkMissingSource(kind, items, baselineEntry, failures) {
  const missingIds = items.filter((item) => !item.source).map((item) => item.id);
  if (missingIds.length === 0) return;

  const expected = baselineEntry?.missingSource?.[kind];
  if (!expected) {
    failures.push(`${kind} missing source locators: ${missingIds.join(", ")}`);
    return;
  }

  const actualHash = sha256Ids(missingIds);
  if (missingIds.length !== expected.count || actualHash !== expected.idsSha256) {
    const expectedIds = Array.isArray(expected.ids) ? sortedIds(expected.ids) : [];
    const { added, removed } = diffIds(sortedIds(missingIds), expectedIds);
    failures.push(
      `${kind} missing-source baseline drift: expected ${expected.count}/${expected.idsSha256}, got ${missingIds.length}/${actualHash}`,
    );
    if (added.length > 0) failures.push(`added missing-source ${kind}: ${added.join(", ")}`);
    if (removed.length > 0) failures.push(`removed missing-source ${kind}: ${removed.join(", ")}`);
  }
}

function checkNodeRef(id, label, nodeIds, allowedExternalNodeRefs, failures) {
  if (!id || nodeIds.has(id)) return;
  allowedExternalNodeRefs.add(id);
  failures.push(`${label} ${id} is not a registered persistent node`);
}

function checkManifest(manifest, baseline, today = new Date().toISOString().slice(0, 10)) {
  const failures = [];
  const nodes = requireArray(manifest.nodes, "manifest.nodes", failures);
  const edges = requireArray(manifest.edges, "manifest.edges", failures);
  const routes = requireArray(manifest.routes, "manifest.routes", failures);
  const nodeIds = new Set(nodes.map((node) => node.id));
  const edgeIds = new Set(edges.map((edge) => edge.id));
  const externalNodeRefs = new Set();
  const baselineEntry = baseline.entries?.find((entry) => entry.id === "clawix.generated-persistent-surface-source-locators");

  if (!baselineEntry) {
    failures.push(`${baselinePath} must include clawix.generated-persistent-surface-source-locators`);
  } else {
    if (baselineEntry.classification !== "lateral_debt") {
      failures.push(`${baselineEntry.id} must be classified as lateral_debt`);
    }
    if (!baselineEntry.expires && baseline.expires < today) {
      failures.push(`${baselinePath} expired on ${baseline.expires}`);
    }
    if (baselineEntry.expires && baselineEntry.expires < today) {
      failures.push(`${baselineEntry.id} expired on ${baselineEntry.expires}`);
    }
    for (const kind of ["nodes", "edges", "routes"]) {
      checkIdSummary(baselineEntry.missingSource?.[kind], `${baselineEntry.id}.missingSource.${kind}`, failures);
    }
    checkIdSummary(baselineEntry.externalNodeRefs, `${baselineEntry.id}.externalNodeRefs`, failures);
  }

  for (const node of nodes) {
    if (!node.id) failures.push("manifest node is missing id");
    if (!node.surfaceSteward) failures.push(`${node.id || "<unknown node>"} is missing surfaceSteward`);
    if (!node.kind) failures.push(`${node.id || "<unknown node>"} is missing kind`);
  }

  for (const edge of edges) {
    for (const field of ["id", "fromId", "toId", "type", "surfaceSteward", "contractId", "transport", "validation"]) {
      if (!edge[field]) failures.push(`${edge.id || "<unknown edge>"} is missing ${field}`);
    }
    checkNodeRef(edge.fromId, `${edge.id} fromId`, nodeIds, externalNodeRefs, failures);
    checkNodeRef(edge.toId, `${edge.id} toId`, nodeIds, externalNodeRefs, failures);
    checkNodeRef(edge.contractId, `${edge.id} contractId`, nodeIds, externalNodeRefs, failures);
  }

  for (const route of routes) {
    for (const field of ["id", "fromId", "toId", "surfaceSteward", "transport", "validation", "summary"]) {
      if (!route[field]) failures.push(`${route.id || "<unknown route>"} is missing ${field}`);
    }
    checkNodeRef(route.fromId, `${route.id} fromId`, nodeIds, externalNodeRefs, failures);
    checkNodeRef(route.toId, `${route.id} toId`, nodeIds, externalNodeRefs, failures);
    for (const field of ["docs", "tests", "adrs", "steps"]) {
      const values = requireArray(route[field], `${route.id}.${field}`, failures);
      if (values.length === 0) failures.push(`${route.id}.${field} must not be empty`);
    }
    for (const evidencePath of [...(route.docs ?? []), ...(route.tests ?? []), ...(route.adrs ?? [])]) {
      if (!existingPath(evidencePath)) failures.push(`${route.id} evidence path does not exist: ${evidencePath}`);
    }
    for (const step of route.steps ?? []) {
      for (const field of ["edgeId", "fromId", "toId", "edgeType", "contractId", "surfaceSteward", "transport", "validation"]) {
        if (!step[field]) failures.push(`${route.id} step is missing ${field}`);
      }
      if (step.edgeId && !edgeIds.has(step.edgeId)) failures.push(`${route.id} step edgeId ${step.edgeId} is not a registered edge`);
      checkNodeRef(step.fromId, `${route.id} step fromId`, nodeIds, externalNodeRefs, failures);
      checkNodeRef(step.toId, `${route.id} step toId`, nodeIds, externalNodeRefs, failures);
      checkNodeRef(step.contractId, `${route.id} step contractId`, nodeIds, externalNodeRefs, failures);
    }
  }

  checkMissingSource("nodes", nodes, baselineEntry, failures);
  checkMissingSource("edges", edges, baselineEntry, failures);
  checkMissingSource("routes", routes, baselineEntry, failures);
  if (externalNodeRefs.size > 0) {
    const expected = baselineEntry?.externalNodeRefs;
    const actualHash = sha256Ids(externalNodeRefs);
    if (!expected || externalNodeRefs.size !== expected.count || actualHash !== expected.idsSha256) {
      const actualIds = sortedIds(externalNodeRefs);
      const expectedIds = Array.isArray(expected?.ids) ? sortedIds(expected.ids) : [];
      const { added, removed } = diffIds(actualIds, expectedIds);
      failures.push(
        `external node reference baseline drift: expected ${expected?.count ?? "<missing>"}/${expected?.idsSha256 ?? "<missing>"}, got ${externalNodeRefs.size}/${actualHash}`,
      );
      if (added.length > 0) failures.push(`added external node refs: ${added.join(", ")}`);
      if (removed.length > 0) failures.push(`removed external node refs: ${removed.join(", ")}`);
    }
    for (const failure of [...failures]) {
      if (failure.endsWith("is not a registered persistent node")) {
        failures.splice(failures.indexOf(failure), 1);
      }
    }
  }

  return failures;
}

function runSelfTest() {
  const missingSourceSummary = (items) => {
    const ids = sortedIds(items.map((item) => item.id));
    return { count: ids.length, idsSha256: sha256Ids(ids), ids };
  };
  const manifest = {
    nodes: [
      { id: "clawix.ui.chat", surfaceSteward: "clawix", kind: "ui" },
      { id: "clawix.bridge.local", surfaceSteward: "clawix", kind: "bridge" },
      { id: "clawix.protocol.bridge.v1", surfaceSteward: "clawix", kind: "protocol" },
    ],
    edges: [
      {
        id: "edge.one",
        fromId: "clawix.ui.chat",
        toId: "clawix.bridge.local",
        type: "consumes",
        surfaceSteward: "clawix",
        contractId: "clawix.protocol.bridge.v1",
        transport: "local",
        validation: "fixture",
      },
    ],
    routes: [
      {
        id: "route.one",
        fromId: "clawix.ui.chat",
        toId: "clawix.bridge.local",
        surfaceSteward: "clawix",
        transport: "local",
        validation: "fixture",
        summary: "test",
        docs: ["docs/adr/0011-surface-route-graph.md"],
        tests: ["macos/Tests/ClawixMeshTests/ChatHydrationTests.swift"],
        adrs: ["docs/adr/0011-surface-route-graph.md"],
        steps: [
          {
            edgeId: "edge.one",
            fromId: "clawix.ui.chat",
            toId: "clawix.bridge.local",
            edgeType: "consumes",
            contractId: "clawix.protocol.bridge.v1",
            surfaceSteward: "clawix",
            transport: "local",
            validation: "fixture",
          },
        ],
      },
    ],
  };
  const baseline = {
    entries: [
      {
        id: "clawix.generated-persistent-surface-source-locators",
        classification: "lateral_debt",
        missingSource: {
          nodes: missingSourceSummary(manifest.nodes),
          edges: missingSourceSummary(manifest.edges),
          routes: missingSourceSummary(manifest.routes),
        },
        externalNodeRefs: { count: 0, idsSha256: sha256Ids([]), ids: [] },
      },
    ],
  };
  const positive = checkManifest(manifest, baseline);
  if (positive.length > 0) {
    throw new Error(`positive fixture failed: ${positive.join("; ")}`);
  }
  const negative = checkManifest(
    { ...manifest, routes: [{ ...manifest.routes[0], steps: [{ ...manifest.routes[0].steps[0], edgeId: "missing.edge" }] }] },
    baseline,
  );
  if (!negative.some((failure) => failure.includes("missing.edge"))) {
    throw new Error("negative fixture did not catch missing route edge reference");
  }
  const sourceDrift = checkManifest(
    { ...manifest, nodes: [...manifest.nodes, { id: "clawix.new.node", surfaceSteward: "clawix", kind: "preferenceKey" }] },
    baseline,
  );
  if (!sourceDrift.some((failure) => failure.includes("added missing-source nodes: clawix.new.node"))) {
    throw new Error("negative fixture did not report actionable missing-source drift");
  }
  const malformedBaseline = checkManifest(manifest, {
    ...baseline,
    entries: [
      {
        ...baseline.entries[0],
        missingSource: {
          ...baseline.entries[0].missingSource,
          nodes: { ...baseline.entries[0].missingSource.nodes, idsSha256: "wrong" },
        },
      },
    ],
  });
  if (!malformedBaseline.some((failure) => failure.includes("idsSha256 must match ids"))) {
    throw new Error("negative fixture did not catch malformed baseline summary");
  }
}

if (process.argv.includes("--self-test")) {
  runSelfTest();
  console.log("surface evidence projection self-test passed");
} else {
  const failures = checkManifest(readJson(manifestPath), readJson(baselinePath));
  if (failures.length > 0) {
    console.error("surface evidence projection check failed:");
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.log("surface evidence projection check passed");
}
