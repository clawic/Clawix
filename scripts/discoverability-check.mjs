#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const registryPath = path.join(rootDir, "docs/discoverability.registry.json");
const baselinePath = path.join(rootDir, "docs/discoverability-baseline.json");
const allowedKinds = new Set([
  "adr",
  "decision-map-row",
  "skill",
  "guardrail",
  "test-harness",
  "ui-governance",
  "surface-route",
  "docs-page",
  "code-comment-policy",
]);
const allowedStatuses = new Set(["enforced", "baseline", "external_pending"]);
const decisionLikeComment = /\b(?:CANON|DECISION|GUARDRAIL|POLICY|INVARIANT)\b\s*:/;
const canonicalCommentReference = /(?:docs\/|ADR\s*\d{4}|registry|manifest|scripts\/|tests?\/|SKILL\.md)/i;

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function exists(relativePath) {
  return fs.existsSync(path.join(rootDir, relativePath));
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function isDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function listFiles(relativeDir, predicate, output = []) {
  const absoluteDir = path.join(rootDir, relativeDir);
  if (!fs.existsSync(absoluteDir)) return output;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      if (["node_modules", "dist", ".git", ".tmp", "build", ".next", ".build"].includes(entry.name)) continue;
      listFiles(relativePath, predicate, output);
    } else if (entry.isFile() && predicate(relativePath)) {
      output.push(relativePath);
    }
  }
  return output;
}

