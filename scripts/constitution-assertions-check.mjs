#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const defaultRootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const rootArgIndex = args.indexOf("--root");
const rootDir = rootArgIndex === -1 ? defaultRootDir : path.resolve(args[rootArgIndex + 1]);
const selfTest = args.includes("--self-test");

const assertionPath = "docs/constitution.assertions.json";
const allowedEvidenceModes = new Set(["shape", "delegated", "fixture", "external-pending", "manual-review"]);
const allowedRepoScopes = new Set(["clawjs", "clawix", "shared"]);
const allowedStatuses = new Set(["enforced", "partial", "external-pending", "manual"]);
const allowedSurfaces = new Set([
  "audit",
  "bridge",
  "cli",
  "data",
  "docs",
  "host",
  "mcp",
  "mesh",
  "permissions",
  "relay",
  "runtime",
  "sdk",
  "security",
  "storage",
  "ui",
]);

const surfaceRoots = {
  audit: ["docs", "packages", "scripts", "apps"],
  bridge: ["bridge", "packages", "apps", "docs"],
  cli: ["packages", "scripts", "docs"],
  data: ["database", "packages", "docs"],
  docs: ["AGENTS.md", "CLAUDE.md", "README.md", "docs"],
  host: ["apps", "docs", "scripts"],
  mcp: ["mcp", "packages", "docs"],
  mesh: ["relay", "packages", "docs"],
  permissions: ["apps", "packages", "docs", "scripts"],
  relay: ["relay", "packages", "docs"],
  runtime: ["runtime", "packages", "docs"],
  sdk: ["packages", "docs", "examples"],
  security: ["secrets", "packages", "docs", "scripts"],
  storage: ["database", "packages", "docs", "apps"],
  ui: ["website", "examples", "docs", "apps"],
};

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function read(relativePath, base = rootDir) {
  return fs.readFileSync(path.join(base, relativePath), "utf8");
}

function exists(relativePath, base = rootDir) {
  return fs.existsSync(path.join(base, relativePath));
}

function readJson(relativePath, base = rootDir) {
  return JSON.parse(read(relativePath, base));
}

function contractDigest(envelope) {
  const identity = {
    schemaVersion: envelope.schemaVersion,
    contract: "constitution.assertions.v1",
    assertions: [...(envelope.assertions ?? [])]
      .map((entry) => ({
        id: entry.id,
        principle: entry.principle,
        summary: entry.summary,
        evidenceMode: entry.evidenceMode,
        repoScope: entry.repoScope,
        status: entry.status,
      }))
      .sort((a, b) => a.id.localeCompare(b.id)),
  };
  return sha256(stableJson(identity));
}

function section(text, startHeading, endHeading) {
  const start = text.indexOf(startHeading);
  if (start === -1) return "";
  const after = start + startHeading.length;
  const end = endHeading ? text.indexOf(endHeading, after) : -1;
  return text.slice(after, end === -1 ? text.length : end);
}

function constitutionCoverageIds(text) {
  const principles = section(text, "## Principles", "## Red lines");
  const redLines = section(text, "## Red lines", "## Tensions");
  const tensions = section(text, "## Tensions", "## Amendment process");
  const principleIds = [...principles.matchAll(/^\*\*([IVX]+\.\d+(?:\.\d+)?)\b/gm)].map((match) => match[1]);
  const redLineIds = [...redLines.matchAll(/^(\d+)\. \*\*/gm)].map((match) => `Red.${match[1]}`);
  const tensionIds = [...tensions.matchAll(/^(\d+)\. \*\*/gm)].map((match) => `Tension.${match[1]}`);
  return ["Preamble", ...principleIds, ...redLineIds, ...tensionIds, "Amendment"];
}

function listFiles(relativePath, base = rootDir, output = []) {
  const absolutePath = path.join(base, relativePath);
  if (!fs.existsSync(absolutePath)) return output;
  const stat = fs.statSync(absolutePath);
  if (stat.isFile()) {
    output.push(relativePath);
    return output;
  }
  if (!stat.isDirectory()) return output;
  for (const entry of fs.readdirSync(absolutePath, { withFileTypes: true })) {
    const child = path.join(relativePath, entry.name);
    if (entry.isDirectory()) {
      if (["node_modules", "dist", ".git", ".next", "coverage", "test-results", "artifacts"].includes(entry.name)) continue;
      listFiles(child, base, output);
    } else if (entry.isFile()) {
      output.push(child);
    }
  }
  return output;
}

function fileTextIfReadable(relativePath, base = rootDir) {
  const absolutePath = path.join(base, relativePath);
  try {
    const stat = fs.statSync(absolutePath);
    if (!stat.isFile() || stat.size > 1024 * 1024) return "";
    return fs.readFileSync(absolutePath, "utf8");
  } catch {
    return "";
  }
}

