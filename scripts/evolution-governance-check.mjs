#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const result = spawnSync(process.execPath, [
  path.join(rootDir, "scripts/evolution_rescue_mirror_check.mjs"),
  ...process.argv.slice(2),
], {
  cwd: rootDir,
  stdio: "inherit",
  env: process.env,
});

process.exitCode = result.status ?? 1;
