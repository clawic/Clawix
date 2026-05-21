#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const siblingClawJs = path.resolve(rootDir, "../../clawjs");
const errors = [];

function exists(relativePath, base = rootDir) {
  return fs.existsSync(path.join(base, relativePath));
}

function read(relativePath, base = rootDir) {
  return fs.readFileSync(path.join(base, relativePath), "utf8");
}

function readJson(relativePath, base = rootDir) {
  return JSON.parse(read(relativePath, base));
}

for (const file of [
  "docs/runtime-ecosystem-lens.md",
  "docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md",
  "docs/interface-surface-clawix.registry.json",
  "docs/decision-map.md",
  "docs/discoverability.registry.json",
  "docs/adr-operational-coverage.manifest.json"
]) {
  if (!exists(file)) errors.push(`missing ${file}`);
}

if (exists("docs/runtime-ecosystem-lens.md")) {
  const text = read("docs/runtime-ecosystem-lens.md");
  for (const snippet of ["runtime lens", "semantic native parity", "local overlays", "EXTERNAL PENDING"]) {
    if (!text.includes(snippet)) errors.push(`runtime lens doc missing ${snippet}`);
  }
}

if (exists("docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md")) {
  const text = read("docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md");
  for (const snippet of ["Status: Accepted", "Surface Parity", "Discovery Route", "ClawJS ADR 0047"]) {
    if (!text.includes(snippet)) errors.push(`mirror ADR missing ${snippet}`);
  }
}

if (exists("docs/interface-surface-clawix.registry.json")) {
  const registry = readJson("docs/interface-surface-clawix.registry.json");
  const surface = (registry.surfaces ?? []).find((entry) => entry.id === "runtimeEcosystemLens");
  if (!surface) errors.push("interface registry missing runtimeEcosystemLens");
  else {
    if (surface.status !== "dev-only") errors.push("runtimeEcosystemLens must stay dev-only until UI implementation evidence exists");
    for (const field of ["humanSurface", "programmaticSurface", "storageOwner", "validation", "steward"]) {
      if (!surface[field]) errors.push(`runtimeEcosystemLens missing ${field}`);
    }
  }
}

if (!read("docs/decision-map.md").includes("Runtime ecosystem lens")) {
  errors.push("decision map missing Runtime ecosystem lens row");
}

const discoverability = readJson("docs/discoverability.registry.json");
const sources = new Set((discoverability.artifacts ?? []).map((entry) => entry.canonicalSource));
for (const source of [
  "docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md",
  "docs/runtime-ecosystem-lens.md",
  "scripts/runtime_ecosystem_lens_check.mjs"
]) {
  if (!sources.has(source)) errors.push(`discoverability registry missing ${source}`);
}

const coverage = readJson("docs/adr-operational-coverage.manifest.json");
if (!(coverage.acceptedAdrCoverage ?? []).some((entry) => entry.adr === "docs/adr/0033-runtime-ecosystem-integration-standard-mirror.md")) {
  errors.push("ADR operational coverage missing runtime ecosystem mirror ADR");
}

if (fs.existsSync(siblingClawJs)) {
  for (const file of [
    "docs/runtime-ecosystem-integration.manifest.json",
    "docs/runtime-ecosystem-integration-standard.md",
    "docs/adr/0047-runtime-ecosystem-integration-standard.md"
  ]) {
    if (!exists(file, siblingClawJs)) errors.push(`sibling ClawJS missing ${file}`);
  }
}

if (errors.length > 0) {
  console.error("Runtime ecosystem lens check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("runtime ecosystem lens check passed");