function testLaneText(base = rootDir) {
  const parts = [];
  for (const relativePath of ["package.json", "scripts/test.sh"]) {
    if (!exists(relativePath, base)) continue;
    parts.push(read(relativePath, base));
  }
  return parts.join("\n");
}

function normalizeForbiddenTerm(term) {
  if (typeof term === "string") return { term, type: "literal", surfaces: undefined, allowlist: [] };
  return { type: "literal", surfaces: undefined, allowlist: [], ...term };
}

function validateForbiddenTerms(envelope, failures, baseDir) {
  for (const assertion of envelope.assertions ?? []) {
    for (const rawTerm of assertion.forbiddenTerms ?? []) {
      const term = normalizeForbiddenTerm(rawTerm);
      if (!term.term || typeof term.term !== "string") {
        failures.push(`${assertion.id} has a forbidden term without a term string`);
        continue;
      }
      if (!["literal", "regex"].includes(term.type)) {
        failures.push(`${assertion.id} forbidden term ${term.term} has invalid type ${term.type}`);
        continue;
      }
      const surfaces = term.surfaces ?? assertion.affectedSurfaces ?? [];
      const roots = [...new Set(surfaces.flatMap((surface) => surfaceRoots[surface] ?? []))];
      const allowlist = new Map((term.allowlist ?? []).map((entry) => [entry.path, entry.reason]));
      const matcher = term.type === "regex" ? new RegExp(term.term) : term.term;
      for (const root of roots) {
        for (const file of listFiles(root, baseDir)) {
          if (file === assertionPath || file === "docs/constitution.assertions.schema.json") continue;
          const text = fileTextIfReadable(file, baseDir);
          const found = typeof matcher === "string" ? text.includes(matcher) : matcher.test(text);
          if (!found) continue;
          const reason = allowlist.get(file);
          if (!reason) {
            failures.push(`${assertion.id} forbidden term ${JSON.stringify(term.term)} found in ${file}`);
          } else if (typeof reason !== "string" || reason.trim().length < 8) {
            failures.push(`${assertion.id} allowlist for ${file} must include a reason`);
          }
        }
      }
    }
  }
}

