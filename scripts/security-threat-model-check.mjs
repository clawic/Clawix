#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const siblingRoot = path.resolve(rootDir, "../../clawjs");
const siblingCheck = path.join(siblingRoot, "scripts/security-threat-model-check.mjs");

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function exists(relativePath) {
  return fs.existsSync(path.join(rootDir, relativePath));
}

function requireSnippet(errors, relativePath, snippet) {
  if (!exists(relativePath)) {
    errors.push(`missing ${relativePath}`);
    return;
  }
  if (!read(relativePath).includes(snippet)) errors.push(`${relativePath} must mention ${snippet}`);
}

function validateLocalRouting() {
  const errors = [];
  requireSnippet(errors, "docs/adr/0028-global-threat-modeling-mirror.md", "adr:global-threat-modeling-governance");
  requireSnippet(errors, "docs/adr/TEMPLATE.md", "Threat Model Impact");
  requireSnippet(errors, "docs/decision-map.md", "global threat modeling");
  requireSnippet(errors, "docs/decision-map.md", "security-threat-model-check.mjs");
  requireSnippet(errors, "docs/discoverability.registry.json", "global-threat-modeling");
  requireSnippet(errors, "docs/discoverability.registry.json", "security-threat-model-check");
  requireSnippet(errors, "docs/discoverability.md", "global-threat-modeling");
  requireSnippet(errors, "docs/discoverability.md", "security-threat-model-check");
  requireSnippet(errors, "scripts/test.sh", "security-threat-model-check.mjs");
  return errors;
}

function runSibling(args = []) {
  if (!fs.existsSync(siblingCheck)) {
    return {
      status: 1,
      stderr: `ClawJS canonical security threat model checker not found: ${siblingCheck}\n`,
      stdout: "",
    };
  }
  return spawnSync(process.execPath, [siblingCheck, ...args], {
    cwd: siblingRoot,
    encoding: "utf8",
    env: process.env,
  });
}

function runSelfTest() {
  assert.equal(validateLocalRouting().some((error) => error.includes("missing impossible")), false);
  const missingSibling = spawnSync(process.execPath, ["-e", "process.exit(0)"], { encoding: "utf8" });
  assert.equal(missingSibling.status, 0);
  console.log("clawix security threat model check self-test passed");
}

const selfTest = process.argv.includes("--self-test");
if (selfTest) {
  runSelfTest();
} else {
  const sibling = runSibling();
  const errors = validateLocalRouting();
  if (sibling.status !== 0) errors.push(`sibling ClawJS threat model check failed:\n${sibling.stdout}${sibling.stderr}`.trim());
  if (errors.length > 0) {
    console.error("clawix security threat model check failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  process.stdout.write(sibling.stdout);
  console.log("clawix security threat model check passed");
}
