#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const json = args.has("--json");
const updateBaseline = args.has("--update-baseline");
const selfTest = args.has("--self-test");
const reportAllSurfaces = args.has("--report-all-surfaces");
const baselineRelativePath = "docs/conceptual-vocabulary-baseline.json";
const registryRelativePath = "docs/vocabulary.registry.json";

const ignoredDirs = new Set([
  ".git",
  ".build",
  ".data",
  ".next",
  ".next-e2e",
  ".tmp",
  ".tmp-pack-smoke",
  "artifacts",
  "build",
  "coverage",
  "dist",
  "node_modules",
  "output",
  "playwright-report",
  "test-results",
]);
const ignoredPathParts = [
  "/package-lock.json",
  "/docs/conceptual-vocabulary-baseline.json",
  "/docs/vocabulary.registry.json",
  "/scripts/conceptual-vocabulary-guard.mjs",
];
const docsExtensions = new Set([".md", ".json", ".yaml", ".yml"]);
const sourceExtensions = new Set([".swift", ".ts", ".tsx", ".js", ".mjs", ".kt", ".cs"]);
const uiStringExtensions = new Set([".xcstrings", ".strings"]);
const maxFileBytes = 1_000_000;

function toPosix(relativePath) {
  return relativePath.split(path.sep).join("/");
}

function readJson(baseDir, relativePath) {
  return JSON.parse(fs.readFileSync(path.join(baseDir, relativePath), "utf8"));
}

function exists(baseDir, relativePath) {
  return fs.existsSync(path.join(baseDir, relativePath));
}

function shouldIgnore(relativePath, entry) {
  if (entry?.isDirectory?.() && ignoredDirs.has(entry.name)) return true;
  const wrapped = `/${toPosix(relativePath)}`;
  return ignoredPathParts.some((part) => wrapped.endsWith(part) || wrapped.includes(part));
}

function walk(baseDir, dir = baseDir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const absolutePath = path.join(dir, entry.name);
    const relativePath = toPosix(path.relative(baseDir, absolutePath));
    if (shouldIgnore(relativePath, entry)) continue;
    if (entry.isDirectory()) walk(baseDir, absolutePath, out);
    else if (entry.isFile()) out.push(relativePath);
  }
  return out;
}

function listedFiles(baseDir) {
  try {
    const output = execFileSync("git", ["-C", baseDir, "ls-files", "-z"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const files = output.split("\0").filter(Boolean).map(toPosix);
    if (files.length > 0) return files.filter((relativePath) => !shouldIgnore(relativePath, null));
  } catch {
    // Fall back to walking when the guard is run outside a Git checkout.
  }
  return walk(baseDir);
}

function isPublicInterfacePath(relativePath) {
  const lower = relativePath.toLowerCase();
  if (lower.startsWith("docs/")) return true;
  if (lower === "agents.md" || lower === "claude.md" || lower === "readme.md") return true;
  if (lower.includes("/bin/") || lower.includes("/cli")) return true;
  return [
    "protocol",
    "schema",
    "schemas",
    "contract",
    "contracts",
    "registry",
    "surface",
    "route",
    "routes",
    "command",
    "commands",
    "governance",
    "workspace",
    "project",
    "connector",
    "sync",
    "relay",
    "host",
  ].some((part) => lower.includes(part));
}

function isUiCopyPath(relativePath) {
  const lower = relativePath.toLowerCase();
  const extension = path.extname(relativePath);
  if (uiStringExtensions.has(extension)) return true;
  if (!sourceExtensions.has(extension)) return false;
  return lower.includes("/ui/") ||
    lower.includes("/app/") ||
    lower.includes("/apps/") ||
    lower.includes("/screens/") ||
    lower.includes("/views/") ||
    lower.includes("/components/") ||
    lower.includes("/sources/clawix/");
}

function isScannedPath(relativePath) {
  const ext = path.extname(relativePath);
  if (relativePath.startsWith("docs/") && docsExtensions.has(ext)) return true;
  if (!sourceExtensions.has(ext)) return false;
  return isPublicInterfacePath(relativePath) || isUiCopyPath(relativePath);
}

function isTestFixturePath(relativePath) {
  return /(^|\/)(test|tests|__tests__|fixtures|qa\/scenarios)(\/|$)|\.(test|spec)\./iu.test(relativePath);
}

function isExamplePath(relativePath) {
  return /(^|\/)(examples?|samples?)(\/|$)/iu.test(relativePath);
}

function isFullSurfaceScannedPath(relativePath) {
  const ext = path.extname(relativePath);
  if (relativePath.startsWith("docs/") && docsExtensions.has(ext)) return true;
  if (isTestFixturePath(relativePath) && (docsExtensions.has(ext) || sourceExtensions.has(ext))) return true;
  if (isExamplePath(relativePath) && (docsExtensions.has(ext) || sourceExtensions.has(ext))) return true;
  if (isUiCopyPath(relativePath)) return true;
  return sourceExtensions.has(ext);
}

function categoryFor(relativePath) {
  const ext = path.extname(relativePath);
  if (relativePath.startsWith("docs/") && docsExtensions.has(ext)) return "docs";
  if (isTestFixturePath(relativePath)) return "tests-fixtures";
  if (isExamplePath(relativePath)) return "examples";
  if (isUiCopyPath(relativePath)) return "ui-strings";
  if (docsExtensions.has(ext) || sourceExtensions.has(ext)) return "code";
  return "other";
}

function sortedObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map((key) => [key, sortedObject(value[key])]),
  );
}

