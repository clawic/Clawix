#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANONICAL="$ROOT/docs/persistent-surface-clawix.manifest.json"
RESOURCE="$ROOT/macos/Sources/Clawix/Resources/persistent-surface-clawix.manifest.json"
SURFACE_ROUTE_REGISTRY="$ROOT/docs/surface-route-registry.manifest.json"
OUT_ARG="${1:-"$CANONICAL"}"
if [[ "$OUT_ARG" = /* ]]; then
  OUT="$OUT_ARG"
else
  OUT="$ROOT/$OUT_ARG"
fi

node - "$CANONICAL" "$RESOURCE" "$OUT" "$SURFACE_ROUTE_REGISTRY" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [canonicalPath, resourcePath, outPath, surfaceRouteRegistryPath] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(canonicalPath, "utf8"));
const surfaceRouteRegistry = JSON.parse(fs.readFileSync(surfaceRouteRegistryPath, "utf8"));
if (!Number.isInteger(manifest.version)) {
  throw new Error("persistent surface manifest is missing integer version");
}
if (!Array.isArray(manifest.nodes)) {
  throw new Error("persistent surface manifest is missing nodes[]");
}
const ids = new Set();
for (const node of manifest.nodes) {
  if (!node || typeof node.id !== "string" || node.id.length === 0) {
    throw new Error("persistent surface manifest contains a node without id");
  }
  if (ids.has(node.id)) {
    throw new Error(`persistent surface manifest contains duplicate node id ${node.id}`);
  }
  ids.add(node.id);
}
manifest.surfaceRouteRegistry = {
  sourceManifest: "docs/surface-route-registry.manifest.json",
  generatedSwift: surfaceRouteRegistry.generatedSwift,
  generator: "scripts/generate-surface-route-registry.mjs",
  version: surfaceRouteRegistry.version,
  routeCount: Array.isArray(surfaceRouteRegistry.routes) ? surfaceRouteRegistry.routes.length : 0,
  modules: surfaceRouteRegistry.modules ?? [],
  dependencies: surfaceRouteRegistry.dependencies ?? [],
  readinessModes: surfaceRouteRegistry.readinessModes ?? [],
};
const pretty = JSON.stringify(manifest, null, 2)
  .replace(/"([^"\\]*(?:\\.[^"\\]*)*)":/g, '"$1" :');
const output = `${pretty}\n`;
for (const target of new Set([canonicalPath, resourcePath, outPath])) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, output);
}
NODE
