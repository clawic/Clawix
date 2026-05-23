#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const releaseTargets = new Set(["macos-release", "ios-release", "linux-release", "windows-release", "web-release"]);
const phases = new Set(["preflight", "publish"]);
const acceptedExternalStatuses = new Set([
  "pass",
  "passed",
  "validated",
  "validated-local",
  "validated-private",
  "verified",
  "verified-complete",
]);
const acceptedEvidenceStatuses = new Set(["accepted", "pass", "passed", "validated", "verified", "verified-complete"]);
const evidenceRefTypes = new Set(["path", "command", "hash", "attestation", "capture", "log", "validation"]);
const contractSourcePattern = /^(docs\/|playbooks\/|qa\/|scripts\/|macos\/scripts\/|ios\/scripts\/|linux\/scripts\/|windows\/scripts\/|RELEASING\.md$|STYLE\.md$|SAFETY\.md$|REGULATED_DOMAINS\.md$)/u;

function read(relativePath, baseDir = rootDir) {
  return fs.readFileSync(path.join(baseDir, relativePath), "utf8");
}

function readJson(relativePath, baseDir = rootDir) {
  return JSON.parse(read(relativePath, baseDir));
}

function exists(relativePath, baseDir = rootDir) {
  return fs.existsSync(path.join(baseDir, relativePath));
}

function normalizeStatus(status) {
  return String(status || "").trim().toLowerCase().replace(/[_ ]/g, "-");
}

function splitList(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed || trimmed === "none") return [];
  return trimmed
    .split(",")
    .map((item) => item.trim().replace(/^`|`$/g, ""))
    .filter(Boolean);
}

