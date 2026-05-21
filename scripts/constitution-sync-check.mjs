#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const argSet = new Set(args);
const defaultRootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const rootDir = path.resolve(valueAfter("--root") ?? defaultRootDir);

function valueAfter(flag) {
  const index = args.indexOf(flag);
  return index === -1 ? undefined : args[index + 1];
}

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

function read(file) {
  return fs.readFileSync(file, "utf8");
}

function readJson(file) {
  return JSON.parse(read(file));
}

function normalizeText(text) {
  return text
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .map((line) => line.replace(/[ \t]+$/g, ""))
    .join("\n")
    .replace(/\n*$/g, "\n");
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

function sortedUnique(values) {
  return [...new Set(values)].sort();
}

function setDiff(left, right) {
  const rightSet = new Set(right);
  return left.filter((value) => !rightSet.has(value));
}

function firstDifferentLine(left, right) {
  const leftLines = left.split("\n");
  const rightLines = right.split("\n");
  const count = Math.max(leftLines.length, rightLines.length);
  for (let index = 0; index < count; index += 1) {
    if (leftLines[index] !== rightLines[index]) {
      return {
        line: index + 1,
        clawix: leftLines[index] ?? "<missing>",
        clawjs: rightLines[index] ?? "<missing>",
      };
    }
  }
  return null;
}

function resolveRoots(baseDir) {
  const clawixRootArg = valueAfter("--clawix-root") ?? process.env.CLAWIX_ROOT;
  const clawjsRootArg = valueAfter("--clawjs-root") ?? process.env.CLAWJS_ROOT;
  if (clawixRootArg && clawjsRootArg) {
    return { clawixRoot: path.resolve(clawixRootArg), clawjsRoot: path.resolve(clawjsRootArg) };
  }

  const basename = path.basename(baseDir);
  const parent = path.dirname(baseDir);
  if (basename === "clawjs") {
    return {
      clawixRoot: path.resolve(clawixRootArg ?? parent, "Clawix", "clawix"),
      clawjsRoot: path.resolve(clawjsRootArg ?? baseDir),
    };
  }
  if (basename === "clawix") {
    return {
      clawixRoot: path.resolve(clawixRootArg ?? baseDir),
      clawjsRoot: path.resolve(clawjsRootArg ?? parent, "..", "clawjs"),
    };
  }

  return {
    clawixRoot: path.resolve(clawixRootArg ?? baseDir, "clawix"),
    clawjsRoot: path.resolve(clawjsRootArg ?? baseDir, "..", "clawjs"),
  };
}

function validate({ clawixRoot, clawjsRoot }) {
  const failures = [];
  const constitutionPath = "CONSTITUTION.md";
  const assertionsPath = "docs/constitution.assertions.json";
  const clawixConstitution = path.join(clawixRoot, constitutionPath);
  const clawjsConstitution = path.join(clawjsRoot, constitutionPath);
  const clawixAssertionsPath = path.join(clawixRoot, assertionsPath);
  const clawjsAssertionsPath = path.join(clawjsRoot, assertionsPath);

  for (const file of [clawixConstitution, clawjsConstitution, clawixAssertionsPath, clawjsAssertionsPath]) {
    if (!fs.existsSync(file)) failures.push(`missing ${file}`);
  }
  if (failures.length > 0) return failures;

  const clawixText = normalizeText(read(clawixConstitution));
  const clawjsText = normalizeText(read(clawjsConstitution));
  if (clawixText !== clawjsText) {
    const diff = firstDifferentLine(clawixText, clawjsText);
    failures.push(
      `CONSTITUTION.md drift: Clawix and ClawJS copies differ at normalized line ${diff?.line ?? "unknown"}`,
    );
    if (diff) {
      failures.push(`  Clawix: ${diff.clawix.slice(0, 160)}`);
      failures.push(`  ClawJS: ${diff.clawjs.slice(0, 160)}`);
    }
  }

  const clawixCoverage = sortedUnique(constitutionCoverageIds(clawixText));
  const clawjsCoverage = sortedUnique(constitutionCoverageIds(clawjsText));
  const missingFromClawix = setDiff(clawjsCoverage, clawixCoverage);
  const missingFromClawjs = setDiff(clawixCoverage, clawjsCoverage);
  if (missingFromClawix.length > 0) failures.push(`Clawix CONSTITUTION.md is missing coverage ids: ${missingFromClawix.join(", ")}`);
  if (missingFromClawjs.length > 0) failures.push(`ClawJS CONSTITUTION.md is missing coverage ids: ${missingFromClawjs.join(", ")}`);

  const assertionChecks = [
    { label: "Clawix", root: clawixRoot, constitutionCoverage: clawixCoverage, envelope: readJson(clawixAssertionsPath) },
    { label: "ClawJS", root: clawjsRoot, constitutionCoverage: clawjsCoverage, envelope: readJson(clawjsAssertionsPath) },
  ];
  for (const check of assertionChecks) {
    const digest = contractDigest(check.envelope);
    if (check.envelope.contractDigest && check.envelope.contractDigest !== digest) {
      failures.push(`${check.label} contractDigest mismatch: expected ${digest}, found ${check.envelope.contractDigest}`);
    }

    const assertionPrinciples = sortedUnique((check.envelope.assertions ?? []).map((entry) => entry.principle));
    const extraAssertions = setDiff(assertionPrinciples, check.constitutionCoverage);
    const missingAssertions = setDiff(check.constitutionCoverage, assertionPrinciples);
    if (extraAssertions.length > 0) failures.push(`${check.label} assertions reference principles absent from CONSTITUTION.md: ${extraAssertions.join(", ")}`);
    if (missingAssertions.length > 0) failures.push(`${check.label} assertions are missing constitutional coverage: ${missingAssertions.join(", ")}`);
  }

  const clawixEnvelope = assertionChecks[0].envelope;
  const clawjsEnvelope = assertionChecks[1].envelope;
  const clawixPrinciples = sortedUnique((clawixEnvelope.assertions ?? []).map((entry) => entry.principle));
  const clawjsPrinciples = sortedUnique((clawjsEnvelope.assertions ?? []).map((entry) => entry.principle));
  const clawixIds = sortedUnique((clawixEnvelope.assertions ?? []).map((entry) => entry.id));
  const clawjsIds = sortedUnique((clawjsEnvelope.assertions ?? []).map((entry) => entry.id));
  if (stableJson(clawixPrinciples) !== stableJson(clawjsPrinciples)) failures.push("Clawix and ClawJS assertion principle coverage diverges");
  if (stableJson(clawixIds) !== stableJson(clawjsIds)) failures.push("Clawix and ClawJS assertion ids diverge");

  const upstream = clawixEnvelope.upstream;
  if (upstream?.repo !== "clawjs" || upstream.path !== assertionsPath || !upstream.sourceDigest) {
    failures.push("Clawix constitution assertions must declare upstream ClawJS sourceDigest");
  } else {
    const upstreamDigest = contractDigest(clawjsEnvelope);
    if (upstream.sourceDigest !== upstreamDigest) {
      failures.push(`Clawix upstream sourceDigest is stale: expected ${upstreamDigest}, found ${upstream.sourceDigest}`);
    }
  }

  return failures;
}

function writeText(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, value);
}

