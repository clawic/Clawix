#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const args = new Set(process.argv.slice(2));
const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const siblingClawjsDir = process.env.CLAWJS_ROOT
  ? path.resolve(process.env.CLAWJS_ROOT)
  : path.resolve(rootDir, "..", "..", "clawjs");
const errors = [];

function fail(message) {
  errors.push(message);
}

function filePath(baseDir, relativePath) {
  return path.join(baseDir, relativePath);
}

function exists(baseDir, relativePath) {
  return fs.existsSync(filePath(baseDir, relativePath));
}

function read(baseDir, relativePath) {
  const absolutePath = filePath(baseDir, relativePath);
  if (!fs.existsSync(absolutePath)) {
    fail(`missing ${path.relative(rootDir, absolutePath)}`);
    return "";
  }
  return fs.readFileSync(absolutePath, "utf8");
}

function normalize(text) {
  return text.replace(/\s+/g, " ").trim();
}

function requireSnippet(baseDir, relativePath, snippet, label) {
  const text = normalize(read(baseDir, relativePath));
  if (!text.includes(normalize(snippet))) {
    fail(`${label} ${relativePath} is missing ${JSON.stringify(snippet)}`);
  }
}

function requireAnySnippet(baseDir, relativePaths, snippet, label) {
  const expected = normalize(snippet);
  for (const relativePath of relativePaths) {
    if (normalize(read(baseDir, relativePath)).includes(expected)) return;
  }
  fail(`${label} mirror set is missing ${JSON.stringify(snippet)} in ${relativePaths.join(", ")}`);
}

function requireLocalReference(localPaths, siblingPath, topic) {
  const reference = siblingPath.replaceAll("\\", "/");
  for (const localPath of localPaths) {
    if (read(rootDir, localPath).includes(reference)) return;
  }
  fail(`${topic} mirror must reference sibling ClawJS ${reference}`);
}

function scanForContradictions(relativePaths) {
  const contradictions = [
    {
      pattern: /\bClawix\b[^.\n]{0,100}\b(?:owns|is the source of truth for|becomes the source of truth for)\b[^.\n]{0,100}\b(?:framework contracts|framework schemas|framework storage|public `?claw`? CLI|domain APIs)\b/i,
      reason: "ClawJS owns framework contracts, schemas, storage resolution, domain APIs, and the public claw CLI",
    },
    {
      pattern: /\bClawix\b[^.\n]{0,120}\b(?:owns|defines|is the source of truth for|becomes the source of truth for)\b[^.\n]{0,120}\b(?:remote contracts|Relay API|remote source of truth|Gateway contracts|Sync authority manifests)\b/i,
      reason: "ClawJS owns remote, Relay, Gateway, and Sync contracts",
    },
    {
      pattern: /\b(?:new workspace writes|workspace framework data|framework workspace data)\b[^.\n]{0,80}\b(?:use|uses|belong under|live under)\b[^.\n]{0,40}\.clawjs\//i,
      reason: "new workspace-local framework writes use .claw/",
      skipWhen: /\b(?:must not|not a new-write|retired|no longer)\b/i,
    },
    {
      pattern: /\bofficial Clawix\b[^.\n]{0,120}\b(?:forbids|prohibits|blocks|disallows)\b[^.\n]{0,80}\b(?:forks?|source builds?|commercial use|compatible implementations)\b/i,
      reason: "official trust is separate from open compatibility",
    },
    {
      pattern: /\bClawix\b[^.\n]{0,120}\b(?:owns|sets|defines)\b[^.\n]{0,80}\bpre_v1_mutable\b/i,
      reason: "ClawJS is the canonical source of pre-V1 version governance",
    },
  ];

  for (const relativePath of relativePaths) {
    const text = read(rootDir, relativePath);
    const lines = text.split("\n");
    for (const [index, line] of lines.entries()) {
      for (const contradiction of contradictions) {
        if (contradiction.skipWhen?.test(line)) continue;
        if (contradiction.pattern.test(line)) {
          fail(`${relativePath}:${index + 1} contradicts ClawJS mirror canon: ${contradiction.reason}`);
        }
      }
    }
  }
}

function runSelfTest() {
  const sourceOfTruth = "ClawJS owns framework contracts, schemas, storage resolution, domain APIs, and the public claw CLI.";
  assert.match(sourceOfTruth, /ClawJS owns framework contracts/);
  assert.equal(
    /\bClawix\b[^.\n]{0,100}\b(?:owns|is the source of truth for|becomes the source of truth for)\b[^.\n]{0,100}\b(?:framework contracts|framework schemas|framework storage|public `?claw`? CLI|domain APIs)\b/i.test(
      "Clawix owns framework contracts.",
    ),
    true,
  );
  assert.equal(
    /\bofficial Clawix\b[^.\n]{0,120}\b(?:forbids|prohibits|blocks|disallows)\b[^.\n]{0,80}\b(?:forks?|source builds?|commercial use|compatible implementations)\b/i.test(
      "official Clawix forbids forks.",
    ),
    true,
  );
  assert.equal(normalize("claw inspect   version-governance").includes(normalize("claw inspect version-governance")), true);
  console.error("ClawJS mirror contradiction self-test passed");
}

