#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const outputs = ["guard/test añadido", "ADR/regla añadida", "deuda explícita con expiry"];
const required = new Map([
  ["docs/adr/0032-problem-to-guardrail-loop-mirror.md", [
    "Problem-to-Guardrail loop mirror",
    ...outputs,
    "punctual problem",
    "general class",
    "existing rule",
  ]],
  ["docs/decision-map.md", [
    "Problem-to-Guardrail",
    ...outputs,
    "scripts/problem_to_guardrail_check.mjs",
  ]],
  ["docs/agent-rules/index.md", [
    "Problem-to-Guardrail loop",
    ...outputs,
  ]],
  ["docs/adr/TEMPLATE.md", outputs],
  ["skills/adr-to-guardrail/SKILL.md", outputs],
  ["skills/code-review-risk/SKILL.md", outputs],
  ["docs/adr-operational-coverage.manifest.json", [
    "docs/adr/0032-problem-to-guardrail-loop-mirror.md",
    "scripts/problem_to_guardrail_check.mjs",
  ]],
  ["scripts/test.sh", ["problem_to_guardrail_check.mjs"]],
]);

function read(relativePath, overrides = new Map()) {
  return overrides.get(relativePath) ?? fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function validate(overrides = new Map()) {
  const failures = [];
  for (const [relativePath, snippets] of required) {
    const filePath = path.join(rootDir, relativePath);
    if (!fs.existsSync(filePath)) {
      failures.push(`missing ${relativePath}`);
      continue;
    }
    const text = read(relativePath, overrides);
    for (const snippet of snippets.flat()) {
      if (!text.includes(snippet)) failures.push(`${relativePath} must include ${JSON.stringify(snippet)}`);
    }
  }
  return failures;
}

function runSelfTest() {
  assert.deepEqual(validate(), []);
  const broken = new Map([[
    "docs/agent-rules/index.md",
    read("docs/agent-rules/index.md").replaceAll("guard/test añadido", "fixed locally"),
  ]]);
  assert.match(validate(broken).join("\n"), /guard\/test añadido/);
}

if (process.argv.includes("--self-test")) {
  const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname], {
    cwd: rootDir,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr);
  runSelfTest();
  console.log("problem-to-guardrail check self-test passed");
  process.exit(0);
}

const failures = validate();
if (failures.length > 0) {
  console.error("problem-to-guardrail check failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("problem-to-guardrail check passed");