function writeJson(file, value) {
  writeText(file, `${JSON.stringify(value, null, 2)}\n`);
}

function fixtureConstitution(extra = "") {
  return `# Constitution

## Preamble

## Principles

**I.1 First principle.** Text.
${extra}
## Red lines

1. **Never leak.** Text.

## Tensions we navigate

1. **Local vs remote.** Text.

## Amendment process

Text.
`;
}

function fixtureAssertions({ extraPrinciple } = {}) {
  const assertions = [
    ["Preamble.authority", "Preamble"],
    ["I.1.first-principle", "I.1"],
    ["Red.1.never-leak", "Red.1"],
    ["Tension.1.local-remote", "Tension.1"],
    ["Amendment.process", "Amendment"],
  ].map(([id, principle]) => ({
    id,
    principle,
    summary: `${principle} is covered by the fixture.`,
    forbiddenTerms: [],
    affectedSurfaces: ["docs"],
    canonicalDocs: ["CONSTITUTION.md"],
    protectorScripts: ["scripts/constitution-sync-check.mjs"],
    evidenceMode: "shape",
    repoScope: "shared",
    status: "enforced",
  }));
  if (extraPrinciple) {
    assertions.push({
      id: "II.1.extra-principle",
      principle: "II.1",
      summary: "Extra assertion should be rejected.",
      forbiddenTerms: [],
      affectedSurfaces: ["docs"],
      canonicalDocs: ["CONSTITUTION.md"],
      protectorScripts: ["scripts/constitution-sync-check.mjs"],
      evidenceMode: "shape",
      repoScope: "shared",
      status: "enforced",
    });
  }
  const envelope = {
    schemaVersion: 1,
    description: "fixture",
    source: "CONSTITUTION.md",
    explicitlyDocumentedLanes: ["node scripts/constitution-sync-check.mjs"],
    assertions,
  };
  envelope.contractDigest = contractDigest(envelope);
  return envelope;
}

