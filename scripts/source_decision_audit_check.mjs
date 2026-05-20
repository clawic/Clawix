#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const errors = [];
const allowedStates = ["implemented", "documented", "blocked", "superseded"];
const unsafePublicPatterns = [
  /\/Users\//,
  /file:\/\//,
  /secret:\/\//,
  /-----BEGIN/,
  /\bsk-[A-Za-z0-9_-]+/,
  /\bAKIA[A-Z0-9]+/,
  /rollout-\d{4}-\d{2}-\d{2}T/,
];

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(relativePath) {
  return JSON.parse(read(relativePath));
}

function requireFile(relativePath) {
  if (!fs.existsSync(path.join(rootDir, relativePath))) fail(`missing ${relativePath}`);
}

function requireSnippet(relativePath, snippet) {
  const text = read(relativePath);
  if (!text.includes(snippet)) fail(`${relativePath}: missing ${JSON.stringify(snippet)}`);
}

function assertPublicSafe(label, value) {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  for (const pattern of unsafePublicPatterns) {
    if (pattern.test(text)) fail(`${label}: contains private or secret-looking material`);
  }
}

function requireStringArray(value, label, options = {}) {
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string" || item.length === 0)) {
    fail(`${label}: must be an array of non-empty strings`);
    return [];
  }
  if (options.nonEmpty && value.length === 0) fail(`${label}: must not be empty`);
  const seen = new Set();
  for (const item of value) {
    if (seen.has(item)) fail(`${label}: duplicate ${item}`);
    seen.add(item);
  }
  return value;
}

function sourceRows(artifact) {
  if (Array.isArray(artifact.rows)) return artifact.rows;
  if (Array.isArray(artifact.items)) return artifact.items;
  if (Array.isArray(artifact.decisions)) return artifact.decisions;
  return [];
}

function normalizeLegacyState(seed, row) {
  if (!seed.legacyStateField) return null;
  const legacyState = row?.[seed.legacyStateField];
  const mapped = seed.legacyStateMap?.[legacyState];
  if (!mapped) fail(`${seed.id}: unmapped legacy state ${legacyState}`);
  return mapped;
}

function validateSeed(seed) {
  for (const field of ["id", "artifactPath", "sourceConversationId", "artifactKind", "minimumDecisionRows"]) {
    if (seed[field] === undefined || seed[field] === "") fail(`${seed.id ?? "seed"}: missing ${field}`);
  }
  assertPublicSafe(seed.id, seed);
  requireFile(seed.artifactPath);
  const artifact = readJson(seed.artifactPath);
  const rows = sourceRows(artifact);
  if (rows.length < seed.minimumDecisionRows) {
    fail(`${seed.id}: expected at least ${seed.minimumDecisionRows} rows, found ${rows.length}`);
  }
  if (artifact.sourceConversationId && artifact.sourceConversationId !== seed.sourceConversationId) {
    fail(`${seed.id}: sourceConversationId drifted`);
  }
  if (artifact.conversationId && artifact.conversationId !== seed.sourceConversationId) {
    fail(`${seed.id}: conversationId drifted`);
  }
  if (artifact.sourcePlanId && seed.sourcePlanId && artifact.sourcePlanId !== seed.sourcePlanId) {
    fail(`${seed.id}: sourcePlanId drifted`);
  }
  const normalizedStates = new Set(seed.normalizedStates ?? []);
  if (seed.legacyStateField) {
    for (const row of rows) normalizedStates.add(normalizeLegacyState(seed, row));
  }
  for (const state of normalizedStates) {
    if (!allowedStates.includes(state)) fail(`${seed.id}: invalid normalized state ${state}`);
  }
  requireStringArray(seed.evidenceRefs, `${seed.id}.evidenceRefs`, { nonEmpty: true });
  for (const evidenceRef of seed.evidenceRefs) {
    if (evidenceRef.startsWith("docs/") || evidenceRef.startsWith("scripts/")) {
      requireFile(evidenceRef.split("#")[0]);
    }
  }
  if (normalizedStates.has("blocked")) {
    requireStringArray(seed.blockedRefs, `${seed.id}.blockedRefs`, { nonEmpty: true });
  }
}

function validateRegistry() {
  const registry = readJson("docs/governance/source-decision-audits.registry.json");
  if (registry.schemaVersion !== 1) fail("registry.schemaVersion must be 1");
  if (registry.forwardOnly !== true) fail("registry.forwardOnly must be true");
  if (JSON.stringify(registry.statusVocabulary) !== JSON.stringify(allowedStates)) {
    fail(`registry.statusVocabulary must be exactly ${allowedStates.join(", ")}`);
  }
  for (const field of ["decisionId", "sourceConversationId", "sourceAnchor", "architectureImpact", "state", "evidenceRefs", "reviewedAt"]) {
    if (!registry.rowContract?.requiredFields?.includes(field)) fail(`rowContract.requiredFields must include ${field}`);
  }
  for (const field of ["blockerReason", "reentryCondition", "remaining"]) {
    if (!registry.rowContract?.blockedRequires?.includes(field)) fail(`rowContract.blockedRequires must include ${field}`);
  }
  if (!registry.rowContract?.supersededRequires?.includes("supersededBy")) {
    fail("rowContract.supersededRequires must include supersededBy");
  }
  assertPublicSafe("Clawix source decision registry", registry);
  requireSnippet("docs/governance/source-decision-audits.md", "ClawJS owns the general source decision audit contract");
  requireSnippet("docs/decision-map.md", "Source decision audits");
  requireSnippet("docs/adr/TEMPLATE.md", "## Source Decision Audit");
  requireSnippet("docs/governance/README.md", "Source Decision Audits");
  requireSnippet("docs/discoverability.registry.json", "clawix-source-decision-audit-governance");
  const seeds = Array.isArray(registry.seeds) ? registry.seeds : [];
  for (const requiredSeed of [
    "ui-governance-decision-verification",
    "system-telemetry-source-review",
    "v1-surface-closure-decisions",
  ]) {
    if (!seeds.some((seed) => seed.id === requiredSeed)) fail(`registry.seeds missing ${requiredSeed}`);
  }
  for (const seed of seeds) validateSeed(seed);
}

function runSelfTest() {
  const mapped = normalizeLegacyState({
    id: "self-test",
    legacyStateField: "status",
    legacyStateMap: { "blocked-external-pending": "blocked" },
  }, { status: "blocked-external-pending" });
  if (mapped !== "blocked") fail("self-test: blocked-external-pending must normalize to blocked");
  assertPublicSafe("self-test-safe-ref", "docs/governance/source-decision-audits.md");
}

if (args.has("--self-test")) runSelfTest();
else validateRegistry();

if (errors.length > 0) {
  console.error(`Clawix source decision audit check failed (${errors.length})`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(args.has("--self-test") ? "Clawix source decision audit self-test passed" : "Clawix source decision audit check passed");