function markdownCells(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

function sectionBetween(text, heading) {
  const start = text.indexOf(heading);
  if (start === -1) return "";
  const remainder = text.slice(start);
  const nextHeading = remainder.slice(1).search(/\n## /);
  return nextHeading === -1 ? remainder : remainder.slice(0, nextHeading + 1);
}

function extractGoalCompletionImpactRows(text, sourcePath, failures) {
  const section = sectionBetween(text, "## Goal Completion Impact");
  if (!section) {
    failures.push(`${sourcePath}: missing ## Goal Completion Impact section`);
    return [];
  }
  const tableLines = section
    .split("\n")
    .filter((line) => line.trim().startsWith("|") && !/^\|\s*-+/.test(line));
  if (tableLines.length < 2) {
    failures.push(`${sourcePath}: goal completion impact table must include a header and rows`);
    return [];
  }
  const expectedHeaders = [
    "External pending row",
    "linkedPromiseIds",
    "linkedDecisionIds",
    "completionImpact",
    "closureEffect",
    "reentryCondition",
    "evidenceRequired",
  ];
  const headers = markdownCells(tableLines[0]);
  if (headers.join("|") !== expectedHeaders.join("|")) {
    failures.push(`${sourcePath}: goal completion impact table headers must be ${expectedHeaders.join(", ")}`);
  }
  return tableLines.slice(1).map((line) => {
    const cells = markdownCells(line);
    return {
      id: cells[0],
      sourcePath,
      linkedPromiseIds: splitList(cells[1]),
      linkedDecisionIds: splitList(cells[2]),
      completionImpact: cells[3],
      closureEffect: cells[4],
      reentryCondition: cells[5],
      evidenceRequired: splitList(cells[6]),
    };
  });
}

function findCurrentStatus(text, rowId) {
  for (const line of text.split("\n")) {
    if (!line.trim().startsWith("|")) continue;
    const cells = markdownCells(line);
    if (cells[0] !== rowId) continue;
    if (cells.length >= 7 && cells[3] && cells[4] && cells[5] && cells[6]) continue;
    return cells[cells.length - 1] || "";
  }
  return "";
}

function hasScopeRevision(row, ledgerText) {
  if (row.closureEffect !== "requires_scope_revision") return false;
  const escapedId = row.id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const explicitRevision = new RegExp(`${escapedId}[^\\n]*scope_revision|scope_revision[^\\n]*${escapedId}`);
  return ledgerText
    .split("\n")
    .some((line) => !line.trim().startsWith("|") && explicitRevision.test(line));
}

function loadExternalRows(manifest, baseDir, failures) {
  const rows = new Map();
  for (const sourcePath of manifest.sources?.externalPendingLedgers ?? []) {
    if (!exists(sourcePath, baseDir)) {
      failures.push(`missing external pending ledger: ${sourcePath}`);
      continue;
    }
    const text = read(sourcePath, baseDir);
    for (const row of extractGoalCompletionImpactRows(text, sourcePath, failures)) {
      const currentStatus = findCurrentStatus(text, row.id);
      rows.set(row.id, { ...row, currentStatus, ledgerText: text });
    }
  }
  return rows;
}

function normalizeBlockingRow(row, promise, failures) {
  if (typeof row === "string") {
    return { id: row, targets: promise.releaseTargets ?? [] };
  }
  if (!row || typeof row !== "object") {
    failures.push(`${promise.id}: blockingExternalRows entries must be strings or objects`);
    return { id: "", targets: [] };
  }
  return {
    id: row.id || "",
    targets: Array.isArray(row.targets) ? row.targets : [],
  };
}

function validateContractSource(source, label, failures) {
  if (typeof source !== "string" || source.trim() === "") {
    failures.push(`${label} entries must be non-empty strings`);
    return;
  }
  if (!exists(source)) failures.push(`${label}.${source} does not exist`);
}

function validateAcceptedEvidenceRef(ref, label, failures) {
  if (!ref || typeof ref !== "object" || Array.isArray(ref)) {
    failures.push(`${label} entries must be objects`);
    return;
  }
  if (!evidenceRefTypes.has(ref.type)) failures.push(`${label}.type must be one of ${[...evidenceRefTypes].join(", ")}`);
  if (typeof ref.ref !== "string" || ref.ref.trim() === "") {
    failures.push(`${label}.ref must be non-empty`);
    return;
  }
  if (ref.ref.includes("/Users/") || ref.ref.includes("file://")) failures.push(`${label}.${ref.ref} must be public-safe`);
  if (/\bfixture\b|synthetic_templates_not_evidence/iu.test(ref.ref)) failures.push(`${label}.${ref.ref} cannot cite fixtures or synthetic templates as real evidence`);
  if (contractSourcePattern.test(ref.ref)) failures.push(`${label}.${ref.ref} is a contract source; use contractSources instead`);
  if (ref.type === "path" && !exists(ref.ref)) failures.push(`${label}.${ref.ref} path does not exist`);
  if (ref.type === "hash" && !/^sha256:[a-f0-9]{64}$/u.test(ref.ref)) failures.push(`${label}.${ref.ref} must be sha256:<64 lowercase hex>`);
  if ((ref.type === "command" || ref.type === "validation") && !/^(node scripts\/|bash scripts\/|bash macos\/scripts\/|bash ios\/scripts\/|bash linux\/scripts\/|pwsh windows\/scripts\/|npm run |swift test |claw verify )/u.test(ref.ref)) {
    failures.push(`${label}.${ref.ref} must be a known validation command`);
  }
}

function commandLabel(command) {
  return (command?.argv ?? []).join(" ");
}

function validateCommandRequirement(target, requirement, failures) {
  const command = requirement.command;
  if (!command || typeof command !== "object" || Array.isArray(command)) {
    failures.push(`${target}.${requirement.id}: command requirement must define command`);
    return;
  }
  if (!Array.isArray(command.argv) || command.argv.length === 0 || command.argv.some((part) => typeof part !== "string" || part.trim() === "")) {
    failures.push(`${target}.${requirement.id}: command.argv must be a non-empty string array`);
  }
  if (typeof command.cwd !== "string" || command.cwd.trim() === "") {
    failures.push(`${target}.${requirement.id}: command.cwd must be a non-empty string`);
  }
  if (!Array.isArray(command.requiredEnv) || command.requiredEnv.some((name) => typeof name !== "string" || name.trim() === "")) {
    failures.push(`${target}.${requirement.id}: command.requiredEnv must be an array of environment variable names`);
  }
}

function validateExternalEvidenceRequirement(target, requirement, failures) {
  const evidence = requirement.externalEvidence;
  if (!evidence || typeof evidence !== "object" || Array.isArray(evidence)) {
    failures.push(`${target}.${requirement.id}: externalEvidence requirement must define externalEvidence`);
    return;
  }
  for (const field of ["blockerId", "evidenceKind", "verifier"]) {
    if (typeof evidence[field] !== "string" || evidence[field].trim() === "") {
      failures.push(`${target}.${requirement.id}: externalEvidence.${field} must be a non-empty string`);
    }
  }
}

function validateTargetContracts(manifest, failures) {
  const contracts = manifest.targetContracts;
  if (!Array.isArray(contracts) || contracts.length === 0) {
    failures.push("targetContracts must be a non-empty array");
    return;
  }

  const targetsWithContracts = new Set();
  for (const contract of contracts) {
    if (!contract || typeof contract !== "object" || Array.isArray(contract)) {
      failures.push("targetContracts entries must be objects");
      continue;
    }
    const target = contract.target;
    if (!releaseTargets.has(target)) failures.push(`unsupported target contract: ${target}`);
    if (targetsWithContracts.has(target)) failures.push(`duplicate target contract: ${target}`);
    targetsWithContracts.add(target);
    if (!Array.isArray(contract.requirements) || contract.requirements.length === 0) {
      failures.push(`${target}: requirements must be a non-empty array`);
      continue;
    }
    if (!contract.requirements.some((requirement) => requirement?.kind === "command" && commandLabel(requirement.command).includes("scripts/debt_control_baseline_check.mjs"))) {
      failures.push(`${target}: target contract must include scripts/debt_control_baseline_check.mjs`);
    }
    const requirementIds = new Set();
    for (const requirement of contract.requirements) {
      if (!requirement || typeof requirement !== "object" || Array.isArray(requirement)) {
        failures.push(`${target}: requirements entries must be objects`);
        continue;
      }
      if (typeof requirement.id !== "string" || requirement.id.trim() === "") {
        failures.push(`${target}: each requirement needs an id`);
        continue;
      }
      if (requirementIds.has(requirement.id)) failures.push(`${target}: duplicate requirement id ${requirement.id}`);
      requirementIds.add(requirement.id);
      if (!phases.has(requirement.phase)) failures.push(`${target}.${requirement.id}: phase must be preflight or publish`);
      if (!["command", "externalEvidence"].includes(requirement.kind)) {
        failures.push(`${target}.${requirement.id}: kind must be command or externalEvidence`);
        continue;
      }
      if (requirement.kind === "command") validateCommandRequirement(target, requirement, failures);
      if (requirement.kind === "externalEvidence") validateExternalEvidenceRequirement(target, requirement, failures);
      if (requirement.kind === "command" && requirement.externalEvidence) {
        failures.push(`${target}.${requirement.id}: command requirements must not also define externalEvidence`);
      }
      if (requirement.kind === "externalEvidence" && requirement.command) {
        failures.push(`${target}.${requirement.id}: externalEvidence requirements must not also define command`);
      }
    }
  }

  for (const target of manifest.releaseTargets ?? []) {
    if (!targetsWithContracts.has(target)) failures.push(`${target}: missing executable target contract`);
  }
}

function validateManifest(manifest, assertionEnvelope, externalRows, failures, options = {}) {
  if (manifest.schemaVersion !== 2) failures.push("schemaVersion must be 2");
  if (manifest.scope !== "v1-central-promises") failures.push("scope must be v1-central-promises");
  if (!manifest.sources || typeof manifest.sources !== "object") failures.push("sources must be an object");
  if (manifest.sources?.constitutionAssertions !== "docs/constitution.assertions.json") {
    failures.push("sources.constitutionAssertions must be docs/constitution.assertions.json");
  }
  if (manifest.sources?.humanMatrix !== "docs/governance/release-readiness.md") {
    failures.push("sources.humanMatrix must be docs/governance/release-readiness.md");
  }
  if (manifest.sources?.debtControlBaselineCheck !== "scripts/debt_control_baseline_check.mjs") {
    failures.push("sources.debtControlBaselineCheck must be scripts/debt_control_baseline_check.mjs");
  }
  if (!Array.isArray(manifest.sources?.externalPendingLedgers)) {
    failures.push("sources.externalPendingLedgers must be an array");
  }
  if (!Array.isArray(manifest.releaseTargets)) failures.push("releaseTargets must be an array");
  for (const target of manifest.releaseTargets ?? []) {
    if (!releaseTargets.has(target)) failures.push(`unsupported release target: ${target}`);
  }
  if (manifest.statusRules?.requiredAssertionStatus !== "enforced") {
    failures.push("statusRules.requiredAssertionStatus must be enforced");
  }
  if (manifest.statusRules?.blockingCompletionImpact !== "central_promise_blocker") {
    failures.push("statusRules.blockingCompletionImpact must be central_promise_blocker");
  }
  if (!Array.isArray(manifest.promises) || manifest.promises.length === 0) {
    failures.push("promises must be a non-empty array");
  }
  validateTargetContracts(manifest, failures);

  const assertionById = new Map((assertionEnvelope.assertions ?? []).map((assertion) => [assertion.id, assertion]));
  const seenPromiseIds = new Set();
  for (const promise of manifest.promises ?? []) {
    if (!promise.id || typeof promise.id !== "string") failures.push("each promise needs an id");
    if (seenPromiseIds.has(promise.id)) failures.push(`duplicate promise id: ${promise.id}`);
    seenPromiseIds.add(promise.id);
    if (!promise.title || typeof promise.title !== "string") failures.push(`${promise.id}: title is required`);
    if (!Array.isArray(promise.constitutionalAssertionIds) || promise.constitutionalAssertionIds.length === 0) {
      failures.push(`${promise.id}: constitutionalAssertionIds must be non-empty`);
    }
    if (!Array.isArray(promise.releaseTargets) || promise.releaseTargets.length === 0) {
      failures.push(`${promise.id}: releaseTargets must be non-empty`);
    }
    for (const target of promise.releaseTargets ?? []) {
      if (!releaseTargets.has(target)) failures.push(`${promise.id}: unsupported release target ${target}`);
    }
    for (const assertionId of promise.constitutionalAssertionIds ?? []) {
      if (!assertionById.has(assertionId)) failures.push(`${promise.id}: missing constitutional assertion ${assertionId}`);
    }
    if (!Array.isArray(promise.blockingExternalRows)) {
      failures.push(`${promise.id}: blockingExternalRows must be an array`);
    }
    for (const rawRow of promise.blockingExternalRows ?? []) {
      const row = normalizeBlockingRow(rawRow, promise, failures);
      if (!row.id) {
        failures.push(`${promise.id}: blocking external row missing id`);
        continue;
      }
      if (!externalRows.has(row.id)) {
        failures.push(`${promise.id}: blocking external row ${row.id} is not present in configured ledgers`);
        continue;
      }
      const externalRow = externalRows.get(row.id);
      if (externalRow.completionImpact !== "central_promise_blocker") {
        failures.push(`${promise.id}: blocking external row ${row.id} is ${externalRow.completionImpact}, expected central_promise_blocker`);
      }
      if (row.targets.length === 0) failures.push(`${promise.id}: blocking external row ${row.id} must list targets`);
      for (const target of row.targets) {
        if (!releaseTargets.has(target)) failures.push(`${promise.id}: blocking external row ${row.id} has unsupported target ${target}`);
        if (!(promise.releaseTargets ?? []).includes(target)) {
          failures.push(`${promise.id}: blocking external row ${row.id} target ${target} is outside the promise targets`);
        }
      }
    }
    if (promise.evidenceSources !== undefined) {
      failures.push(`${promise.id}: evidenceSources is retired; use contractSources and acceptedEvidenceRefs`);
    }
    if (!Array.isArray(promise.contractSources) || promise.contractSources.length === 0) {
      failures.push(`${promise.id}: contractSources must be non-empty`);
    }
    for (const source of promise.contractSources ?? []) validateContractSource(source, `${promise.id}.contractSources`, failures);
    if (!Array.isArray(promise.acceptedEvidenceRefs)) {
      failures.push(`${promise.id}: acceptedEvidenceRefs must be an array`);
    }
    for (const ref of promise.acceptedEvidenceRefs ?? []) validateAcceptedEvidenceRef(ref, `${promise.id}.acceptedEvidenceRefs`, failures);
    if (!promise.releaseRule || typeof promise.releaseRule !== "string") {
      failures.push(`${promise.id}: releaseRule is required`);
    }
  }

  if (!options.skipDocs) validateDocRouting(failures);
}

function validateDocRouting(failures) {
  const required = [
    ["docs/governance/release-readiness.md", "release-readiness.manifest.json"],
    ["docs/governance/README.md", "Release Readiness"],
    ["docs/decision-map.md", "target contract"],
    ["docs/constitution-map.md", "release-readiness.md"],
    ["RELEASING.md", "release_readiness_check.mjs --target <target> --phase preflight --run"],
    ["docs/discoverability.md", "executable release readiness contract"],
    ["docs/discoverability.registry.json", "executable release readiness contract"],
    ["scripts/test.sh", "release_readiness_check.mjs"],
    ["scripts/test.sh", "debt_control_baseline_check.mjs"],
  ];
  for (const [relativePath, snippet] of required) {
    if (!exists(relativePath)) {
      failures.push(`missing routed document: ${relativePath}`);
      continue;
    }
    if (!read(relativePath).includes(snippet)) {
      failures.push(`${relativePath} is missing required snippet: ${snippet}`);
    }
  }
}

function targetReadinessFailures(manifest, assertionEnvelope, externalRows, target) {
  const failures = [];
  const assertionById = new Map((assertionEnvelope.assertions ?? []).map((assertion) => [assertion.id, assertion]));
  const requiredStatus = manifest.statusRules.requiredAssertionStatus;

  for (const promise of manifest.promises) {
    if (!promise.releaseTargets.includes(target)) continue;
    for (const assertionId of promise.constitutionalAssertionIds) {
      const assertion = assertionById.get(assertionId);
      if (!assertion) continue;
      if (assertion.status !== requiredStatus) {
        failures.push(`${promise.id} blocks ${target}: ${assertionId} is ${assertion.status}, expected ${requiredStatus}`);
      }
    }
    for (const rawRow of promise.blockingExternalRows ?? []) {
      const row = normalizeBlockingRow(rawRow, promise, failures);
      if (!row.targets.includes(target)) continue;
      const externalRow = externalRows.get(row.id);
      if (!externalRow) continue;
      const status = normalizeStatus(externalRow.currentStatus);
      if (status !== "external-pending") continue;
      if (acceptedExternalStatuses.has(status) || hasScopeRevision(externalRow, externalRow.ledgerText)) continue;
      failures.push(`${promise.id} blocks ${target}: ${row.id} remains EXTERNAL PENDING in ${externalRow.sourcePath}`);
    }
  }

  return failures;
}

function contractForTarget(manifest, target) {
  return (manifest.targetContracts ?? []).find((contract) => contract.target === target);
}

function requirementInPhase(requirement, phase) {
  if (phase === "publish") return requirement.phase === "preflight" || requirement.phase === "publish";
  return requirement.phase === "preflight";
}

function executeCommandRequirement(requirement) {
  const command = requirement.command;
  const missingEnv = (command.requiredEnv ?? []).filter((name) => !process.env[name]);
  if (missingEnv.length > 0) {
    return {
      status: "blocked",
      output: "",
      reason: `missing required env: ${missingEnv.join(", ")}`,
    };
  }
  const argv = command.argv;
  const cwd = path.resolve(rootDir, command.cwd);
  const result = spawnSync(argv[0], argv.slice(1), {
    cwd,
    env: process.env,
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 20,
  });
  const output = `${result.stdout || ""}${result.stderr || ""}`;
  if (result.error) {
    return { status: "failed", output, reason: result.error.message };
  }
  if (result.status === 2 || output.includes("EXTERNAL PENDING")) {
    return {
      status: "blocked",
      output,
      reason: result.status === 2 ? "command exited with EXTERNAL PENDING status 2" : "command output contains EXTERNAL PENDING",
    };
  }
  if (result.status !== 0) {
    return { status: "failed", output, reason: `command exited with status ${result.status}` };
  }
  return { status: "passed", output, reason: "" };
}

function evaluateTargetContract(manifest, target, phase, options = {}) {
  const checks = [];
  const blockers = [];
  const contract = contractForTarget(manifest, target);
  if (!contract) {
    const blocker = `${target}: missing executable target contract`;
    return { checks, blockers: [blocker] };
  }

  for (const requirement of contract.requirements.filter((item) => requirementInPhase(item, phase))) {
    if (requirement.kind === "command") {
      const check = {
        id: requirement.id,
        kind: requirement.kind,
        phase: requirement.phase,
        command: commandLabel(requirement.command),
        status: options.run ? "pending" : "declared",
      };
      if (options.run) {
        const result = executeCommandRequirement(requirement);
        check.status = result.status;
        check.reason = result.reason;
        if (result.status !== "passed") blockers.push(`${requirement.id} blocks ${target}: ${result.reason}`);
      }
      checks.push(check);
      continue;
    }

    const evidence = requirement.externalEvidence;
    const status = normalizeStatus(evidence.status);
    const accepted = acceptedEvidenceStatuses.has(status);
    const check = {
      id: requirement.id,
      kind: requirement.kind,
      phase: requirement.phase,
      evidenceKind: evidence.evidenceKind,
      verifier: evidence.verifier,
      status: accepted ? "accepted" : "blocked",
    };
    checks.push(check);
    if (!accepted) {
      blockers.push(`${requirement.id} blocks ${target}: missing ${evidence.evidenceKind} (${evidence.verifier})`);
    }
  }

  return { checks, blockers };
}

function parseArgs() {
  let target = "";
  let phase = "preflight";
  let selfTest = false;
  let run = false;
  let json = false;
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--self-test") {
      selfTest = true;
      continue;
    }
    if (arg === "--run") {
      run = true;
      continue;
    }
    if (arg === "--json") {
      json = true;
      continue;
    }
    if (arg === "--target") {
      target = args[index + 1] || "";
      index += 1;
      continue;
    }
    if (arg.startsWith("--target=")) {
      target = arg.slice("--target=".length);
      continue;
    }
    if (arg === "--phase") {
      phase = args[index + 1] || "";
      index += 1;
      continue;
    }
    if (arg.startsWith("--phase=")) {
      phase = arg.slice("--phase=".length);
      continue;
    }
    throw new Error(`unknown argument: ${arg}`);
  }
  return { target, phase, selfTest, run, json };
}