function createFixture(root, options = {}) {
  const clawixRoot = path.join(root, "Clawix", "clawix");
  const clawjsRoot = path.join(root, "clawjs");
  const text = fixtureConstitution();
  writeText(path.join(clawixRoot, "CONSTITUTION.md"), options.clawixText ?? text);
  writeText(path.join(clawjsRoot, "CONSTITUTION.md"), options.clawjsText ?? text);
  const clawjsEnvelope = fixtureAssertions();
  const clawixEnvelope = fixtureAssertions({ extraPrinciple: options.clawixExtraAssertion });
  clawixEnvelope.upstream = {
    repo: "clawjs",
    root: "../../clawjs",
    path: "docs/constitution.assertions.json",
    sourceDigest: options.staleSourceDigest ? "stale" : contractDigest(clawjsEnvelope),
  };
  writeJson(path.join(clawixRoot, "docs/constitution.assertions.json"), clawixEnvelope);
  writeJson(path.join(clawjsRoot, "docs/constitution.assertions.json"), clawjsEnvelope);
  return { clawixRoot, clawjsRoot };
}

function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "constitution-sync-check."));
  const cases = [
    {
      name: "valid",
      options: {},
      shouldPass: true,
    },
    {
      name: "clawix-only-change",
      options: { clawixText: fixtureConstitution("\n**I.2 Clawix only.** Text.\n") },
      shouldPass: false,
      expected: "CONSTITUTION.md drift",
    },
    {
      name: "clawjs-only-change",
      options: { clawjsText: fixtureConstitution("\n**I.2 ClawJS only.** Text.\n") },
      shouldPass: false,
      expected: "CONSTITUTION.md drift",
    },
    {
      name: "extra-assertion-principle",
      options: { clawixExtraAssertion: true },
      shouldPass: false,
      expected: "absent from CONSTITUTION.md",
    },
    {
      name: "stale-source-digest",
      options: { staleSourceDigest: true },
      shouldPass: false,
      expected: "sourceDigest is stale",
    },
  ];

  const failures = [];
  for (const testCase of cases) {
    const roots = createFixture(path.join(tempRoot, testCase.name), testCase.options);
    const result = validate(roots);
    const passed = result.length === 0;
    const matchedExpected = !testCase.expected || result.join("\n").includes(testCase.expected);
    if (passed !== testCase.shouldPass || !matchedExpected) {
      failures.push(`${testCase.name}: ${result.join("; ") || "unexpected pass"}`);
    }
  }

  if (failures.length > 0) {
    console.error("constitution sync self-test failed:");
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.error("constitution sync self-test passed");
}

if (argSet.has("--self-test")) {
  runSelfTest();
} else {
  const failures = validate(resolveRoots(rootDir));
  if (failures.length > 0) {
    console.error(`constitution sync check failed (${failures.length})`);
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.error("constitution sync check passed");
}
