#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const clawjsRoot = process.env.CLAWJS_ROOT || path.resolve(repoRoot, "..", "..", "clawjs");
const clawBin = path.join(clawjsRoot, "packages", "clawjs", "bin", "claw.mjs");
const curatedFiltersPath = path.join(repoRoot, "macos", "Sources", "Clawix", "Database", "Filters", "CuratedFilterRegistry.swift");
const sidebarPath = path.join(repoRoot, "macos", "Sources", "Clawix", "SidebarView.swift");
const collections = ["tasks", "goals", "notes", "projects"];
const failures = [];

function fail(message) {
  failures.push(message);
}

function read(filePath) {
  return fs.readFileSync(filePath, "utf8");
}

function schemaFor(collection) {
  const result = spawnSync(process.execPath, [clawBin, "collections", collection, "schema", "--json"], {
    cwd: clawjsRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail(`ClawJS schema command failed for ${collection}: ${result.stderr || result.stdout}`);
    return undefined;
  }
  try {
    const parsed = JSON.parse(result.stdout);
    if (parsed?.ok !== true || parsed?.data?.exists !== true) {
      fail(`ClawJS schema for ${collection} is not available`);
      return undefined;
    }
    return parsed.data.collection;
  } catch (error) {
    fail(`ClawJS schema for ${collection} did not return JSON: ${error.message}`);
    return undefined;
  }
}

function fieldsFor(schema) {
  return new Map((schema?.fields ?? []).map((field) => [field.name, field]));
}

const curatedSource = read(curatedFiltersPath);
const sidebarSource = read(sidebarPath);

for (const collection of collections) {
  if (!curatedSource.includes(`case "${collection}": return ${collection}Tabs`)) {
    fail(`CuratedFilterRegistry.tabs is missing ${collection}`);
  }
  if (!curatedSource.includes(`"${collection}"`) || !curatedSource.includes(`, "${collection}"),`)) {
    fail(`CuratedFilterRegistry.sidebarEntries is missing ${collection}`);
  }
  if (!sidebarSource.includes(`route: .databaseCollection("${collection}")`)) {
    fail(`SidebarToolsCatalog is missing database route for ${collection}`);
  }
}

const curatedFields = new Map();
const curatedStatusValues = new Map();
const tabBlockPattern = /private static let (\w+)Tabs:\s*\[Tab\]\s*=\s*\[([\s\S]*?)\n    \]/g;
for (const match of curatedSource.matchAll(tabBlockPattern)) {
  const collection = match[1];
  if (!collections.includes(collection)) continue;
  const block = match[2];
  const fields = new Set([...block.matchAll(/field:\s*"([^"]+)"/g)].map((fieldMatch) => fieldMatch[1]));
  const sortFields = [...block.matchAll(/Sort\(field:\s*"([^"]+)"/g)].map((fieldMatch) => fieldMatch[1]);
  for (const sortField of sortFields) fields.add(sortField);
  curatedFields.set(collection, fields);
  curatedStatusValues.set(collection, new Set(
    [...block.matchAll(/field:\s*"status"[\s\S]*?value:\s*\.string\("([^"]+)"\)/g)].map((valueMatch) => valueMatch[1])
  ));
}

for (const collection of collections) {
  const schema = schemaFor(collection);
  if (!schema) continue;
  const fields = fieldsFor(schema);
  const uiFields = curatedFields.get(collection) ?? new Set();
  for (const field of uiFields) {
    if (!fields.has(field)) fail(`${collection} curated filter references missing ClawJS field ${field}`);
  }

  const statusValues = curatedStatusValues.get(collection) ?? new Set();
  if (statusValues.size === 0) continue;
  const statusField = fields.get("status");
  if (statusField?.type !== "select") {
    fail(`${collection} curated filter references status but ClawJS status is not select`);
    continue;
  }
  const allowed = new Set(statusField.options ?? []);
  for (const value of statusValues) {
    if (!allowed.has(value)) fail(`${collection} curated status ${value} is not in ClawJS schema`);
  }
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log(JSON.stringify({
  ok: true,
  collections: collections.length,
  source: path.relative(repoRoot, clawBin),
  projections: [
    path.relative(repoRoot, curatedFiltersPath),
    path.relative(repoRoot, sidebarPath),
  ],
}, null, 2));
