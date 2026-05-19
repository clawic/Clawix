#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { enforcePrivateVerifierArgs } from "./ui_private_verifier_args.mjs";
import { privateSliceOption } from "./ui_private_slice_scope.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_UI_VISUAL_VERIFY_SELF_TEST === "1";

function hasFlag(name) {
  return args.includes(name);
}

const requireApproved = hasFlag("--require-approved");
const includePending = hasFlag("--include-pending");
const sliceIndex = args.indexOf("--slice");
const sliceArgs = sliceIndex === -1 ? [] : ["--slice", args[sliceIndex + 1] || ""];
privateSliceOption(args, (message) => {
  console.error(message);
  process.exit(1);
}, "UI private visual verification");

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

const validationManifest = readJson("docs/ui/private-visual-validation.manifest.json");
const requiredRoots = Array.isArray(validationManifest.requiredRoots) ? validationManifest.requiredRoots : [];
const delegateCommands = Array.isArray(validationManifest.delegates) ? validationManifest.delegates : [];

function parseDelegate(command) {
  const parts = String(command || "").trim().split(/\s+/).filter(Boolean);
  const [runtime, script, ...delegateArgs] = parts;
  if (runtime !== "node" || !script?.startsWith("scripts/ui_private_") || script.includes("..")) {
    throw new Error(`invalid private visual delegate command: ${command}`);
  }
  if (!delegateArgs.includes("--require-approved")) {
    throw new Error(`private visual delegate must require approval: ${command}`);
  }
  if (sliceArgs.length > 0 && script === "scripts/ui_private_debt_audit_verify.mjs") {
    return null;
  }
  const delegateSliceArgs = sliceArgs.length > 0 && script !== "scripts/ui_private_approval_verify.mjs" ? sliceArgs : [];
  return {
    script,
    args: [
      ...delegateArgs,
      ...(includePending && !delegateArgs.includes("--include-pending") ? ["--include-pending"] : []),
      ...delegateSliceArgs,
    ],
  };
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_VISUAL_VERIFY_SELF_TEST: "1",
  };
  for (const envName of requiredRoots) {
    delete selfTestEnv[envName];
  }
  delete selfTestEnv.CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE;
  const tests = [
    [[], "requires --require-approved"],
    [["--require-approved", "--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--require-approved", "--include-pending"], "CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE"],
    [["--require-approved"], "EXTERNAL PENDING"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      console.error(`UI private visual verification self-test ${testArgs.join(" ") || "<no args>"} must fail.`);
      process.exit(1);
    }
    if (!output.includes(expectedOutput)) {
      console.error(`UI private visual verification self-test ${testArgs.join(" ") || "<no args>"} output must include ${expectedOutput}.`);
      process.exit(1);
    }
  }
}

if (!requireApproved) {
  console.error("UI private visual verification requires --require-approved.");
  process.exit(1);
}
enforcePrivateVerifierArgs(args, {
  label: "UI private visual verification",
  allowedFlags: ["--require-approved", "--include-pending", "--slice"],
  optionsWithValues: ["--slice"],
  testOnlyFlags: ["--include-pending"],
});

if (!isSelfTest) {
  runFailureSelfTests();
}

const missingRoots = requiredRoots.filter((envName) => !process.env[envName]);
if (missingRoots.length > 0) {
  console.error(`EXTERNAL PENDING: set ${missingRoots.join(", ")} to verify private UI evidence.`);
  process.exit(2);
}

for (const delegateCommand of delegateCommands) {
  const delegate = parseDelegate(delegateCommand);
  if (!delegate) continue;
  const result = spawnSync(process.execPath, [path.join(rootDir, delegate.script), ...delegate.args], {
    cwd: rootDir,
    env: process.env,
    encoding: "utf8",
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    console.error(`UI private visual verification failed at ${delegate.script}.`);
    process.exit(result.status || 1);
  }
}

console.log("UI private visual verification passed");
