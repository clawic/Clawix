#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const macJsonPath = path.join(repoRoot, "macos", "Sources", "Clawix", "Resources", "life-registry.json");
const iosJsonPath = path.join(repoRoot, "ios", "Sources", "Clawix", "Life", "Resources", "life-registry.json");
const swiftPaths = [
  path.join(repoRoot, "macos", "Sources", "Clawix", "Life", "LifeRegistry.swift"),
  path.join(repoRoot, "ios", "Sources", "Clawix", "Life", "LifeRegistry.swift"),
  path.join(repoRoot, "macos", "Sources", "Clawix", "Life", "LifeManager.swift"),
  path.join(repoRoot, "ios", "Sources", "Clawix", "Life", "LifeManager.swift"),
];

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

const macRaw = fs.readFileSync(macJsonPath, "utf8");
const iosRaw = fs.readFileSync(iosJsonPath, "utf8");
if (macRaw !== iosRaw) fail("macOS and iOS life-registry.json projections differ");

const projection = JSON.parse(macRaw);
if (projection.projectionVersion !== "signals-registry.v1") fail("life registry projectionVersion mismatch");
if (projection.source?.path !== "tracking-registry.json") fail("life registry source path mismatch");
if (!String(projection.source?.checksum ?? "").startsWith("sha256:")) fail("life registry source checksum missing");
if (projection.service?.port !== 24110) fail("life registry Signals port mismatch");
if (projection.service?.verticalRouteTemplate !== "/v1/{verticalId}") fail("life registry route template mismatch");
if (projection.categories?.length !== 10) fail("life registry category count mismatch");
if (projection.entries?.length !== 80) fail("life registry entry count mismatch");
if (!projection.entries.some((entry) => entry.status === "dev_only")) fail("life registry dev_only status missing");
if (/packageName|servicePort|catalogPackage/.test(macRaw)) fail("life registry JSON contains forbidden framework-owned fields");

for (const swiftPath of swiftPaths) {
  const source = fs.readFileSync(swiftPath, "utf8");
  if (/packageName|servicePort|portByVertical|@clawjs\/(health|sleep|workouts|finance)/.test(source)) {
    fail(`${path.relative(repoRoot, swiftPath)} contains forbidden manual registry ownership`);
  }
}

if (!process.exitCode) {
  console.log(JSON.stringify({
    ok: true,
    entries: projection.entries.length,
    categories: projection.categories.length,
    servicePort: projection.service.port,
    checksum: projection.source.checksum,
  }, null, 2));
}