function validateEnvelope(baseDir, options = {}) {
  const failures = [];
  const envelope = readJson(assertionPath, baseDir);
  const constitutionText = read("CONSTITUTION.md", baseDir);
  const expectedPrinciples = new Set(constitutionCoverageIds(constitutionText));
  const laneText = testLaneText(baseDir);

  if (envelope.schemaVersion !== 1) failures.push("schemaVersion must be 1");
  if (!Array.isArray(envelope.assertions)) failures.push("assertions must be an array");
  if (!Array.isArray(envelope.explicitlyDocumentedLanes)) failures.push("explicitlyDocumentedLanes must be an array");

  const seenIds = new Set();
  const seenPrinciples = new Set();
  for (const assertion of envelope.assertions ?? []) {
    for (const field of [
      "id",
      "principle",
      "summary",
      "forbiddenTerms",
      "affectedSurfaces",
      "canonicalDocs",
      "protectorScripts",
      "evidenceMode",
      "repoScope",
      "status",
    ]) {
      if (assertion[field] === undefined) failures.push(`${assertion.id ?? "<unknown>"} is missing ${field}`);
    }
    if (seenIds.has(assertion.id)) failures.push(`duplicate assertion id ${assertion.id}`);
    seenIds.add(assertion.id);
    seenPrinciples.add(assertion.principle);
    if (!expectedPrinciples.has(assertion.principle) && !options.allowExtraPrinciples) {
      failures.push(`${assertion.id} references principle ${assertion.principle} that is not in CONSTITUTION.md`);
    }
    if (typeof assertion.summary !== "string" || assertion.summary.length < 8) {
      failures.push(`${assertion.id} must have a useful summary`);
    }
    if (!Array.isArray(assertion.forbiddenTerms)) failures.push(`${assertion.id} forbiddenTerms must be an array`);
    if (!Array.isArray(assertion.affectedSurfaces) || assertion.affectedSurfaces.length === 0) {
      failures.push(`${assertion.id} affectedSurfaces must be a non-empty array`);
    } else {
      for (const surface of assertion.affectedSurfaces) {
        if (!allowedSurfaces.has(surface)) failures.push(`${assertion.id} has unknown affected surface ${surface}`);
      }
    }
    if (!Array.isArray(assertion.canonicalDocs) || assertion.canonicalDocs.length === 0) {
      failures.push(`${assertion.id} canonicalDocs must be a non-empty array`);
    } else {
      for (const doc of assertion.canonicalDocs) {
        if (!exists(doc, baseDir)) failures.push(`${assertion.id} canonical doc does not exist: ${doc}`);
      }
    }
    if (!Array.isArray(assertion.protectorScripts) || assertion.protectorScripts.length === 0) {
      failures.push(`${assertion.id} protectorScripts must be a non-empty array`);
    } else {
      for (const script of assertion.protectorScripts) {
        if (!exists(script, baseDir)) failures.push(`${assertion.id} protector script does not exist: ${script}`);
        const documented = (envelope.explicitlyDocumentedLanes ?? []).some((lane) => lane.includes(script));
        if (!laneText.includes(script) && !documented) {
          failures.push(`${assertion.id} protector script is not reachable from a test lane or explicitlyDocumentedLanes: ${script}`);
        }
      }
    }
    if (!allowedEvidenceModes.has(assertion.evidenceMode)) {
      failures.push(`${assertion.id} has invalid evidenceMode ${assertion.evidenceMode}`);
    }
    if (!allowedRepoScopes.has(assertion.repoScope)) {
      failures.push(`${assertion.id} has invalid repoScope ${assertion.repoScope}`);
    }
    if (!allowedStatuses.has(assertion.status)) {
      failures.push(`${assertion.id} has invalid status ${assertion.status}`);
    }
  }

  for (const principle of expectedPrinciples) {
    if (!seenPrinciples.has(principle)) failures.push(`missing assertion coverage for ${principle}`);
  }

  validateForbiddenTerms(envelope, failures, baseDir);

  const digest = contractDigest(envelope);
  if (envelope.contractDigest && envelope.contractDigest !== digest) {
    failures.push(`contractDigest mismatch: expected ${digest}, found ${envelope.contractDigest}`);
  }

  const upstream = envelope.upstream;
  if (upstream?.repo === "clawjs" && upstream.path && upstream.sourceDigest) {
    const upstreamRoot = path.resolve(baseDir, upstream.root ?? "../../clawjs");
    const upstreamPath = path.join(upstreamRoot, upstream.path);
    if (fs.existsSync(upstreamPath)) {
      const upstreamEnvelope = JSON.parse(fs.readFileSync(upstreamPath, "utf8"));
      const upstreamDigest = contractDigest(upstreamEnvelope);
      if (upstream.sourceDigest !== upstreamDigest) {
        failures.push(`upstream sourceDigest mismatch: expected ${upstreamDigest}, found ${upstream.sourceDigest}`);
      }
      const localIds = [...seenIds].sort();
      const upstreamIds = [...(upstreamEnvelope.assertions ?? []).map((entry) => entry.id)].sort();
      if (stableJson(localIds) !== stableJson(upstreamIds)) failures.push("local assertion ids diverge from ClawJS upstream");
      const localPrinciples = [...seenPrinciples].sort();
      const upstreamPrinciples = [...new Set((upstreamEnvelope.assertions ?? []).map((entry) => entry.principle))].sort();
      if (stableJson(localPrinciples) !== stableJson(upstreamPrinciples)) failures.push("local principle coverage diverges from ClawJS upstream");
    }
  }

  return { failures, envelope, digest };
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function writeText(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, value);
}

function createFixture(root, overrides = {}) {
  writeText(
    path.join(root, "CONSTITUTION.md"),
    `# Constitution

## Preamble

## Principles

**I.1 First principle.** Text.

**II.1 Second principle.** Text.

## Red lines

1. **Never leak.** Text.

## Tensions we navigate

1. **Local vs remote.** Text.

## Amendment process

Text.
`,
  );
  writeText(path.join(root, "package.json"), JSON.stringify({ scripts: { "test:docs": "node scripts/guard.mjs" } }, null, 2));
  writeText(path.join(root, "scripts/guard.mjs"), "console.log('ok');\n");
  for (const doc of ["docs/a.md", "docs/b.md"]) writeText(path.join(root, doc), "# doc\n");
  const assertions = [
    {
      id: "preamble.authority",
      principle: "Preamble",
      summary: "Authority is routed through canon.",
      forbiddenTerms: [],
      affectedSurfaces: ["docs"],
      canonicalDocs: ["docs/a.md"],
      protectorScripts: ["scripts/guard.mjs"],
      evidenceMode: "shape",
      repoScope: "shared",
      status: "enforced",
    },
    {
      id: "I.1.first-principle",
      principle: "I.1",
      summary: "First principle is covered.",
      forbiddenTerms: [{ term: "BAD_TERM", surfaces: ["docs"] }],
      affectedSurfaces: ["docs"],
      canonicalDocs: ["docs/a.md"],
      protectorScripts: ["scripts/guard.mjs"],
      evidenceMode: "delegated",
      repoScope: "shared",
      status: "partial",
    },
    {
      id: "II.1.second-principle",
      principle: "II.1",
      summary: "Second principle is covered.",
      forbiddenTerms: [],
      affectedSurfaces: ["storage"],
      canonicalDocs: ["docs/b.md"],
      protectorScripts: ["scripts/guard.mjs"],
      evidenceMode: "manual-review",
      repoScope: "shared",
      status: "manual",
    },
    {
      id: "Red.1.never-leak",
      principle: "Red.1",
      summary: "Red line is covered.",
      forbiddenTerms: [],
      affectedSurfaces: ["security"],
      canonicalDocs: ["docs/a.md"],
      protectorScripts: ["scripts/guard.mjs"],
      evidenceMode: "external-pending",
      repoScope: "shared",
      status: "external-pending",
    },
    {
      id: "Tension.1.local-remote",
      principle: "Tension.1",
      summary: "Tension is covered.",
      forbiddenTerms: [],
      affectedSurfaces: ["docs"],
      canonicalDocs: ["docs/a.md"],
      protectorScripts: ["scripts/guard.mjs"],
      evidenceMode: "shape",
      repoScope: "shared",
      status: "enforced",
    },
    {
      id: "amendment.process",
      principle: "Amendment",
      summary: "Amendment process is covered.",
      forbiddenTerms: [],
      affectedSurfaces: ["docs"],
      canonicalDocs: ["docs/a.md"],
      protectorScripts: ["scripts/guard.mjs"],
      evidenceMode: "shape",
      repoScope: "shared",
      status: "enforced",
    },
  ];
  const envelope = {
    schemaVersion: 1,
    description: "fixture",
    source: "CONSTITUTION.md",
    explicitlyDocumentedLanes: [],
    assertions,
    ...overrides,
  };
  envelope.contractDigest = contractDigest(envelope);
  writeJson(path.join(root, assertionPath), envelope);
  return envelope;
}