function lineForIndex(text, index) {
  return text.slice(0, index).split(/\n/u).length;
}

function windowFor(text, index, length) {
  const before = text.lastIndexOf("\n", Math.max(0, index - 240));
  const after = text.indexOf("\n", index + length + 240);
  return text.slice(before === -1 ? 0 : before + 1, after === -1 ? text.length : after).toLowerCase();
}

function isAllowedMatch(relativePath, windowText, pattern) {
  const lowerPath = relativePath.toLowerCase();
  if ((pattern.allowedPathIncludes || []).some((part) => lowerPath.includes(String(part).toLowerCase()))) {
    return true;
  }
  return (pattern.allowedContextPhrases || []).some((phrase) => windowText.includes(String(phrase).toLowerCase()));
}

function loadPolicy(baseDir) {
  if (!exists(baseDir, registryRelativePath)) {
    throw new Error(`${registryRelativePath} is missing`);
  }
  const registry = readJson(baseDir, registryRelativePath);
  const guard = registry.conceptualGuard;
  if (!guard || !Array.isArray(guard.terms) || guard.terms.length === 0) {
    throw new Error(`${registryRelativePath}.conceptualGuard.terms must define protected concepts`);
  }
  return guard;
}

function collectFindings(baseDir, policy, shouldScanPath = isScannedPath) {
  const findings = [];
  for (const relativePath of listedFiles(baseDir)) {
    if (!shouldScanPath(relativePath)) continue;
    const absolutePath = path.join(baseDir, relativePath);
    const stat = fs.statSync(absolutePath);
    if (stat.size > maxFileBytes) continue;
    let text;
    try {
      text = fs.readFileSync(absolutePath, "utf8");
    } catch {
      continue;
    }
    for (const term of policy.terms) {
      for (const pattern of term.blockedPatterns || []) {
        const flags = pattern.flags || "giu";
        const regex = new RegExp(pattern.pattern, flags.includes("g") ? flags : `${flags}g`);
        let match;
        while ((match = regex.exec(text)) !== null) {
          const context = windowFor(text, match.index, match[0].length);
          if (isAllowedMatch(relativePath, context, pattern)) continue;
          findings.push({
            term: term.term,
            patternId: pattern.id,
            path: relativePath,
            line: lineForIndex(text, match.index),
            match: match[0],
            suggestion: pattern.suggestion || term.replacementGuidance || "",
          });
        }
      }
    }
  }
  return findings;
}