if (args.has("--self-test")) {
  runSelfTest();
  process.exit(0);
}

const localMirrorDocs = [
  "CONSTITUTION.md",
  "AGENTS.md",
  "docs/agent-rules/index.md",
  "docs/decision-map.md",
  "docs/host-ownership.md",
  "docs/data-storage-boundary.md",
  "docs/naming-style-guide.md",
  "docs/adr/0001-claw-framework-host-boundary.md",
  "docs/adr/0002-naming-and-stability-surfaces.md",
  "docs/adr/0011-surface-route-graph.md",
  "docs/adr/0020-open-standard-official-trust-mirror.md",
  "docs/pre-v1-version-governance.md",
  "FORKS.md",
  "TRADEMARKS.md",
];

for (const relativePath of localMirrorDocs) read(rootDir, relativePath);
scanForContradictions(localMirrorDocs);

const mirrorGroups = [
  {
    topic: "constitution",
    sibling: ["CONSTITUTION.md", "docs/constitution-map.md"],
    local: ["CONSTITUTION.md", "docs/constitution-map.md", "docs/decision-map.md"],
    siblingRequired: [
      "They are two faces of the same project",
      "The two copies of this constitution",
      "Remote framework access is organized as Coordinator, Gateway, Connector, and Sync",
    ],
    localRequired: [
      "They are two faces of the same project",
      "The two copies of this constitution",
      "Remote framework access is organized as Coordinator, Gateway, Connector, and Sync",
    ],
  },
  {
    topic: "host ownership",
    sibling: ["docs/host-ownership.md", "packages/clawjs-core/src/domain-ownership.ts"],
    local: ["docs/host-ownership.md", "docs/adr/0001-claw-framework-host-boundary.md", "docs/decision-map.md"],
    references: ["docs/host-ownership.md"],
    siblingRequired: [
      "ClawJS/Claw is the framework. It owns public contracts",
      "Clawix is the human interface and an embedded signed host",
      "Clawix has no duplicated canonical store for that domain",
    ],
    localRequired: [
      "ClawJS/Claw is the framework. It owns public contracts",
      "Clawix is the native human interface and an embedded signed host",
      "ClawJS/Claw owns framework contracts, schemas, fixtures, storage resolution, domain APIs, and the public `claw` CLI",
    ],
  },
  {
    topic: "storage",
    sibling: ["docs/data-storage-boundary.md", "packages/clawjs-core/src/storage.ts"],
    local: ["docs/data-storage-boundary.md", "docs/decision-map.md", "docs/adr/0002-naming-and-stability-surfaces.md"],
    references: ["docs/data-storage-boundary.md"],
    siblingRequired: [
      "Clawix host-operational root: `~/.clawix`",
      "Older `.clawjs/` workspace paths",
      "`core.sqlite` is the main framework database. It stores user-facing structured",
    ],
    localRequired: [
      "Clawix host-operational root: `~/.clawix`",
      "Older `.clawjs/` workspace paths",
      "User-facing structured records belong in `core.sqlite`",
    ],
  },
  {
    topic: "naming",
    sibling: ["docs/adr/0001-naming-and-stability-surfaces.md", "docs/naming-style-guide.md"],
    local: ["docs/adr/0002-naming-and-stability-surfaces.md", "docs/naming-style-guide.md", "docs/decision-map.md"],
    references: ["docs/adr/0001-naming-and-stability-surfaces.md", "docs/naming-style-guide.md"],
    siblingRequired: [
      "Framework/product name: `ClawJS`",
      "Public APIs live under `/v1/...`",
      "Clawix host/bridge operational home is `~/.clawix/`",
    ],
    localRequired: [
      "This ADR mirrors the canonical ClawJS naming ADR",
      "When Clawix consumes ClawJS packages, ports, APIs, schemas, database names, or domain names, use the ClawJS naming ADR as the source of truth.",
      "ClawJS service ports live in `24100-24199` and are consumed from the ClawJS registry, not duplicated in Clawix.",
    ],
  },
  {
    topic: "route graph",
    sibling: ["docs/adr/0012-surface-route-graph.md"],
    local: ["docs/adr/0011-surface-route-graph.md", "docs/decision-map.md"],
    references: [],
    siblingRequired: [
      "ClawJS and Clawix have many compatibility-sensitive surfaces",
      "Generated diagrams remain views; the registry is the source of truth.",
      "Relay is registered as a first-class critical node.",
    ],
    localRequired: [
      "The canonical surface route graph lives in ClawJS",
      "ClawJS remains the source of truth for the complete method-route list.",
      "claw inspect show|neighbors|routes|route",
    ],
  },
  {
    topic: "official trust",
    sibling: ["docs/adr/0033-open-standard-official-trust.md", "docs/official-trust-and-compatibility.md"],
    local: ["docs/adr/0020-open-standard-official-trust-mirror.md", "FORKS.md", "TRADEMARKS.md", "docs/decision-map.md"],
    references: ["docs/adr/0033-open-standard-official-trust.md"],
    siblingRequired: [
      "ClawJS is MIT-licensed and intentionally buildable, forkable, and extensible.",
      "`official`: produced or distributed by upstream.",
      "`compatible`: implements a stated Claw contract without being upstream.",
    ],
    localRequired: [
      "Clawix source code and documentation remain under the repository license",
      "`official Clawix` is reserved",
      "`official`, `source`, `community`, and `compatible`",
    ],
  },
  {
    topic: "remote",
    sibling: ["docs/adr/0022-remote-gateway-sync-redesign.md", "docs/relay.md"],
    local: ["docs/adr/0011-surface-route-graph.md", "docs/decision-map.md", "docs/interface-matrix.md"],
    references: ["docs/adr/0022-remote-gateway-sync-redesign.md", "docs/relay.md"],
    siblingRequired: [
      "Remote access is therefore not a side API.",
      "Remote framework access has four canonical layers",
      "RemoteExternalPendingRegister",
      "/v1/remote/route-contracts",
      "SyncAuthorityHandoffReceipt",
    ],
    localRequired: [
      "Clawix remote mesh UI and companion clients consume the framework-owned Coordinator/Gateway/Connector/Sync model",
      "Clawix route manifests must stay consumers of the framework graph",
      "RemoteExternalPendingRegister",
      "RemoteRouteContractCatalog",
      "SyncAuthorityHandoffReceipt",
    ],
  },
  {
    topic: "version governance",
    sibling: ["docs/adr/0025-pre-v1-version-governance.md", "packages/clawjs-core/src/version-governance.ts"],
    local: ["docs/pre-v1-version-governance.md", "docs/decision-map.md", "docs/adr/0002-naming-and-stability-surfaces.md"],
    references: ["docs/adr/0025-pre-v1-version-governance.md", "packages/clawjs-core/src/version-governance.ts"],
    siblingRequired: [
      "ClawJS is the canonical source of version governance",
      'phase: "pre_v1_mutable"',
      'sourceOfTruth: "clawjs"',
      "claw inspect version-governance --json",
    ],
    localRequired: [
      "Clawix consumes the canonical ClawJS version-governance policy.",
      "pre_v1_mutable",
      "claw inspect version-governance --json",
      "bridge/API/schema/protocol/file-format/surface version bumps require explicit user approval",
    ],
  },
];