function fixtureEnvelope() {
  return {
    assertions: [
      { id: "A.enforced", status: "enforced" },
      { id: "B.partial", status: "partial" },
      { id: "C.external", status: "external-pending" },
    ],
  };
}

function fixtureExternalRows(failures) {
  const text = `| ID | Requirement | Local evidence | Missing prerequisite | Status |
| --- | --- | --- | --- | --- |
| FIX-CENTRAL | Central promise | local | signed host | EXTERNAL PENDING |
| FIX-DONE | Complete promise | local | none | VALIDATED LOCAL |

## Goal Completion Impact

| External pending row | linkedPromiseIds | linkedDecisionIds | completionImpact | closureEffect | reentryCondition | evidenceRequired |
| --- | --- | --- | --- | --- | --- | --- |
| FIX-CENTRAL | promise.native | D1 | central_promise_blocker | blocks_goal | signed host available | signed-host receipt |
| FIX-DONE | promise.native | D2 | central_promise_blocker | blocks_goal | none | signed-host receipt |`;
  return new Map(extractGoalCompletionImpactRows(text, "fixture.md", failures).map((row) => [
    row.id,
    { ...row, currentStatus: findCurrentStatus(text, row.id), ledgerText: text },
  ]));
}

function fixtureManifest(overrides = {}) {
  return {
    schemaVersion: 2,
    scope: "v1-central-promises",
    sources: {
      constitutionAssertions: "docs/constitution.assertions.json",
      humanMatrix: "docs/governance/release-readiness.md",
      debtControlBaselineCheck: "scripts/debt_control_baseline_check.mjs",
      externalPendingLedgers: ["fixture.md"],
    },
    releaseTargets: ["macos-release"],
    statusRules: {
      requiredAssertionStatus: "enforced",
      blockingExternalStatus: "EXTERNAL PENDING",
      blockingCompletionImpact: "central_promise_blocker",
    },
    targetContracts: [
      {
        target: "macos-release",
        requirements: [
          {
            id: "fixture.local",
            kind: "command",
            phase: "preflight",
            command: { cwd: ".", argv: ["node", "-e", "process.exit(0)"], requiredEnv: [] },
          },
          {
            id: "fixture.debt-control",
            kind: "command",
            phase: "preflight",
            command: { cwd: ".", argv: ["node", "scripts/debt_control_baseline_check.mjs"], requiredEnv: [] },
          },
          {
            id: "fixture.notarization",
            kind: "externalEvidence",
            phase: "publish",
            externalEvidence: {
              blockerId: "fixture.notarization",
              evidenceKind: "notarization receipt",
              verifier: "fixture verifier",
            },
          },
          {
            id: "fixture.device",
            kind: "externalEvidence",
            phase: "publish",
            externalEvidence: {
              blockerId: "fixture.device",
              evidenceKind: "device test receipt",
              verifier: "fixture verifier",
            },
          },
          {
            id: "fixture.sbom",
            kind: "externalEvidence",
            phase: "publish",
            externalEvidence: {
              blockerId: "fixture.sbom",
              evidenceKind: "CycloneDX JSON SBOM",
              verifier: "fixture verifier",
            },
          },
          {
            id: "fixture.provenance",
            kind: "externalEvidence",
            phase: "publish",
            externalEvidence: {
              blockerId: "fixture.provenance",
              evidenceKind: "provenance attestation",
              verifier: "fixture verifier",
            },
          },
          {
            id: "fixture.accessibility",
            kind: "externalEvidence",
            phase: "publish",
            externalEvidence: {
              blockerId: "fixture.accessibility",
              evidenceKind: "manual accessibility receipt",
              verifier: "fixture verifier",
            },
          },
        ],
      },
    ],
    promises: [
      {
        id: "fixture-promise",
        title: "Fixture promise",
        constitutionalAssertionIds: ["A.enforced"],
        releaseTargets: ["macos-release"],
        blockingExternalRows: [],
        contractSources: ["docs/governance/release-readiness.md"],
        acceptedEvidenceRefs: [],
        releaseRule: "Fixture rule.",
        ...(overrides.promise ?? {}),
      },
    ],
    ...overrides.manifest,
  };
}