function categorySummaryFor(findings) {
  const categories = {};
  const samples = {};
  for (const finding of findings) {
    const category = categoryFor(finding.path);
    const key = `${finding.term}/${finding.patternId}`;
    categories[category] ??= {};
    categories[category][key] ??= { files: new Set(), occurrences: 0 };
    categories[category][key].files.add(finding.path);
    categories[category][key].occurrences += 1;
    samples[key] ??= [];
    if (samples[key].length < 5) {
      samples[key].push({
        path: finding.path,
        line: finding.line,
        match: finding.match,
      });
    }
  }

  const serializableCategories = {};
  for (const [category, patterns] of Object.entries(categories)) {
    serializableCategories[category] = {};
    for (const [pattern, value] of Object.entries(patterns)) {
      serializableCategories[category][pattern] = {
        files: value.files.size,
        occurrences: value.occurrences,
      };
    }
  }

  return {
    scope: "docs-code-ui-tests-fixtures-examples",
    note: "Report-only scan across tracked docs, source, UI copy, tests, fixtures, and examples. It does not change the blocking baseline.",
    categories: serializableCategories,
    samples,
  };
}

function countsFor(findings) {
  const counts = {};
  for (const finding of findings) {
    counts[finding.term] ??= {};
    counts[finding.term][finding.patternId] ??= {};
    counts[finding.term][finding.patternId][finding.path] ??= 0;
    counts[finding.term][finding.patternId][finding.path] += 1;
  }
  return counts;
}

function summaryFor(counts) {
  const summary = {};
  for (const [term, patterns] of Object.entries(counts)) {
    let files = new Set();
    let occurrences = 0;
    for (const paths of Object.values(patterns)) {
      for (const [relativePath, count] of Object.entries(paths)) {
        files.add(relativePath);
        occurrences += count;
      }
    }
    summary[term] = { files: files.size, occurrences };
  }
  return summary;
}

function totalOccurrencesForSummary(summary) {
  return Object.values(summary).reduce((total, entry) => total + (entry?.occurrences ?? 0), 0);
}

function compareToBaseline(baseDir, findings, counts) {
  const failures = [];
  if (!exists(baseDir, baselineRelativePath)) {
    failures.push(`${baselineRelativePath} is missing. Run node scripts/conceptual-vocabulary-guard.mjs --update-baseline after reviewing conceptual vocabulary debt.`);
    return failures;
  }
  const baseline = readJson(baseDir, baselineRelativePath);
  const baselineCounts = baseline.counts || {};
  for (const finding of findings) {
    const current = counts[finding.term]?.[finding.patternId]?.[finding.path] ?? 0;
    const allowed = baselineCounts[finding.term]?.[finding.patternId]?.[finding.path] ?? 0;
    if (current > allowed) {
      failures.push(`${finding.path}:${finding.line} adds conceptual vocabulary debt ${finding.term}/${finding.patternId} via ${JSON.stringify(finding.match)}; ${finding.suggestion}`);
    }
  }
  return [...new Set(failures)];
}

function writeBaseline(baseDir, policy, counts) {
  const summary = summaryFor(counts);
  const current = totalOccurrencesForSummary(summary);
  const baseline = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    policy: "Reviewed conceptual vocabulary debt may shrink without review. Any increase in a tracked path or any new tracked path fails scripts/conceptual-vocabulary-guard.mjs unless the occurrence is removed or this baseline is deliberately updated with rationale.",
    rationale: "Initial frozen baseline for docs, UI copy, and public/stable conceptual vocabulary surfaces.",
    protectedTerms: policy.terms.map((term) => term.term),
    scan: {
      docs: "docs/**/*.md|json|yaml|yml",
      source: "UI copy-bearing source plus public protocol, schema, CLI, registry, route, host, relay, connector, sync, workspace, project, governance, and surface files",
    },
    summary,
    counts,
    debtControl: {
      ownerArea: "naming-governance",
      expiresAt: "2026-08-19",
      severity: "P2",
      budget: {
        metric: "protected_vocabulary_debt_hits",
        unit: "hit",
        current,
        maxAllowed: current,
        nextMaxAllowed: Math.max(0, current - 1),
        target: 0,
        cadence: "next_touch_or_expiry",
      },
      releaseEffect: {
        mode: "blocks_growth",
        targets: ["changed-work"],
        gate: "node scripts/conceptual-vocabulary-guard.mjs",
        reason: "Protected vocabulary baseline must shrink or block new conceptual drift.",
      },
    },
  };
  fs.writeFileSync(path.join(baseDir, baselineRelativePath), `${JSON.stringify(sortedObject(baseline), null, 2)}\n`);
}

