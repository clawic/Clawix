#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const errors = [];

function fail(message) {
  errors.push(message);
}

function readJson(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function hasLocalPath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
}

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (hasLocalPath(value)) fail(`${label} must not contain a local path`);
}

const registryPath = "docs/ui/inspiration/references.registry.json";
const registry = readJson(registryPath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
requireFields(registry, registryPath, ["schemaVersion", "policy", "references"]);
if (args.has("--simulate-incomplete-policy") && registry) {
  registry.policy = "External references are inspiration only.";
}
if (args.has("--simulate-missing-required-reference") && Array.isArray(registry?.references)) {
  registry.references = registry.references.filter((reference) => reference?.id !== "playwright-snapshots");
}
if (args.has("--simulate-canonical-reference") && Array.isArray(registry?.references) && registry.references[0]) {
  registry.references[0] = { ...registry.references[0], canonical: true };
}
if (args.has("--simulate-http-reference") && Array.isArray(registry?.references) && registry.references[0]) {
  registry.references[0] = { ...registry.references[0], url: "http://example.invalid/inspiration" };
}
if (args.has("--simulate-duplicate-reference-id") && Array.isArray(registry?.references) && registry.references[0]) {
  registry.references = [...registry.references, { ...registry.references[0] }];
}
if (args.has("--simulate-invalid-reference-id") && Array.isArray(registry?.references) && registry.references[0]) {
  registry.references[0] = { ...registry.references[0], id: "Storybook Visual Tests" };
}
if (args.has("--simulate-invalid-reference-url") && Array.isArray(registry?.references) && registry.references[0]) {
  registry.references[0] = { ...registry.references[0], url: "not a url" };
}
if (args.has("--simulate-canonical-use-text") && Array.isArray(registry?.references) && registry.references[0]) {
  registry.references[0] = { ...registry.references[0], use: "canonical visual style reference" };
}
if (args.has("--simulate-required-reference-url-mismatch") && Array.isArray(registry?.references)) {
  registry.references = registry.references.map((reference) => (
    reference?.id === "playwright-snapshots"
      ? { ...reference, url: "https://playwright.dev/docs/screenshots" }
      : reference
  ));
}
if (args.has("--simulate-local-path-leak") && Array.isArray(registry?.references) && registry.references[0]) {
  registry.references[0] = { ...registry.references[0], use: "/Users/example/private/reference-notes" };
}
if (args.has("--simulate-decision-evidence-missing-registry") && Array.isArray(decisionVerification?.decisions)) {
  const decision = decisionVerification.decisions.find((entry) => entry?.id === "external_references_policy");
  if (decision) {
    decision.publicEvidence = decision.publicEvidence.filter((evidence) => evidence !== registryPath);
  }
}
if (args.has("--simulate-decision-evidence-missing-script") && Array.isArray(decisionVerification?.decisions)) {
  const decision = decisionVerification.decisions.find((entry) => entry?.id === "external_references_policy");
  if (decision) {
    decision.publicEvidence = decision.publicEvidence.filter((evidence) => evidence !== "scripts/ui_inspiration_reference_check.mjs");
  }
}

const policy = String(registry?.policy || "").toLowerCase();
for (const phrase of ["inspiration", "non-canonical", "explicitly approves", "concepts", "not visual styles", "do not copy"]) {
  if (!policy.includes(phrase)) fail(`${registryPath}.policy must mention ${phrase}`);
}

const references = requireArray(registry, registryPath, "references");
const seenIds = new Set();
const seenUrlsById = new Map();
for (const [index, reference] of references.entries()) {
  const label = `${registryPath}.references[${index}]`;
  requireFields(reference, label, ["id", "url", "use", "canonical"]);
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(String(reference.id || ""))) {
    fail(`${label}.id must be a stable slug`);
  }
  if (seenIds.has(reference.id)) fail(`${label}.id duplicates ${reference.id}`);
  seenIds.add(reference.id);
  seenUrlsById.set(reference.id, reference.url);
  let url = null;
  try {
    url = new URL(reference.url);
  } catch {
    fail(`${label}.url must be a valid URL`);
  }
  if (url && url.protocol !== "https:") fail(`${label}.url must use https`);
  if (reference.canonical !== false) fail(`${label}.canonical must remain false`);
  if (String(reference.use || "").toLowerCase().includes("canonical")) {
    fail(`${label}.use must not describe the reference as canonical`);
  }
}

const requiredReferences = [
  ["storybook-visual-tests", "https://storybook.js.org/docs/8/writing-tests/visual-testing"],
  ["playwright-snapshots", "https://playwright.dev/docs/test-snapshots"],
  ["design-tokens-format", "https://www.w3.org/community/reports/design-tokens/CG-FINAL-format-20251028/"],
  ["style-dictionary", "https://styledictionary.com/info/tokens/"],
  ["shadcn-registry-mcp", "https://ui.shadcn.com/docs/registry/mcp"],
  ["panda-slot-recipes", "https://panda-css.com/docs/concepts/slot-recipes"],
];
for (const [id, url] of requiredReferences) {
  if (!seenIds.has(id)) {
    fail(`${registryPath}.references must include required inspiration reference ${id}`);
    continue;
  }
  if (seenUrlsById.get(id) !== url) {
    fail(`${registryPath}.references ${id} must use ${url}`);
  }
}

const externalReferencesDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "external_references_policy");
if (!externalReferencesDecision) {
  fail(`${decisionVerificationPath}.decisions must include external_references_policy`);
} else {
  if (externalReferencesDecision.status !== "verified-complete") {
    fail(`${decisionVerificationPath}.decisions.external_references_policy.status must be verified-complete`);
  }
  const publicEvidence = new Set(Array.isArray(externalReferencesDecision.publicEvidence) ? externalReferencesDecision.publicEvidence : []);
  for (const evidence of [registryPath, "scripts/ui_inspiration_reference_check.mjs"]) {
    if (!publicEvidence.has(evidence)) {
      fail(`${decisionVerificationPath}.decisions.external_references_policy.publicEvidence must include ${evidence}`);
    }
  }
}

const patternRegistry = readJson("docs/ui/pattern-registry/patterns.registry.json");
for (const patternId of requireArray(patternRegistry, "docs/ui/pattern-registry/patterns.registry.json", "patterns")) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (args.has("--simulate-external-pattern-reference") && patternId === "sidebar-row" && Array.isArray(pattern?.canonicalReferences)) {
    pattern.canonicalReferences = [...pattern.canonicalReferences, "https://example.invalid/inspiration"];
  }
  for (const [index, reference] of requireArray(pattern, patternPath, "canonicalReferences").entries()) {
    if (String(reference).startsWith("http://") || String(reference).startsWith("https://")) {
      fail(`${patternPath}.canonicalReferences[${index}] must not point to an external inspiration URL`);
    }
  }
}

scanForLocalPaths(registry, registryPath);

if (errors.length > 0) {
  console.error("UI inspiration reference check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI inspiration reference check passed (${seenIds.size} references)`);
