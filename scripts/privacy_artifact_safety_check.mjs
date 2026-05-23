#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import {
  assertPublicSafe,
  privacyFindings,
  redactSensitiveText,
  serializeForPrivacyScan,
} from "./privacy-redaction.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const fixturesPath = "docs/governance/privacy-artifact-redaction.fixtures.json";
const args = process.argv.slice(2);

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function fail(message) {
  console.error(`privacy artifact safety check failed: ${message}`);
  process.exit(1);
}

function materializeSyntheticSensitiveValue(value) {
  if (Array.isArray(value)) return value.map((entry) => materializeSyntheticSensitiveValue(entry));
  if (value && typeof value === "object") {
    if (Array.isArray(value.segments) && Object.keys(value).length === 1) {
      return value.segments.join("");
    }
    return Object.fromEntries(
      Object.entries(value).map(([key, child]) => [key, materializeSyntheticSensitiveValue(child)]),
    );
  }
  return value;
}

function validateFixtures() {
  const fixtures = readJson(fixturesPath);
  if (fixtures.status !== "synthetic_sensitive_templates_not_evidence") {
    fail("fixtures must remain synthetic sensitive templates only");
  }
  if (fixtures.validatorPath !== "scripts/privacy_artifact_safety_check.mjs") {
    fail("fixtures validatorPath is stale");
  }

  for (const artifact of fixtures.safeSyntheticArtifacts ?? []) {
    try {
      assertPublicSafe(artifact, artifact.id);
    } catch (error) {
      fail(`safe fixture ${artifact.id} was rejected: ${error.message}`);
    }
  }

  for (const artifact of fixtures.sensitiveSyntheticArtifacts ?? []) {
    const materializedArtifact = materializeSyntheticSensitiveValue(artifact);
    const findings = privacyFindings(materializedArtifact);
    if (findings.length === 0) {
      fail(`sensitive fixture ${artifact.id} did not produce privacy findings`);
    }
    const redacted = redactSensitiveText(serializeForPrivacyScan(materializedArtifact));
    if (privacyFindings(redacted).length > 0) {
      fail(`sensitive fixture ${artifact.id} still contains sensitive material after redaction`);
    }
    for (const token of artifact.expectedRedactions ?? []) {
      if (!redacted.includes(token)) {
        fail(`sensitive fixture ${artifact.id} missing expected redaction ${token}`);
      }
    }
  }

  return {
    safeSyntheticArtifacts: fixtures.safeSyntheticArtifacts?.length ?? 0,
    sensitiveSyntheticArtifacts: fixtures.sensitiveSyntheticArtifacts?.length ?? 0,
  };
}

function validateFile(filePath) {
  const absolutePath = path.resolve(process.cwd(), filePath);
  const text = fs.readFileSync(absolutePath, "utf8");
  try {
    assertPublicSafe(text, path.relative(rootDir, absolutePath));
  } catch (error) {
    fail(error.message);
  }
}

function publicArtifactFiles() {
  const files = [];
  const roots = ["docs", "tests", "packages", "macos/Tests"];
  const ignored = new Set([".build", "build", "node_modules"]);
  for (const root of roots) walk(path.join(rootDir, root));
  return files.sort();

  function walk(absolutePath) {
    if (!fs.existsSync(absolutePath)) return;
    const stat = fs.statSync(absolutePath);
    if (stat.isDirectory()) {
      if (ignored.has(path.basename(absolutePath))) return;
      for (const entry of fs.readdirSync(absolutePath)) walk(path.join(absolutePath, entry));
      return;
    }
    if (!stat.isFile()) return;
    const relativePath = path.relative(rootDir, absolutePath);
    const basename = path.basename(relativePath).toLowerCase();
    const extension = path.extname(relativePath).toLowerCase();
    if (![".json", ".md", ".log", ".trace"].includes(extension)) return;
    if (
      basename.includes("report") ||
      basename.includes("fixture") ||
      relativePath.includes("/Fixtures/") ||
      relativePath.includes("/fixtures/")
    ) {
      files.push(relativePath);
    }
  }
}

if (args.includes("--help")) {
  console.log("Usage: node scripts/privacy_artifact_safety_check.mjs --fixtures | --public-artifacts | <artifact-file>...");
  process.exit(0);
}

if (args.length === 0 || args.includes("--fixtures")) {
  const result = validateFixtures();
  console.log(JSON.stringify({ ok: true, ...result }, null, 2));
} else if (args.includes("--public-artifacts")) {
  const files = publicArtifactFiles();
  for (const file of files) validateFile(file);
  console.log(JSON.stringify({ ok: true, checkedFiles: files.length }, null, 2));
} else {
  for (const file of args) validateFile(file);
  console.log(JSON.stringify({ ok: true, checkedFiles: args.length }, null, 2));
}