function run(baseDir) {
  const policy = loadPolicy(baseDir);
  const findings = collectFindings(baseDir, policy);
  const counts = countsFor(findings);
  const failures = updateBaseline ? [] : compareToBaseline(baseDir, findings, counts);
  if (updateBaseline) writeBaseline(baseDir, policy, counts);
  const result = { failures, summary: summaryFor(counts), baselineUpdated: updateBaseline };
  if (reportAllSurfaces) {
    result.fullSurfaceReport = categorySummaryFor(collectFindings(baseDir, policy, isFullSurfaceScannedPath));
  }
  return result;
}

function writeFixture(baseDir, registry, files, baselineCounts = {}) {
  fs.mkdirSync(path.join(baseDir, "docs"), { recursive: true });
  fs.writeFileSync(path.join(baseDir, registryRelativePath), `${JSON.stringify(registry, null, 2)}\n`);
  fs.writeFileSync(path.join(baseDir, baselineRelativePath), `${JSON.stringify({ schemaVersion: 1, counts: baselineCounts }, null, 2)}\n`);
  for (const [relativePath, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(baseDir, relativePath)), { recursive: true });
    fs.writeFileSync(path.join(baseDir, relativePath), text);
  }
}

function assertSelfTest(condition, message) {
  if (!condition) throw new Error(message);
}

