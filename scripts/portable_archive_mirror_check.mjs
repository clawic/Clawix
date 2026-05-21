#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const errors = [];

function read(relativePath) {
  const file = path.join(root, relativePath);
  if (!fs.existsSync(file)) {
    errors.push(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const text = read(relativePath);
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (error) {
    errors.push(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireIncludes(relativePath, snippets) {
  const text = read(relativePath);
  for (const snippet of snippets) {
    if (!text.includes(snippet)) errors.push(`${relativePath} missing ${snippet}`);
  }
  return text;
}

function flatten(value) {
  return JSON.stringify(value ?? {});
}

requireIncludes("docs/adr/0034-portable-archive-contract-mirror.md", [
  ".clawbackup",
  ".clawexport",
  ".clawsecrets",
  "requires_signed_host",
  "Settings/Data",
  "PortableArchiveRestoreReport",
]);

requireIncludes("docs/decision-map.md", [
  "Portable archive backup/export/import/restore",
  "macos/Sources/Clawix/Settings/PortableArchiveSettingsPage.swift",
  "scripts/portable_archive_mirror_check.mjs",
]);

requireIncludes("macos/Sources/Clawix/SettingsView.swift", [
  "case portableArchive",
  "return \"Data\"",
  "PortableArchiveSettingsPage()",
]);

requireIncludes("macos/Sources/Clawix/Settings/PortableArchiveSettingsPage.swift", [
  "PortableArchiveUXState",
  "verificationFailed",
  "secretsRequireReauth",
  "externalSourceReferenced",
  "cacheWillRebuild",
  "restoreBlocked",
  "restoreComplete",
  ".clawbackup",
  ".clawsecrets",
  "signed-host proof",
]);

const assertions = readJson("docs/constitution.assertions.json");
const ii6 = assertions?.assertions?.find((entry) => entry.id === "II.6.backups-and-export-are-a-user-right");
if (!ii6) errors.push("II.6 assertion missing");
else {
  for (const snippet of [
    "docs/adr/0034-portable-archive-contract-mirror.md",
    "../../clawjs/docs/adr/0038-portable-archive-contract.md",
    "scripts/portable_archive_mirror_check.mjs",
  ]) {
    if (!flatten(ii6).includes(snippet)) errors.push(`II.6 assertion missing ${snippet}`);
  }
}

const surfaces = readJson("docs/interface-surface-clawix.registry.json");
if (!flatten(surfaces).includes("portableArchive")) errors.push("interface surface registry missing portableArchive");

const discovery = readJson("docs/discoverability.registry.json");
for (const required of [
  "docs/adr/0034-portable-archive-contract-mirror.md",
  "scripts/portable_archive_mirror_check.mjs",
]) {
  if (!flatten(discovery).includes(required)) errors.push(`discoverability registry missing ${required}`);
}
for (const query of ["portable archive", "backup", "export", "import", "restore", "requires_signed_host"]) {
  if (!read("docs/adr/0034-portable-archive-contract-mirror.md").includes(query)) {
    errors.push(`portable archive mirror docs missing ${query}`);
  }
}

const siblingRoot = path.resolve(root, "../../clawjs");
if (fs.existsSync(siblingRoot)) {
  const siblingAdr = path.join(siblingRoot, "docs/adr/0038-portable-archive-contract.md");
  const siblingContract = path.join(siblingRoot, "docs/portable-archive-contract.md");
  const siblingCli = path.join(siblingRoot, "packages/clawjs/src/cli-archive-command.ts");
  for (const file of [siblingAdr, siblingContract, siblingCli]) {
    if (!fs.existsSync(file)) errors.push(`missing sibling portable archive canon ${path.relative(siblingRoot, file)}`);
  }
}

if (errors.length > 0) {
  console.error(errors.map((error) => `portable-archive-mirror: ${error}`).join("\n"));
  process.exit(1);
}

console.log("portable archive mirror ok");