function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "constitution-assertions-check."));
  const cases = [];
  function expect(name, mutate, shouldPass) {
    const caseRoot = path.join(tempRoot, name);
    fs.mkdirSync(caseRoot, { recursive: true });
    const envelope = createFixture(caseRoot);
    mutate?.(caseRoot, envelope);
    const { failures } = validateEnvelope(caseRoot);
    cases.push({ name, passed: failures.length === 0, failures, shouldPass });
  }

  expect("valid", null, true);
  expect("missing-principle", (caseRoot, envelope) => {
    envelope.assertions = envelope.assertions.filter((entry) => entry.principle !== "II.1");
    envelope.contractDigest = contractDigest(envelope);
    writeJson(path.join(caseRoot, assertionPath), envelope);
  }, false);
  expect("missing-doc", (caseRoot, envelope) => {
    envelope.assertions[0].canonicalDocs = ["docs/missing.md"];
    envelope.contractDigest = contractDigest(envelope);
    writeJson(path.join(caseRoot, assertionPath), envelope);
  }, false);
  expect("missing-script", (caseRoot, envelope) => {
    envelope.assertions[0].protectorScripts = ["scripts/missing.mjs"];
    envelope.contractDigest = contractDigest(envelope);
    writeJson(path.join(caseRoot, assertionPath), envelope);
  }, false);
  expect("forbidden-term", (caseRoot) => {
    writeText(path.join(caseRoot, "docs/bad.md"), "BAD_TERM\n");
  }, false);
  expect("invalid-status", (caseRoot, envelope) => {
    envelope.assertions[0].status = "experimental";
    envelope.contractDigest = contractDigest(envelope);
    writeJson(path.join(caseRoot, assertionPath), envelope);
  }, false);
  expect("invalid-evidence-mode", (caseRoot, envelope) => {
    envelope.assertions[0].evidenceMode = "guess";
    envelope.contractDigest = contractDigest(envelope);
    writeJson(path.join(caseRoot, assertionPath), envelope);
  }, false);
  expect("bad-mirror-digest", (caseRoot, envelope) => {
    const upstreamRoot = path.join(caseRoot, "upstream");
    fs.mkdirSync(upstreamRoot, { recursive: true });
    createFixture(upstreamRoot);
    envelope.upstream = { repo: "clawjs", root: "upstream", path: assertionPath, sourceDigest: "bad" };
    envelope.contractDigest = contractDigest(envelope);
    writeJson(path.join(caseRoot, assertionPath), envelope);
  }, false);

  const failed = cases.filter((testCase) => testCase.passed !== testCase.shouldPass);
  if (failed.length > 0) {
    console.error("constitution assertions self-test failed:");
    for (const testCase of failed) {
      console.error(`- ${testCase.name}: ${testCase.failures.join("; ") || "unexpected pass"}`);
    }
    process.exit(1);
  }
  console.log("constitution assertions self-test passed");
}

if (selfTest) {
  runSelfTest();
} else {
  const { failures, digest } = validateEnvelope(rootDir);
  if (failures.length > 0) {
    console.error("Constitution assertions check failed:");
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.log(`constitution assertions check passed (${digest})`);
}
