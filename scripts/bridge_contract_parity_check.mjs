#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const fixtureRoot = path.join(rootDir, "packages/ClawixCore/Fixtures/BridgeV1");
const manifestPath = path.join(fixtureRoot, "manifest.json");
const requiredPlatforms = new Set(["swift", "web", "android", "windows"]);
const requiredFiles = [
  "packages/ClawixCore/Sources/BridgeProtocolFixtures/BridgeFixtures.swift",
  "packages/ClawixCore/Tests/ClawixCoreTests/BridgeProtocolContractValidatorTests.swift",
  "web/tests/unit/wire.test.ts",
  "android/app/src/test/java/com/example/clawix/android/BridgeFrameRoundtripTest.kt",
  "android/app/build.gradle.kts",
  "windows/Clawix.Tests/BridgeFixtureParityTests.cs",
  "windows/Clawix.Tests/Clawix.Tests.csproj",
];

function read(file) {
  return fs.readFileSync(path.join(rootDir, file), "utf8");
}

function fail(errors, message) {
  errors.push(message);
}

function parseJson(file, errors) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(errors, `${path.relative(rootDir, file)} is not valid JSON: ${error.message}`);
    return null;
  }
}

function checkManifest(errors) {
  if (!fs.existsSync(manifestPath)) {
    fail(errors, "missing packages/ClawixCore/Fixtures/BridgeV1/manifest.json");
    return null;
  }
  const manifest = parseJson(manifestPath, errors);
  if (!manifest) return null;
  if (manifest.schemaVersion !== 1) fail(errors, "Bridge V1 manifest schemaVersion must be 1");
  if (manifest.contractId !== "clawix.protocol.bridge.v1") fail(errors, "Bridge V1 manifest must target clawix.protocol.bridge.v1");
  if (manifest.bridgeSchemaVersion !== 1) fail(errors, "Bridge V1 manifest bridgeSchemaVersion must be 1");
  if (manifest.source !== "packages/ClawixCore/Sources/BridgeProtocolFixtures/BridgeFixtures.swift") {
    fail(errors, "Bridge V1 manifest source must be BridgeFixtures.swift");
  }
  if (!Array.isArray(manifest.fixtures)) fail(errors, "Bridge V1 manifest fixtures must be an array");
  if (!Number.isInteger(manifest.fixtureCount) || manifest.fixtureCount !== manifest.fixtures?.length) {
    fail(errors, "Bridge V1 manifest fixtureCount must match fixtures.length");
  }

  const seen = new Set();
  for (const [index, fixture] of (manifest.fixtures ?? []).entries()) {
    const label = `fixtures[${index}]`;
    if (fixture.index !== index + 1) fail(errors, `${label} index must be ${index + 1}`);
    if (!fixture.name || fixture.type !== fixture.name) fail(errors, `${label} type must match name`);
    if (!["clientToDaemon", "daemonToClient"].includes(fixture.direction)) fail(errors, `${label} has invalid direction`);
    if (!fixture.file || !fixture.file.endsWith(`-${fixture.name}.json`)) fail(errors, `${label} file must end with -${fixture.name}.json`);
    if (seen.has(fixture.name)) fail(errors, `duplicate Bridge V1 fixture ${fixture.name}`);
    seen.add(fixture.name);

    const filePath = path.join(fixtureRoot, fixture.file ?? "");
    if (!fs.existsSync(filePath)) {
      fail(errors, `${label} missing fixture file ${fixture.file}`);
      continue;
    }
    const payload = parseJson(filePath, errors);
    if (!payload) continue;
    if (payload.schemaVersion !== manifest.bridgeSchemaVersion) fail(errors, `${fixture.file} schemaVersion mismatch`);
    if (payload.type !== fixture.type) fail(errors, `${fixture.file} type mismatch`);
    if (payload.payload !== undefined) fail(errors, `${fixture.file} must not contain payload envelope`);
  }

  const jsonFiles = fs.readdirSync(fixtureRoot).filter((file) => file.endsWith(".json") && file !== "manifest.json");
  if (jsonFiles.length !== manifest.fixtureCount) fail(errors, "Bridge V1 fixture directory file count must match manifest.fixtureCount");

  const validators = new Set((manifest.platformValidators ?? []).map((entry) => entry.platform));
  for (const platform of requiredPlatforms) {
    if (!validators.has(platform)) fail(errors, `Bridge V1 manifest missing ${platform} platform validator`);
  }
  return manifest;
}

function checkConsumers(errors) {
  for (const file of requiredFiles) {
    if (!fs.existsSync(path.join(rootDir, file))) fail(errors, `missing Bridge V1 parity consumer ${file}`);
  }

  const expectations = [
    ["packages/ClawixCore/Tests/ClawixCoreTests/BridgeProtocolContractValidatorTests.swift", "Fixtures"],
    ["packages/ClawixCore/Tests/ClawixCoreTests/BridgeProtocolContractValidatorTests.swift", "BridgeV1"],
    ["web/tests/unit/wire.test.ts", "packages/ClawixCore/Fixtures/BridgeV1"],
    ["android/app/build.gradle.kts", "packages/ClawixCore/Fixtures/BridgeV1"],
    ["android/app/src/test/java/com/example/clawix/android/BridgeFrameRoundtripTest.kt", "manifest.json"],
    ["windows/Clawix.Tests/Clawix.Tests.csproj", "packages\\ClawixCore\\Fixtures\\BridgeV1\\*.json"],
    ["windows/Clawix.Tests/BridgeFixtureParityTests.cs", "CanonicalBridgeFixtures"],
  ];
  for (const [file, snippet] of expectations) {
    if (fs.existsSync(path.join(rootDir, file)) && !read(file).includes(snippet)) {
      fail(errors, `${file} must reference ${snippet}`);
    }
  }
}

function checkLegacyWindowsMirror(errors, manifest) {
  const legacyRoot = path.join(rootDir, "windows/Clawix.Tests/Fixtures");
  if (!manifest || !fs.existsSync(legacyRoot)) return;
  const legacyFiles = fs.readdirSync(legacyRoot).filter((file) => file.endsWith(".json")).sort();
  if (legacyFiles.length === 0) return;
  const expectedFiles = manifest.fixtures.map((fixture) => fixture.file).sort();
  if (legacyFiles.join("\n") !== expectedFiles.join("\n")) {
    fail(errors, "windows/Clawix.Tests/Fixtures must mirror the generated Bridge V1 corpus when present");
    return;
  }
  for (const file of expectedFiles) {
    const canonical = fs.readFileSync(path.join(fixtureRoot, file), "utf8");
    const legacy = fs.readFileSync(path.join(legacyRoot, file), "utf8");
    if (canonical !== legacy) fail(errors, `legacy Windows fixture diverges from generated corpus: ${file}`);
  }
}

const errors = [];
const manifest = checkManifest(errors);
checkConsumers(errors);
checkLegacyWindowsMirror(errors, manifest);

if (errors.length > 0) {
  console.error("Bridge contract parity check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`Bridge contract parity check passed (${manifest.fixtureCount} fixtures, ${requiredPlatforms.size} platform validators).`);