const siblingAvailable = fs.existsSync(siblingClawjsDir);
if (!siblingAvailable) {
  console.error(`PARTIAL ClawJS mirror contradiction check: sibling ClawJS repo not found at ${siblingClawjsDir}`);
} else {
  for (const group of mirrorGroups) {
    for (const siblingPath of group.sibling) {
      if (!exists(siblingClawjsDir, siblingPath)) {
        fail(`${group.topic} canonical sibling source is missing: ${siblingPath}`);
      }
    }
    for (const snippet of group.siblingRequired) {
      requireAnySnippet(siblingClawjsDir, group.sibling, snippet, `sibling ${group.topic}`);
    }
    for (const siblingPath of group.references ?? []) {
      requireLocalReference(group.local, siblingPath, group.topic);
    }
  }
}

for (const group of mirrorGroups) {
  for (const localPath of group.local) read(rootDir, localPath);
  for (const snippet of group.localRequired) {
    requireAnySnippet(rootDir, group.local, snippet, `local ${group.topic}`);
  }
}

for (const [relativePath, snippet] of [
  ["docs/decision-map.md", "node scripts/clawjs_mirror_contradiction_check.mjs"],
  ["docs/agent-rules/index.md", "scripts/clawjs_mirror_contradiction_check.mjs"],
  ["scripts/test.sh", "scripts/clawjs_mirror_contradiction_check.mjs"],
]) {
  requireSnippet(rootDir, relativePath, snippet, "local guardrail routing");
}

if (errors.length > 0) {
  console.error(`ClawJS mirror contradiction check failed (${errors.length})`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.error("ClawJS mirror contradiction check passed");
