#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const clawjsRoot = process.env.CLAWJS_ROOT || path.resolve(repoRoot, "..", "..", "clawjs");
const clawjsRegistryPath = path.join(clawjsRoot, "packages", "clawjs-index", "src", "schema", "registry.ts");
const swiftPath = path.join(repoRoot, "macos", "Sources", "Clawix", "Index", "Components", "IndexTypeMeta.swift");
const failures = [];

function fail(message) {
  failures.push(message);
}

function read(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function swiftIconName(icon) {
  return icon.replaceAll("-", "_");
}

function rgb(hex) {
  const value = hex.replace("#", "");
  return [0, 2, 4].map((offset) => Number.parseInt(value.slice(offset, offset + 2), 16) / 255);
}

function closeEnough(actual, expected) {
  return Math.abs(actual - expected) <= 0.015;
}

const clawjsSource = read(clawjsRegistryPath);
const swiftSource = read(swiftPath);

const canonical = [];
const typePattern = /name:\s*"([^"]+)"[\s\S]*?uiHints:\s*\{\s*icon:\s*"([^"]+)",\s*cardKind:\s*"([^"]+)",\s*accentColor:\s*"(#[0-9a-fA-F]{6})"\s*\}/g;
for (const match of clawjsSource.matchAll(typePattern)) {
  canonical.push({
    name: match[1],
    icon: match[2],
    kind: match[3],
    accentColor: match[4].toLowerCase(),
  });
}

const orderBlock = swiftSource.match(/static let canonicalOrder:\s*\[String\]\s*=\s*\[([\s\S]*?)\]/)?.[1] ?? "";
const swiftOrder = [...orderBlock.matchAll(/"([^"]+)"/g)].map((match) => match[1]);
const swiftKnown = new Map();
const knownPattern = /"([^"]+)":\s*\.init\(typeName:\s*"([^"]+)",\s*displayName:\s*"[^"]+",\s*lucideName:\s*"([^"]+)",\s*accent:\s*Color\(red:\s*([0-9.]+),\s*green:\s*([0-9.]+),\s*blue:\s*([0-9.]+)\),\s*kind:\s*\.(\w+)\)/g;
for (const match of swiftSource.matchAll(knownPattern)) {
  swiftKnown.set(match[1], {
    typeName: match[2],
    icon: match[3],
    rgb: [Number(match[4]), Number(match[5]), Number(match[6])],
    kind: match[7],
  });
}

if (canonical.length === 0) fail(`${path.relative(repoRoot, clawjsRegistryPath)} yielded no canonical index types`);
if (canonical.length !== swiftOrder.length) {
  fail(`IndexTypeCatalog.canonicalOrder has ${swiftOrder.length} types; @clawjs/index has ${canonical.length}`);
}

for (const [index, entry] of canonical.entries()) {
  const swiftEntry = swiftKnown.get(entry.name);
  if (swiftOrder[index] !== entry.name) {
    fail(`IndexTypeCatalog.canonicalOrder[${index}] is ${JSON.stringify(swiftOrder[index])}; expected ${JSON.stringify(entry.name)}`);
  }
  if (!swiftEntry) {
    fail(`IndexTypeCatalog.known is missing ${entry.name}`);
    continue;
  }
  if (swiftEntry.typeName !== entry.name) fail(`${entry.name} typeName mismatch`);
  if (swiftEntry.icon !== swiftIconName(entry.icon)) {
    fail(`${entry.name} lucideName is ${swiftEntry.icon}; expected ${swiftIconName(entry.icon)}`);
  }
  if (swiftEntry.kind !== entry.kind) fail(`${entry.name} kind is ${swiftEntry.kind}; expected ${entry.kind}`);

  const expectedRgb = rgb(entry.accentColor);
  for (const [channelIndex, channel] of ["red", "green", "blue"].entries()) {
    if (!closeEnough(swiftEntry.rgb[channelIndex], expectedRgb[channelIndex])) {
      fail(`${entry.name} ${channel} accent is ${swiftEntry.rgb[channelIndex]}; expected ${expectedRgb[channelIndex].toFixed(2)} from ${entry.accentColor}`);
    }
  }
}

if (!swiftKnown.has("intent")) fail("IndexTypeCatalog.known must include ClawJS canonical type intent");

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log(JSON.stringify({
  ok: true,
  canonicalTypes: canonical.length,
  source: path.relative(repoRoot, clawjsRegistryPath),
  projection: path.relative(repoRoot, swiftPath),
}, null, 2));