function runSelfTest() {
  const fixtureRegistry = {
    schemaVersion: 1,
    conceptualGuard: {
      terms: [
        {
          term: "owner",
          blockedPatterns: [
            {
              id: "generic-owner-authority",
              pattern: "\\bowner(?:Id|Kind|_id)?\\b",
              suggestion: "Use steward, principal, grant, or a domain-specific owner field.",
              allowedContextPhrases: ["legal owner", "provider owner", "asset owner"],
            },
          ],
        },
        {
          term: "tenant",
          blockedPatterns: [
            {
              id: "tenant-as-product-scope",
              pattern: "\\btenant(?:Id|_id)?\\b",
              suggestion: "Use workspace, project, entity, scope, or provider tenant only for technical isolation.",
              allowedContextPhrases: ["provider tenant", "technical tenant", "hosted tenant"],
            },
          ],
        },
        {
          term: "host",
          blockedPatterns: [
            {
              id: "node-native-owner",
              pattern: "\\bnode owner\\b|\\bnode-owned\\b",
              suggestion: "Use signed host for native authority.",
            },
          ],
        },
        {
          term: "connector",
          blockedPatterns: [
            {
              id: "provider-plugin-account",
              pattern: "\\bplugin account\\b|\\bintegration account\\b",
              suggestion: "Use connector account for configured external accounts.",
              allowedContextPhrases: ["broader integration account domain"],
            },
          ],
        },
        {
          term: "route",
          blockedPatterns: [
            {
              id: "route-implies-authority",
              pattern: "\\broute\\s+(?:owner|grants? access|permissions?|access control)\\b|\\broute\\s+implies\\s+authority\\b",
              suggestion: "Use explicit grants, restrictions, and authority edges for access.",
            },
          ],
        },
        {
          term: "grant",
          blockedPatterns: [
            {
              id: "grant-as-approval",
              pattern: "\\bgrant\\s+(?:is|as)\\s+(?:approval|consent)\\b|\\bgrant\\s+implies\\s+approval\\b|\\bgrant\\s+without\\s+(?:scope|principal)\\b",
              suggestion: "Use grant for scoped capability edges and approval for review/consent gates.",
            },
          ],
        },
        {
          term: "approval",
          blockedPatterns: [
            {
              id: "approval-implies-access",
              pattern: "\\bapproval\\s+(?:implies|grants)\\s+(?:access|authority|permission|permissions)\\b|\\bapproval\\s+(?:token|credential|secret|lease)\\b",
              suggestion: "Use approval for review/consent and grant/lease/credential references for durable access.",
            },
          ],
        },
      ],
    },
  };

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "conceptual-vocabulary-guard-"));
  try {
    writeFixture(tempRoot, fixtureRegistry, {
      "docs/bad.md": "The workspace ownerId grants access.\nThe tenant is shown in UI.\nThe Node owner handles secrets.\nUse this plugin account for Slack.\n",
      "docs/new-bad.md": "The route grants access.\nThe grant is approval.\nThe approval grants access.\n",
      "docs/allowed.md": "The legal owner is domain data. The provider tenant is technical tenant isolation. The broader integration account domain is not a configured credential.\n",
      "packages/internal.ts": "const ownerId = 'internal-only';\n",
      "tests/internal.test.ts": "const ownerId = 'test-fixture';\n",
      "examples/internal.ts": "const ownerId = 'example-fixture';\n",
    });
    const failing = run(tempRoot);
    assertSelfTest(failing.failures.some((failure) => failure.includes("owner/generic-owner-authority")), "self-test must block ownerId authority usage");
    assertSelfTest(failing.failures.some((failure) => failure.includes("tenant/tenant-as-product-scope")), "self-test must block raw tenant UI usage");
    assertSelfTest(failing.failures.some((failure) => failure.includes("host/node-native-owner")), "self-test must block Node native ownership");
    assertSelfTest(failing.failures.some((failure) => failure.includes("connector/provider-plugin-account")), "self-test must block plugin account");
    assertSelfTest(failing.failures.some((failure) => failure.includes("route/route-implies-authority")), "self-test must block route-as-authority usage");
    assertSelfTest(failing.failures.some((failure) => failure.includes("grant/grant-as-approval")), "self-test must block grant-as-approval usage");
    assertSelfTest(failing.failures.some((failure) => failure.includes("approval/approval-implies-access")), "self-test must block approval-as-access usage");
    assertSelfTest(!failing.failures.some((failure) => failure.includes("allowed.md")), "self-test must allow provider/domain contexts");
    const fullReport = categorySummaryFor(collectFindings(tempRoot, loadPolicy(tempRoot), isFullSurfaceScannedPath));
    assertSelfTest(fullReport.categories.code?.["owner/generic-owner-authority"]?.occurrences === 1, "self-test full-surface report must include code");
    assertSelfTest(fullReport.categories["tests-fixtures"]?.["owner/generic-owner-authority"]?.occurrences === 1, "self-test full-surface report must include tests and fixtures");
    assertSelfTest(fullReport.categories.examples?.["owner/generic-owner-authority"]?.occurrences === 1, "self-test full-surface report must include examples");

    const findings = collectFindings(tempRoot, loadPolicy(tempRoot));
    writeBaseline(tempRoot, loadPolicy(tempRoot), countsFor(findings));
    const passing = run(tempRoot);
    assertSelfTest(passing.failures.length === 0, "self-test baseline must allow frozen debt");

    fs.appendFileSync(path.join(tempRoot, "docs/bad.md"), "Another ownerId appears.\n");
    const increased = run(tempRoot);
    assertSelfTest(increased.failures.some((failure) => failure.includes("owner/generic-owner-authority")), "self-test baseline increase must fail");

    fs.writeFileSync(path.join(tempRoot, "docs/bad.md"), "The provider tenant remains a technical tenant.\n");
    const shrunk = run(tempRoot);
    assertSelfTest(shrunk.failures.length === 0, "self-test baseline shrink must pass");
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
  return { failures: [], summary: {}, baselineUpdated: false, selfTest: true };
}

let result;
try {
  result = selfTest ? runSelfTest() : run(rootDir);
} catch (error) {
  result = { failures: [error.message], summary: {}, baselineUpdated: false };
}

if (json) {
  console.log(JSON.stringify(result, null, 2));
} else {
  if (result.baselineUpdated) console.log("conceptual vocabulary baseline updated");
  if (result.selfTest) console.log("conceptual vocabulary guard self-test passed");
  if (result.failures.length) {
    console.error("conceptual vocabulary guard failed:");
    for (const failure of result.failures) console.error(`- ${failure}`);
  }
  console.log(`conceptual vocabulary guard ${result.failures.length ? "failed" : "passed"}`);
}

if (result.failures.length) process.exit(1);