function expectFailure(name, run, expectedPattern) {
  const failures = run();
  if (!failures.some((failure) => expectedPattern.test(failure))) {
    throw new Error(`${name}: expected failure matching ${expectedPattern}, got ${failures.join("; ") || "<none>"}`);
  }
}

function runSelfTest() {
  const envelope = fixtureEnvelope();
  const setupFailures = [];
  const externalRows = fixtureExternalRows(setupFailures);
  if (setupFailures.length > 0) throw new Error(`fixture setup failed: ${setupFailures.join("; ")}`);

  let failures = [];
  validateManifest(fixtureManifest(), envelope, externalRows, failures, { skipDocs: true });
  if (failures.length > 0) throw new Error(`valid fixture failed shape validation: ${failures.join("; ")}`);
  failures = targetReadinessFailures(fixtureManifest(), envelope, externalRows, "macos-release");
  if (failures.length > 0) throw new Error(`valid fixture failed target readiness: ${failures.join("; ")}`);

  expectFailure("target without contract blocks", () => {
    const manifest = fixtureManifest({ manifest: { releaseTargets: ["macos-release", "ios-release"] } });
    const shapeFailures = [];
    validateManifest(manifest, envelope, externalRows, shapeFailures, { skipDocs: true });
    return shapeFailures;
  }, /ios-release: missing executable target contract/);

  expectFailure("document-only requirement blocks shape validation", () => {
    const manifest = fixtureManifest({
      manifest: {
        targetContracts: [{ target: "macos-release", requirements: [{ id: "doc.only", phase: "preflight" }] }],
      },
    });
    const shapeFailures = [];
    validateManifest(manifest, envelope, externalRows, shapeFailures, { skipDocs: true });
    return shapeFailures;
  }, /kind must be command or externalEvidence/);

  expectFailure("target contract without debt control check blocks shape validation", () => {
    const manifest = fixtureManifest({
      manifest: {
        targetContracts: [{
          target: "macos-release",
          requirements: [{
            id: "fixture.local",
            kind: "command",
            phase: "preflight",
            command: { cwd: ".", argv: ["node", "-e", "process.exit(0)"], requiredEnv: [] },
          }],
        }],
      },
    });
    const shapeFailures = [];
    validateManifest(manifest, envelope, externalRows, shapeFailures, { skipDocs: true });
    return shapeFailures;
  }, /debt_control_baseline_check/);

  expectFailure("partial assertion blocks release", () => {
    const manifest = fixtureManifest({ promise: { constitutionalAssertionIds: ["B.partial"] } });
    return targetReadinessFailures(manifest, envelope, externalRows, "macos-release");
  }, /B\.partial is partial/);

  expectFailure("external-pending assertion blocks release", () => {
    const manifest = fixtureManifest({ promise: { constitutionalAssertionIds: ["C.external"] } });
    return targetReadinessFailures(manifest, envelope, externalRows, "macos-release");
  }, /C\.external is external-pending/);

  expectFailure("missing assertion fails shape validation", () => {
    const manifest = fixtureManifest({ promise: { constitutionalAssertionIds: ["missing.assertion"] } });
    const shapeFailures = [];
    validateManifest(manifest, envelope, externalRows, shapeFailures, { skipDocs: true });
    return shapeFailures;
  }, /missing constitutional assertion/);

  expectFailure("unresolved central blocker blocks release", () => {
    const manifest = fixtureManifest({
      promise: { blockingExternalRows: [{ id: "FIX-CENTRAL", targets: ["macos-release"] }] },
    });
    return targetReadinessFailures(manifest, envelope, externalRows, "macos-release");
  }, /FIX-CENTRAL remains EXTERNAL PENDING/);

  expectFailure("contract docs cannot be accepted evidence", () => {
    const manifest = fixtureManifest({
      promise: { acceptedEvidenceRefs: [{ type: "path", ref: "docs/governance/release-readiness.md" }] },
    });
    const shapeFailures = [];
    validateManifest(manifest, envelope, externalRows, shapeFailures, { skipDocs: true });
    return shapeFailures;
  }, /is a contract source/);

  for (const [name, pattern] of [
    ["notarization absent blocks publish", /fixture\.notarization blocks macos-release/],
    ["device test absent blocks publish", /fixture\.device blocks macos-release/],
    ["SBOM absent blocks publish", /fixture\.sbom blocks macos-release/],
    ["provenance absent blocks publish", /fixture\.provenance blocks macos-release/],
    ["accessibility manual absent blocks publish", /fixture\.accessibility blocks macos-release/],
  ]) {
    expectFailure(name, () => evaluateTargetContract(fixtureManifest(), "macos-release", "publish").blockers, pattern);
  }

  expectFailure("EXTERNAL PENDING command output blocks release", () => {
    const manifest = fixtureManifest({
      manifest: {
        targetContracts: [{
          target: "macos-release",
          requirements: [{
            id: "fixture.debt-control",
            kind: "command",
            phase: "preflight",
            command: { cwd: ".", argv: ["node", "scripts/debt_control_baseline_check.mjs"], requiredEnv: [] },
          }, {
            id: "fixture.pending-command",
            kind: "command",
            phase: "preflight",
            command: { cwd: ".", argv: ["node", "-e", "console.error('EXTERNAL PENDING fixture')"], requiredEnv: [] },
          }],
        }],
      },
    });
    return evaluateTargetContract(manifest, "macos-release", "preflight", { run: true }).blockers;
  }, /fixture\.pending-command blocks macos-release/);

  const acceptedManifest = fixtureManifest({
    manifest: {
      targetContracts: [{
        target: "macos-release",
        requirements: [{
          id: "fixture.accepted",
          kind: "externalEvidence",
          phase: "publish",
          externalEvidence: {
            blockerId: "fixture.accepted",
            evidenceKind: "accepted evidence",
            verifier: "fixture verifier",
            status: "accepted",
          },
        }],
      }],
    },
  });
  const accepted = evaluateTargetContract(acceptedManifest, "macos-release", "publish");
  if (accepted.blockers.length > 0 || accepted.checks[0]?.status !== "accepted") {
    throw new Error("accepted external evidence should unlock only its requirement");
  }
}