function normalizeTarget(target) {
  return target.split("#")[0].replace(/^\.?\//, "");
}

function targetTokens(target) {
  const normalized = normalizeTarget(target);
  const parsed = path.parse(normalized);
  const tokens = new Set([normalized, path.basename(normalized)]);
  if (parsed.dir.includes("skills") && parsed.name === "SKILL") tokens.add(path.basename(parsed.dir));
  if (parsed.ext === ".md" || parsed.ext === ".json" || parsed.ext === ".mjs") tokens.add(parsed.name);
  return [...tokens].filter(Boolean);
}

function resolveMention(fromRelativePath, mention) {
  const clean = normalizeTarget(mention);
  if (!clean || clean.startsWith("http") || clean.startsWith("mailto:")) return null;
  const candidates = [];
  if (clean.startsWith("docs/") || clean.startsWith("skills/") || clean.startsWith("scripts/") || clean === "AGENTS.md" || clean === "CLAUDE.md") {
    candidates.push(clean);
  }
  candidates.push(path.normalize(path.join(path.dirname(fromRelativePath), clean)));
  for (const candidate of candidates) {
    if (exists(candidate)) return candidate;
  }
  return null;
}

function mentionedFiles(relativePath) {
  if (!exists(relativePath)) return [];
  const text = read(relativePath);
  const mentions = new Set();
  const patterns = [
    /\[[^\]]*]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)/g,
    /`([^`\n]+\.(?:md|json|mjs|sh|ts|swift))`/g,
    /\b((?:docs|skills|scripts|packages|tests|qa|playbooks)\/[A-Za-z0-9._/@+-][A-Za-z0-9._/@+/\-]*\.(?:md|json|mjs|sh|ts|swift))\b/g,
  ];
  for (const pattern of patterns) {
    for (const match of text.matchAll(pattern)) {
      const resolved = resolveMention(relativePath, match[1]);
      if (resolved) mentions.add(resolved);
    }
  }
  return [...mentions];
}

function containsTarget(relativePath, target) {
  if (!exists(relativePath)) return false;
  const text = read(relativePath);
  return targetTokens(target).some((token) => text.includes(token));
}

function routeDistance(fromRelativePath, targetRelativePath, maxDistance) {
  if (fromRelativePath === targetRelativePath) return 0;
  if (!exists(fromRelativePath) || !exists(targetRelativePath)) return Infinity;
  if (containsTarget(fromRelativePath, targetRelativePath)) return 1;
  const queue = [[fromRelativePath, 0]];
  const seen = new Set([fromRelativePath]);
  while (queue.length > 0) {
    const [current, distance] = queue.shift();
    if (distance >= maxDistance) continue;
    for (const next of mentionedFiles(current)) {
      if (seen.has(next)) continue;
      if (next === targetRelativePath || containsTarget(next, targetRelativePath)) return distance + 1;
      seen.add(next);
      queue.push([next, distance + 1]);
    }
  }
  return Infinity;
}

function validateRegistry(registry, errors) {
  if (registry.version !== 1) errors.push("docs/discoverability.registry.json version must be 1");
  if (!Number.isInteger(registry.distanceBudget) || registry.distanceBudget < 1) errors.push("discoverability distanceBudget must be a positive integer");
  const ids = new Set();
  for (const artifact of registry.artifacts ?? []) {
    const label = artifact.id || "<missing id>";
    if (!artifact.id) errors.push("registry artifact is missing id");
    if (ids.has(artifact.id)) errors.push(`duplicate registry artifact id ${artifact.id}`);
    ids.add(artifact.id);
    if (!allowedKinds.has(artifact.kind)) errors.push(`${label} has invalid kind ${artifact.kind}`);
    if (!["claw", "clawix", "external"].includes(artifact.owner)) errors.push(`${label} has invalid owner ${artifact.owner}`);
    if (!artifact.canonicalSource || !exists(artifact.canonicalSource)) errors.push(`${label} canonicalSource is missing or does not exist: ${artifact.canonicalSource}`);
    if (!allowedStatuses.has(artifact.status)) errors.push(`${label} has invalid status ${artifact.status}`);
    if (!isDate(artifact.reviewDate)) errors.push(`${label} reviewDate must be YYYY-MM-DD`);
    if (!artifact.guard || !exists(artifact.guard)) errors.push(`${label} guard is missing or does not exist: ${artifact.guard}`);
    if (!Array.isArray(artifact.requiredEntrypoints) || artifact.requiredEntrypoints.length === 0) errors.push(`${label} must declare requiredEntrypoints`);
    if (!Array.isArray(artifact.discoveryTerms) || artifact.discoveryTerms.length === 0) errors.push(`${label} must declare discoveryTerms`);
    if (!Array.isArray(artifact.searchQueries) || artifact.searchQueries.length === 0) errors.push(`${label} must declare searchQueries`);
    for (const entrypoint of artifact.requiredEntrypoints ?? []) {
      if (!exists(entrypoint)) {
        errors.push(`${label} required entrypoint does not exist: ${entrypoint}`);
        continue;
      }
      const distance = routeDistance(entrypoint, artifact.canonicalSource, registry.distanceBudget);
      if (distance > registry.distanceBudget) errors.push(`${label} is not reachable from ${entrypoint} within ${registry.distanceBudget} hops`);
    }
    for (const query of artifact.searchQueries ?? []) {
      if (!query.query || !query.expectPath) errors.push(`${label} searchQueries must include query and expectPath`);
      if (query.expectPath && !exists(query.expectPath)) errors.push(`${label} search expectPath does not exist: ${query.expectPath}`);
      if (query.query && query.expectPath && exists(query.expectPath)) {
        const terms = query.query.toLowerCase().split(/\s+/).filter(Boolean);
        const searchable = `${query.expectPath}\n${read(query.expectPath)}`.toLowerCase();
        if (!terms.every((term) => searchable.includes(term))) errors.push(`${label} search query ${JSON.stringify(query.query)} is not represented in ${query.expectPath}`);
      }
    }
  }
}

function validateBaseline(baseline, errors) {
  if (baseline.version !== 1) errors.push("docs/discoverability-baseline.json version must be 1");
  const seen = new Set();
  for (const entry of baseline.entries ?? []) {
    const label = entry.id || "<missing baseline id>";
    if (!entry.id) errors.push("baseline entry is missing id");
    if (!entry.owner) errors.push(`${label} is missing owner`);
    if (!entry.reason) errors.push(`${label} is missing reason`);
    if (!isDate(entry.reviewDate)) errors.push(`${label} reviewDate must be YYYY-MM-DD`);
    if (!Array.isArray(entry.artifacts) || entry.artifacts.length === 0) errors.push(`${label} must freeze at least one artifact`);
    if (entry.frozenCount !== entry.artifacts?.length) errors.push(`${label} frozenCount must equal artifacts length`);
    const sorted = [...(entry.artifacts ?? [])].sort();
    if (JSON.stringify(sorted) !== JSON.stringify(entry.artifacts ?? [])) errors.push(`${label} artifacts must be sorted`);
    for (const artifact of entry.artifacts ?? []) {
      if (seen.has(artifact)) errors.push(`baseline artifact is listed twice: ${artifact}`);
      seen.add(artifact);
      if (!exists(artifact)) errors.push(`${label} baseline artifact does not exist: ${artifact}`);
    }
  }
  return seen;
}

function validateAdrCoverage(registry, baselineArtifacts, errors) {
  const registered = new Set((registry.artifacts ?? []).filter((artifact) => artifact.kind === "adr").map((artifact) => artifact.canonicalSource));
  const decisionMap = read("docs/decision-map.md");
  for (const adr of listFiles("docs/adr", (file) => file.endsWith(".md") && !file.endsWith("TEMPLATE.md")).sort()) {
    if (!registered.has(adr) && !baselineArtifacts.has(adr)) errors.push(`${adr} is not registered in discoverability.registry.json or discoverability-baseline.json`);
    const relativeDocsLink = adr.replace(/^docs\//, "./");
    if (registered.has(adr) && !decisionMap.includes(adr) && !decisionMap.includes(relativeDocsLink)) errors.push(`${adr} is registered but missing from docs/decision-map.md`);
  }
}

function validateSkillFrontmatter(registry, errors) {
  for (const artifact of registry.artifacts ?? []) {
    if (artifact.kind !== "skill") continue;
    const text = read(artifact.canonicalSource);
    const frontmatter = text.match(/^---\n([\s\S]*?)\n---\n/);
    if (!frontmatter) {
      errors.push(`${artifact.canonicalSource} is missing YAML frontmatter`);
      continue;
    }
    for (const field of ["name:", "description:", "keywords:"]) {
      if (!frontmatter[1].includes(field)) errors.push(`${artifact.canonicalSource} frontmatter is missing ${field}`);
    }
  }
}

function validateDecisionLikeComments(errors) {
  const files = [
    ...listFiles("packages", (file) => /\.(ts|tsx|js|mjs|swift)$/.test(file)),
    ...listFiles("scripts", (file) => /\.(mjs|js)$/.test(file)),
  ];
  for (const file of files) {
    const lines = read(file).split(/\r?\n/);
    lines.forEach((line, index) => {
      const trimmed = line.trim();
      if (!trimmed.startsWith("//") && !trimmed.startsWith("*")) return;
      if (decisionLikeComment.test(trimmed) && !canonicalCommentReference.test(trimmed)) {
        errors.push(`${file}:${index + 1} has decision-like comment without canonical reference`);
      }
    });
  }
}

function runCheck() {
  const errors = [];
  if (!fs.existsSync(registryPath)) errors.push("missing docs/discoverability.registry.json");
  if (!fs.existsSync(baselinePath)) errors.push("missing docs/discoverability-baseline.json");
  if (errors.length > 0) return errors;
  const registry = readJson(registryPath);
  const baseline = readJson(baselinePath);
  validateRegistry(registry, errors);
  const baselineArtifacts = validateBaseline(baseline, errors);
  validateAdrCoverage(registry, baselineArtifacts, errors);
  validateSkillFrontmatter(registry, errors);
  validateDecisionLikeComments(errors);
  return errors;
}

function runSelfTest() {
  assert.equal(isDate("2026-05-17"), true);
  assert.equal(isDate("17-05-2026"), false);
  assert.equal(targetTokens("skills/ui-implementation/SKILL.md").includes("ui-implementation"), true);
  assert.equal(routeDistance("AGENTS.md", "docs/adr/0017-discoverability-and-meta-code-routing.md", 2) <= 2, true);
  assert.equal(routeDistance("AGENTS.md", "docs/adr/not-real.md", 2), Infinity);
  assert.equal(decisionLikeComment.test("// GUARDRAIL: keep this"), true);
  assert.equal(canonicalCommentReference.test("// GUARDRAIL: see docs/adr/0017-discoverability-and-meta-code-routing.md"), true);
  const errors = [];
  validateRegistry({
    version: 1,
    distanceBudget: 2,
    artifacts: [{
      id: "bad",
      kind: "adr",
      owner: "clawix",
      canonicalSource: "docs/adr/missing.md",
      requiredEntrypoints: ["AGENTS.md"],
      discoveryTerms: ["bad"],
      searchQueries: [{ query: "bad", expectPath: "docs/adr/missing.md" }],
      guard: "scripts/missing.mjs",
      status: "enforced",
      reviewDate: "2026-05-17",
    }],
  }, errors);
  assert.equal(errors.some((error) => error.includes("canonicalSource")), true);
  assert.equal(errors.some((error) => error.includes("guard")), true);
}

if (process.argv.includes("--self-test")) {
  runSelfTest();
  console.log("Clawix discoverability check self-test passed");
  process.exit(0);
}

const errors = runCheck();
if (errors.length > 0) {
  console.error("Clawix discoverability check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("Clawix discoverability check passed");
