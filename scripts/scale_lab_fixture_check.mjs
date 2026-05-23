#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const clawixRoot = path.resolve(scriptDir, "..");
const defaultClawjsRoot = path.resolve(clawixRoot, "..", "..", "clawjs");
const clawjsRoot = process.env.CLAWJS_ROOT ? path.resolve(process.env.CLAWJS_ROOT) : defaultClawjsRoot;

if (!fs.existsSync(path.join(clawjsRoot, "scripts", "scale-lab.ts"))) {
  console.error(`EXTERNAL PENDING scale lab fixture: missing ClawJS scale lab at ${clawjsRoot}`);
  process.exit(2);
}

const scratchRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-scale-lab-fixture-"));
const reportPath = path.join(scratchRoot, "scale-lab-report.json");
const lockPath = path.join(scratchRoot, "scale.lock");
try {
  const result = spawnSync("npm", [
    "run",
    "scale:lab",
    "--",
    "--profile",
    "smoke",
    "--workload",
    "sessions,attachments",
    "--report",
    reportPath,
    "--lock",
    lockPath,
    "--json",
  ], {
    cwd: clawjsRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      CLAW_HOME: path.join(scratchRoot, "home"),
      CLAW_DATA_DIR: path.join(scratchRoot, "home", "data"),
    },
  });

  if (result.status !== 0) {
    process.stderr.write(result.stderr);
    process.stderr.write(result.stdout);
    process.exit(result.status ?? 1);
  }

  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  if (report.ok !== true) {
    console.error("Clawix scale lab fixture check failed: report is not ok");
    process.exit(1);
  }
  if (report.cleanup?.status !== "removed") {
    console.error("Clawix scale lab fixture check failed: Scale Lab did not clean up its temporary root");
    process.exit(1);
  }
  const workloadNames = new Set((report.workloads ?? []).map((workload) => workload.name));
  if (!workloadNames.has("sessions") || !workloadNames.has("attachments")) {
    console.error("Clawix scale lab fixture check failed: expected sessions and attachments workloads");
    process.exit(1);
  }
  console.log(JSON.stringify({
    ok: true,
    profile: report.profile,
    workloads: [...workloadNames],
    externalPending: report.externalPending,
  }, null, 2));
} finally {
  fs.rmSync(scratchRoot, { recursive: true, force: true });
}