function resultPayload({ target, phase, run, shapeFailures, targetFailures, contractChecks, contractBlockers }) {
  const blockers = [...shapeFailures, ...targetFailures, ...contractBlockers];
  return {
    status: blockers.length > 0 ? "blocked" : "passed",
    target: target || null,
    phase,
    run,
    checks: contractChecks,
    blockers,
  };
}

function main() {
  const { target, phase, selfTest, run, json } = parseArgs();
  if (selfTest) {
    runSelfTest();
    console.log("Release readiness self-test passed");
    return;
  }

  const shapeFailures = [];
  const targetFailures = [];
  let contractChecks = [];
  let contractBlockers = [];
  if (target && !releaseTargets.has(target)) shapeFailures.push(`unsupported release target: ${target}`);
  if (!phases.has(phase)) shapeFailures.push(`unsupported phase: ${phase}`);
  const manifest = readJson("docs/governance/release-readiness.manifest.json");
  const assertionEnvelope = readJson(manifest.sources?.constitutionAssertions ?? "docs/constitution.assertions.json");
  const externalRows = loadExternalRows(manifest, rootDir, shapeFailures);
  validateManifest(manifest, assertionEnvelope, externalRows, shapeFailures);
  if (target && shapeFailures.length === 0) {
    targetFailures.push(...targetReadinessFailures(manifest, assertionEnvelope, externalRows, target));
    const contractResult = evaluateTargetContract(manifest, target, phase, { run });
    contractChecks = contractResult.checks;
    contractBlockers = contractResult.blockers;
  }

  const payload = resultPayload({ target, phase, run, shapeFailures, targetFailures, contractChecks, contractBlockers });
  if (json) {
    console.log(JSON.stringify(payload, null, 2));
  }
  if (payload.blockers.length > 0) {
    if (!json) {
      console.error("Release readiness check failed:");
      for (const failure of payload.blockers) console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  if (!json) {
    console.log(target
      ? `Release readiness passed for ${target} (${phase}${run ? ", run" : ""})`
      : "Release readiness manifest passed");
  }
}

try {
  main();
} catch (error) {
  console.error("Release readiness check failed:");
  console.error(`- ${error.message}`);
  process.exit(1);
}
