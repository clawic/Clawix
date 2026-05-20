#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const clawjsRoot = process.env.CLAWJS_ROOT || path.resolve(repoRoot, "../../clawjs");
const clawBin = path.join(clawjsRoot, "packages", "clawjs", "bin", "claw.mjs");
const outputPaths = [
  path.join(repoRoot, "macos", "Sources", "Clawix", "Resources", "life-registry.json"),
  path.join(repoRoot, "ios", "Sources", "Clawix", "Life", "Resources", "life-registry.json"),
];
const swiftPaths = [
  path.join(repoRoot, "macos", "Sources", "Clawix", "Life", "LifeRegistry.swift"),
  path.join(repoRoot, "ios", "Sources", "Clawix", "Life", "LifeRegistry.swift"),
];

function runClawRegistry() {
  const stdout = execFileSync(process.execPath, ["--import", "tsx", clawBin, "signals", "registry", "--json"], {
    cwd: clawjsRoot,
    encoding: "utf8",
  });
  const payload = JSON.parse(stdout);
  return payload.data ?? payload;
}

function swiftString(value) {
  return JSON.stringify(String(value)).replaceAll("\\/", "/");
}

function swiftCategory(category) {
  const map = {
    "body-health": "bodyHealth",
    "mind-emotions": "mindEmotions",
    "time-productivity": "timeProductivity",
    "creative-output": "creativeOutput",
    "consumption-leisure": "consumptionLeisure",
    "relations-social": "relationsSocial",
    "world-places": "worldPlaces",
    "possessions-identity": "possessionsIdentity",
    "career-money": "careerMoney",
    "meta-reflection": "metaReflection",
  };
  const value = map[category];
  if (!value) throw new Error(`Unknown Life category: ${category}`);
  return value;
}

function writeProjection(projection) {
  const json = `${JSON.stringify(projection, null, 2)}\n`;
  for (const outputPath of outputPaths) {
    fs.writeFileSync(outputPath, json);
  }
}

function generatedFallbackBlock(projection) {
  return projection.entries
    .filter((entry) => entry.status === "stable")
    .map((entry) => {
      const iconHint = entry.iconHint ? swiftString(entry.iconHint) : "nil";
      return `        LifeFallbackEntry(id: ${swiftString(entry.id)}, label: ${swiftString(entry.label)}, category: .${swiftCategory(entry.category)}, iconHint: ${iconHint}, sensitive: ${entry.sensitive ? "true" : "false"})`;
    })
    .join(",\n");
}

function updateSwiftFallbacks(projection) {
  const block = generatedFallbackBlock(projection);
  for (const swiftPath of swiftPaths) {
    let source = fs.readFileSync(swiftPath, "utf8");
    source = source.replace(
      /private static let generatedFallbackSourceChecksum = ".*"/,
      `private static let generatedFallbackSourceChecksum = ${swiftString(projection.source.checksum)}`,
    );
    source = source.replace(
      /private static let generatedFallbackSignalsServicePort = \d+/,
      `private static let generatedFallbackSignalsServicePort = ${projection.service.port}`,
    );
    source = source.replace(
      /(        \/\/ BEGIN GENERATED LIFE FALLBACK\n)([\s\S]*?)(        \/\/ END GENERATED LIFE FALLBACK)/,
      `$1${block}\n$3`,
    );
    fs.writeFileSync(swiftPath, source);
  }
}

const projection = runClawRegistry();
writeProjection(projection);
updateSwiftFallbacks(projection);
console.log(JSON.stringify({
  ok: true,
  projectionVersion: projection.projectionVersion,
  entries: projection.entries.length,
  categories: projection.categories.length,
  servicePort: projection.service.port,
  sourceChecksum: projection.source.checksum,
}, null, 2));
