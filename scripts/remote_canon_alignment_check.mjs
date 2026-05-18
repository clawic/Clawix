#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const siblingClawjsDir = path.resolve(rootDir, "..", "..", "clawjs");
const failures = [];

function fail(message) {
  failures.push(message);
}

function read(relativePath) {
  const filePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(filePath)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(filePath, "utf8");
}

function requireSnippet(relativePath, snippet) {
  const text = read(relativePath);
  if (!text.includes(snippet)) fail(`${relativePath} is missing ${snippet}`);
}

function requireSiblingSnippet(relativePath, snippet) {
  const filePath = path.join(siblingClawjsDir, relativePath);
  if (!fs.existsSync(filePath)) return;
  const text = fs.readFileSync(filePath, "utf8");
  if (!text.includes(snippet)) fail(`sibling clawjs ${relativePath} is missing ${snippet}`);
}

for (const relativePath of [
  "CONSTITUTION.md",
  "AGENTS.md",
  "docs/decision-map.md",
  "docs/interface-matrix.md",
  "docs/adr/0011-surface-route-graph.md",
]) {
  read(relativePath);
}

for (const snippet of [
  "Coordinator",
  "Gateway",
  "Connector",
  "Sync",
  "sovereign E2E",
  "Gateway-governed",
  "remote-safe",
  "local-only",
  "blocked",
  "pending",
  "brokered secret leases",
  "Sync authority handoff",
  "RemoteExternalPendingRegister",
  "RemoteRouteContractCatalog",
  "claw inspect remote",
]) {
  requireSnippet("CONSTITUTION.md", snippet);
}

for (const snippet of [
  "claw remote pending",
  "claw remote contracts",
  "claw inspect remote",
  "claw sync handoff",
  "claw gateway audit",
  "claw gateway secret-provider",
  "Clawix route manifests must stay consumers of the framework graph",
]) {
  requireSnippet("docs/decision-map.md", snippet);
}

for (const snippet of [
  "remote conformance",
  "RemoteExternalPendingRegister",
  "RemoteRouteContractCatalog",
  "SyncAuthorityHandoffReceipt",
  "claw inspect remote",
]) {
  requireSnippet("docs/interface-matrix.md", snippet);
  requireSnippet("docs/adr/0011-surface-route-graph.md", snippet);
}

for (const snippet of [
  "docs/adr/0022-remote-gateway-sync-redesign.md",
  "docs/relay.md",
]) {
  requireSnippet("docs/decision-map.md", snippet);
  requireSiblingSnippet(snippet, "Coordinator");
}

if (failures.length > 0) {
  console.error(`remote canon alignment failed (${failures.length})`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.error("remote canon alignment passed");
