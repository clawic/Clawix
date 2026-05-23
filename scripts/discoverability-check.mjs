#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const canonical = path.resolve(rootDir, "../../clawjs/scripts/discoverability-check.mjs");
const argv = process.argv.slice(2);
const isClosure = argv.includes("closure");
const wantsJson = argv.includes("--json");

if (!fs.existsSync(canonical)) {
  if (isClosure && wantsJson) {
    console.log(JSON.stringify({
      schemaVersion: 1,
      status: "blocked",
      changedFiles: [],
      relevantFiles: [],
      commandsRun: [],
      discoveredArtifacts: [],
      missingDiscovery: [{
        path: "scripts/discoverability-check.mjs",
        reason: `ClawJS canonical discoverability checker not found: ${canonical}`,
      }],
      failedCommands: [],
    }, null, 2));
    process.exit(1);
  }
  console.error(`ClawJS canonical discoverability checker not found: ${canonical}`);
  process.exit(1);
}

const result = spawnSync(process.execPath, [canonical, "--root", rootDir, "--profile", "clawix", ...argv], {
  cwd: rootDir,
  stdio: "inherit",
  env: process.env,
});

process.exitCode = result.status ?? 1;
