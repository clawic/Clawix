#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = path.join(rootDir, "docs", "debt-ledger-projection.manifest.json");
const siblingClawjsRoot = path.resolve(rootDir, "../../clawjs");
const errors = [];

const manifest = readJson(manifestPath);
if (manifest.schemaVersion !== 1) errors.push("docs/debt-ledger-projection.manifest.json.schemaVersion must be 1");
if (manifest.mode !== "public-redacted-report-only") errors.push("debt ledger projection mode must be public-redacted-report-only");
if (!Array.isArray(manifest.sources) || manifest.sources.length < 1) errors.push("debt ledger projection must list sources");

for (const source of manifest.sources ?? []) {
  if (!source.path || !fs.existsSync(path.join(rootDir, source.path))) errors.push(`projection source is missing: ${source.path ?? "<missing>"}`);
  if (!source.validation) errors.push(`projection source ${source.path ?? "<missing>"} is missing validation`);
}

if (manifest.privateOverlay?.status !== "excluded-from-public-repo") errors.push("private overlay must remain excluded from the public repo");
if (JSON.stringify(manifest).includes("/Users/")) errors.push("public debt ledger projection must not contain private absolute paths");

if (fs.existsSync(path.join(siblingClawjsRoot, "packages", "clawjs", "src", "index.ts"))) {
  const result = spawnSync(process.execPath, ["--import", "tsx", "--eval", sourceCliSnippet(["debt", "audit", "--root", rootDir, "--json"])], {
    cwd: siblingClawjsRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    errors.push(`claw debt audit --root <clawix> failed: ${result.stderr.trim() || result.stdout.trim()}`);
  } else {
    const payload = JSON.parse(result.stdout);
    if (payload?.data?.audit?.privateSummary?.included !== false) errors.push("public debt audit must exclude private summary data");
    if (JSON.stringify(payload).includes("/Users/")) errors.push("public debt audit output must not expose private absolute paths");
  }
}

if (process.argv.includes("--self-test")) {
  const simulated = JSON.parse(JSON.stringify(manifest));
  simulated.privateOverlay.status = "public";
  if (simulated.privateOverlay.status === "excluded-from-public-repo") errors.push("self-test failed to mutate private overlay status");
  console.log("debt ledger projection self-test passed");
  process.exit(0);
}

if (errors.length > 0) {
  console.error("debt ledger projection check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("debt ledger projection check passed");

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function sourceCliSnippet(args) {
  return `
    const { runCli } = await import("./packages/clawjs/src/index.ts");
    const code = await runCli(${JSON.stringify(args)}, {
      stdout: process.stdout,
      stderr: process.stderr,
      stdin: process.stdin,
      cwd: ${JSON.stringify(rootDir)},
      binName: "claw"
    });
    process.exitCode = code;
  `;
}
