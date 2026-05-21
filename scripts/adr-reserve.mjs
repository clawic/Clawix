#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const canonical = path.resolve(rootDir, "../../clawjs/scripts/adr-reserve.mjs");

if (!fs.existsSync(canonical)) {
  console.error(`ClawJS canonical ADR reservation script not found: ${canonical}`);
  process.exit(1);
}

const result = spawnSync(process.execPath, [canonical, "--root", rootDir, ...process.argv.slice(2)], {
  cwd: rootDir,
  stdio: "inherit",
  env: process.env,
});

process.exitCode = result.status ?? 1;
